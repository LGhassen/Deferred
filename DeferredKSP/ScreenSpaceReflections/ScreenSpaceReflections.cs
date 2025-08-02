using UnityEngine;
using UnityEngine.Rendering;
using System.Collections.Generic;
using static Deferred.RenderingUtils;

namespace Deferred
{
    public class ScreenSpaceReflections : MonoBehaviour
    {
        static Dictionary<Camera, ScreenSpaceReflections> CameraToSSR = new Dictionary<Camera, ScreenSpaceReflections>();

        public static bool RegisterScattererOceanForCamera(Camera cam, out bool halfResolution)
        {
            if (CameraToSSR.TryGetValue(cam, out ScreenSpaceReflections ssr))
            {
                if (!ssr.scattererOceanEnabled)
                { 
                    ssr.scattererOceanEnabled = true;
                    ssr.RecreateTexturesAndBuffers(1, true);
                }
                halfResolution = ssr.useHalfResolutionTracing;
                return true;
            }

            halfResolution = false;
            return false;
        }

        public static bool UnregisterScattererOceanForCamera(Camera cam)
        {
            if (CameraToSSR.TryGetValue(cam, out ScreenSpaceReflections ssr))
            {
                ssr.scattererOceanEnabled = false;
                ssr.RecreateTexturesAndBuffers(1, true);
                return true;
            }

            return false;
        }

        Camera targetCamera;

        // When VR is enabled we have different commandBuffers per eye
        HistoryManager<CommandBuffer> ssrCommandBuffer, screenCopyCommandBuffer;

        // These are per-eye flip-flop for VR support
        HistoryManager<RenderTexture> screenColor;

        // These textures are flip-flop only
        HistoryManager<RenderTexture> hiZTextures, ssrColor, ssrHitDistance;

        // These textures are only used with the scatterer ocean, the idea is to precombined these textures
        // Instead of combining them at every tracing/blurring step
        RenderTexture combinedGBufferAndOceanNormalsAndSmoothness, oceanMask;

        public Material ssrMaterial, blurMaterial, generateHiZMaterial;
        public ComputeShader generateHiZComputeShader;

        Mesh quadMesh;

        bool useHalfResolutionTracing = true;

        bool useComputeForHiZ = true;
        bool isRunningOpenGL = false;
        bool supportVR = false;
        bool useHDR = false;
        bool ssrScreenShotModeEnabled = false;
        bool scattererOceanEnabled = false;

        public static class SsrShaderPassName
        {
            public const int Compose = 0;
            public const int TraceRays = 1;
            public const int ReprojectGbufferShading = 2;
            public const int CombineGbufferAndOcean = 3;
        }

        public static class BlurShaderPassName
        {
            public const int DownsampleAndBlurHorizontal = 0;
            public const int BlurVertical = 1;
            public const int NormalsAwareBlurCombined = 2;
            public const int NormalsAwareBlurVertical = 3;
        }

        // Motion vectors render after skybox and before image effects, we need to use this event
        // to have motion vectors To reproject last frame's lighting+reflections+transparencies
        public const CameraEvent SSRCameraEvent = CameraEvent.BeforeImageEffectsOpaque;

        // This will be done after TAA, they use the same event but TAA's CB is added earlier in OnPreCull
        public const CameraEvent ScreenCopyCameraEvent = CameraEvent.AfterForwardAlpha;


        public void Init(bool useHalfResolutionTracing)
        {
            this.useHalfResolutionTracing = useHalfResolutionTracing;
        }

        private void Start()
        {
            targetCamera = GetComponent<Camera>();
            
            if (CameraToSSR.ContainsKey(targetCamera))
            {
                Destroy(this);
                return;
            }

            CameraToSSR.Add(targetCamera, this);

            ssrMaterial = new Material(ShaderLoader.DeferredShaders["Deferred/ScreenSpaceReflections"]);
            blurMaterial = new Material(ShaderLoader.DeferredShaders["Deferred/Blur"]);
            generateHiZMaterial = new Material(ShaderLoader.DeferredShaders["Deferred/GenerateHiZ"]);

            generateHiZComputeShader = ShaderLoader.ComputeShaders["GenerateHiZ"];

            useComputeForHiZ = SystemInfo.supportsComputeShaders;
            isRunningOpenGL = SystemInfo.graphicsDeviceVersion.Contains("OpenGL");

            var go = GameObject.CreatePrimitive(PrimitiveType.Quad);
            quadMesh = Mesh.Instantiate(go.GetComponent<MeshFilter>().sharedMesh);
            Destroy(go);

            RecreateTexturesAndBuffers(1, false);
        }

        private void RecreateTexturesAndBuffers(int supersizingFactor, bool keepScreenHistory)
        {
            supportVR = VREnabled();
            useHDR = targetCamera.allowHDR;

            GetCameraRenderDimensions(targetCamera, out int cameraWidth, out int cameraHeight);

            int screenMipCount = CalculateMipLevel(cameraWidth, cameraHeight, 8);
            int hizMipCount = screenMipCount - 1; // Don't copy the built-in camera depth texture into mip 0, reuse it to save one mip

            bool halfResolutionTracing = useHalfResolutionTracing && supersizingFactor <= 1;

            int tracingWidth = halfResolutionTracing ? cameraWidth / 2 : cameraWidth;
            int tracingHeight = cameraHeight;

            CreateOrResizeRenderTextures(hizMipCount, cameraWidth, cameraHeight, tracingWidth, tracingHeight, supportVR, useHDR, keepScreenHistory, scattererOceanEnabled);
            SetShaderProperties(screenMipCount, cameraWidth, cameraHeight, halfResolutionTracing, scattererOceanEnabled);
            RecreateCommandBuffers(cameraWidth, cameraHeight, screenMipCount, hizMipCount, halfResolutionTracing, scattererOceanEnabled);
        }

        private void RecreateCommandBuffers(int cameraWidth, int cameraHeight, int screenMipCount, int hizMipCount, bool halfResolutionTracing, bool scattererOcean)
        {
            if (ssrCommandBuffer != null)
            {
                ReleaseCBHistoryManager(ssrCommandBuffer);
            }

            ssrCommandBuffer = new HistoryManager<CommandBuffer>(false, supportVR, false);
            ssrCommandBuffer[false, true, 0] = CreateSSRCommandBuffer(screenMipCount, hizMipCount, true, cameraWidth, cameraHeight, halfResolutionTracing, scattererOcean);

            if (supportVR)
            {
                ssrCommandBuffer[false, false, 0] = CreateSSRCommandBuffer(screenMipCount, hizMipCount, false, cameraWidth, cameraHeight, halfResolutionTracing, scattererOcean);
            }

            if (screenCopyCommandBuffer != null)
            {
                ReleaseCBHistoryManager(screenCopyCommandBuffer);
            }

            screenCopyCommandBuffer = new HistoryManager<CommandBuffer>(false, supportVR, false);
            screenCopyCommandBuffer[false, true, 0] = CreateScreenCopyCommandBuffer(true);
            if (supportVR)
            {
                screenCopyCommandBuffer[false, false, 0] = CreateScreenCopyCommandBuffer(false);
            }
        }

        private void SetShaderProperties(int screenMipCount, int cameraWidth, int cameraHeight, bool halfResolutionTracing, bool scattererOcean)
        {
            if (halfResolutionTracing)
            {
                ssrMaterial.EnableKeyword("HALF_RESOLUTION_TRACING");
                blurMaterial.EnableKeyword("HALF_RESOLUTION_TRACING");
            }
            else
            {
                ssrMaterial.DisableKeyword("HALF_RESOLUTION_TRACING");
                blurMaterial.DisableKeyword("HALF_RESOLUTION_TRACING");
            }

            if (scattererOcean)
            {
                ssrMaterial.EnableKeyword("PRECOMBINED_NORMALS_AND_SMOOTHNESS");
                blurMaterial.EnableKeyword("PRECOMBINED_NORMALS_AND_SMOOTHNESS");

                ssrMaterial.SetTexture("combinedGBufferAndOceanNormalsAndSmoothness", combinedGBufferAndOceanNormalsAndSmoothness);
                ssrMaterial.SetTexture("oceanMask", oceanMask);

                blurMaterial.SetTexture("combinedGBufferAndOceanNormalsAndSmoothness", combinedGBufferAndOceanNormalsAndSmoothness);
                blurMaterial.SetTexture("oceanMask", oceanMask);
            }
            else
            {
                ssrMaterial.DisableKeyword("PRECOMBINED_NORMALS_AND_SMOOTHNESS");
                blurMaterial.DisableKeyword("PRECOMBINED_NORMALS_AND_SMOOTHNESS");
            }

            ssrMaterial.SetInt("hiZMipLevelCount", screenMipCount);
            ssrMaterial.SetVector("SSRScreenResolution", new Vector2(cameraWidth, cameraHeight));
            blurMaterial.SetVector("SSRScreenResolution", new Vector2(cameraWidth, cameraHeight));

            ssrMaterial.SetTexture("hiZTexture", hiZTextures[true, false, 0]);
            blurMaterial.SetTexture("ssrHitDistance", ssrHitDistance[true, false, 0]);
        }

        private CommandBuffer CreateSSRCommandBuffer(int screenMipCount, int hizMipCount, bool isVRRightEye, int cameraWidth, int cameraHeight, bool halfResolutionTracing, bool scattererOcean)
        {
            CommandBuffer commandBuffer = new CommandBuffer();
            commandBuffer.name = "Deferred ScreenSpace Reflections CommandBuffer";

            GenerateHiZ(hizMipCount, commandBuffer, cameraWidth, cameraHeight);

            ReprojectAndBlurScreenTexture(commandBuffer, isVRRightEye, cameraWidth, cameraHeight);

            if (scattererOcean)
            {
                // Combine gbuffer info with ocean gbuffer
                RenderTargetIdentifier[] combinedGbufferTargets = { new RenderTargetIdentifier(combinedGBufferAndOceanNormalsAndSmoothness),
                                                                    new RenderTargetIdentifier(oceanMask) };

                commandBuffer.SetRenderTarget(combinedGbufferTargets, combinedGBufferAndOceanNormalsAndSmoothness.depthBuffer);
                commandBuffer.DrawMesh(quadMesh, Matrix4x4.identity, ssrMaterial, 0, SsrShaderPassName.CombineGbufferAndOcean);
            }

            RenderTargetIdentifier[] ssrTargets = { new RenderTargetIdentifier(ssrColor[true, false, 0]),
                                                    new RenderTargetIdentifier(ssrHitDistance[true, false, 0]) };

            commandBuffer.SetRenderTarget(ssrTargets, ssrColor[true, false, 0].depthBuffer);
            commandBuffer.SetGlobalTexture("SSRScreenColor", screenColor[true, isVRRightEye, 0]);

            commandBuffer.DrawMesh(quadMesh, Matrix4x4.identity, ssrMaterial, 0, SsrShaderPassName.TraceRays);

            BlurHitDistanceTexture(commandBuffer, cameraWidth, cameraHeight);

            PerformNormalsAwareSSRBlur(commandBuffer, cameraWidth, cameraHeight, halfResolutionTracing);

            commandBuffer.SetRenderTarget(BuiltinRenderTextureType.CameraTarget);
            commandBuffer.DrawMesh(quadMesh, Matrix4x4.identity, ssrMaterial, 0, SsrShaderPassName.Compose);

            return commandBuffer;
        }

        private CommandBuffer CreateScreenCopyCommandBuffer(bool isVRRightEye)
        {
            var cb = new CommandBuffer();
            cb.name = "Deferred SSR History ScreenCopy CommandBuffer";
            cb.Blit(BuiltinRenderTextureType.CameraTarget, screenColor[false, isVRRightEye, 0]);

            return cb;
        }

        private void PerformNormalsAwareSSRBlur(CommandBuffer cb, int cameraWidth, int cameraHeight, bool halfResolutionTracing)
        {
            
            float maxScreenSizeToCover = 0.05f;
            float pixelSizeToCover = maxScreenSizeToCover * Mathf.Max(cameraWidth, cameraHeight);

            float iterations = Mathf.Ceil(Mathf.Log(pixelSizeToCover, 2f));

            bool useFlip = true;

            RenderTexture currentTarget = null;
            RenderTexture previousTarget = null;
            
            for (int iteration = 0; iteration < iterations; iteration++)
            {
                currentTarget = ssrColor[!useFlip, false, 0];
                previousTarget = ssrColor[useFlip, false, 0];

                cb.SetGlobalFloat("blurOffset", Mathf.Pow(2, iteration));
                cb.SetGlobalFloat("prevBlurOffset", Mathf.Pow(2, iteration - 1));

                cb.SetRenderTarget(currentTarget, 0);
                cb.SetGlobalTexture("deferredSSRColorBuffer", previousTarget); // TODO: rename this, it's in multiple places in the shaders

                if (iteration == 0 && halfResolutionTracing)
                {
                    cb.DrawMesh(quadMesh, Matrix4x4.identity, blurMaterial, 0, BlurShaderPassName.NormalsAwareBlurVertical);
                }
                else
                {
                    cb.DrawMesh(quadMesh, Matrix4x4.identity, blurMaterial, 0, BlurShaderPassName.NormalsAwareBlurCombined);
                }

                if (iteration == 0)
                {
                    cb.SetGlobalInt("isFirstIteration", 0);
                }

                useFlip = !useFlip;
            }

            cb.SetGlobalTexture("ssrOutput", currentTarget);  // TODO: rename property

            //cb.SetGlobalTexture("ssrOutput", ssrColor[true, false, 0]);  // TODO: rename property
        }

        // This will fuzzy out the edges of objects reflected in rough surfaces, making it look closer to the importance-sampled reference
        // I think maybe merge this with the normals aware blur method and do a description there
        // Could also make a reusable blurring method for this and the initial screenColor, code looks similar
        private void BlurHitDistanceTexture(CommandBuffer cb, int cameraWidth, int cameraHeight)
        {
            Vector2 currentMipLevelDimensions = new Vector2(cameraWidth, cameraHeight);

            cb.SetGlobalInt("mipLevelToRead", 0);

            for (int currentMipLevel = 1; currentMipLevel <= ssrHitDistance[true, false, 0].mipmapCount; currentMipLevel++)
            {
                cb.SetGlobalInt("currentMipLevel", currentMipLevel);

                currentMipLevelDimensions = new Vector2((int)(currentMipLevelDimensions.x / 2f), (int)(currentMipLevelDimensions.y / 2f));
                cb.SetGlobalVector("currentMipLevelDimensions", currentMipLevelDimensions);

                // Downscale from previous mip Level while blurring horizontally
                cb.SetRenderTarget(ssrHitDistance[false, false, 0], currentMipLevel);
                cb.SetGlobalTexture("deferredSSRColorBuffer", ssrHitDistance[true, false, 0]);
                cb.DrawMesh(quadMesh, Matrix4x4.identity, blurMaterial, 0, BlurShaderPassName.DownsampleAndBlurHorizontal);

                cb.SetGlobalInt("mipLevelToRead", currentMipLevel);

                // Do vertical blur
                cb.SetRenderTarget(ssrHitDistance[true, false, 0], currentMipLevel);
                cb.SetGlobalTexture("deferredSSRColorBuffer", ssrHitDistance[false, false, 0]);
                cb.DrawMesh(quadMesh, Matrix4x4.identity, blurMaterial, 0, BlurShaderPassName.BlurVertical);
            }
        }

        private void CreateOrResizeRenderTextures(int hizMipCount, int cameraWidth, int cameraHeight, int tracingWidth, int tracingHeight, bool supportVR, bool useHDR, bool keepScreenHistory, bool scattererOcean)
        {
            ReleaseRTHistoryManager(hiZTextures);
            ReleaseRTHistoryManager(ssrColor);
            ReleaseRTHistoryManager(ssrHitDistance);

            if (combinedGBufferAndOceanNormalsAndSmoothness != null)
            {
                combinedGBufferAndOceanNormalsAndSmoothness.Release();
                combinedGBufferAndOceanNormalsAndSmoothness = null;
            }

            if (oceanMask != null)
            {
                oceanMask.Release();
                oceanMask = null;
            }

            hiZTextures = CreateRTHistoryManager(useComputeForHiZ, false, false, cameraWidth / 2, cameraHeight / 2,
                                                    RenderTextureFormat.RFloat, true, FilterMode.Point,0, hizMipCount,
                                                    TextureDimension.Tex2D, 0, useComputeForHiZ);

            ssrColor = CreateRTHistoryManager(true, false, false, tracingWidth, tracingHeight, useHDR ? RenderTextureFormat.DefaultHDR : RenderTextureFormat.ARGB32,
                                              false, FilterMode.Bilinear);
            
            ssrHitDistance = CreateRTHistoryManager(true, false, false, tracingWidth, tracingHeight, RenderTextureFormat.RFloat,
                                              true, FilterMode.Bilinear, 0, 4);

            if (keepScreenHistory && screenColor != null)
            {
                var copyScreenColor = CreateRTHistoryManager(true, supportVR, false, cameraWidth, cameraHeight, useHDR ? RenderTextureFormat.DefaultHDR : RenderTextureFormat.ARGB32,
                     true, FilterMode.Trilinear, 16, hizMipCount + 1);

                CopyRTHistoryManager(screenColor, copyScreenColor);

                ReleaseRTHistoryManager(screenColor);
                screenColor = CreateRTHistoryManager(true, supportVR, false, cameraWidth, cameraHeight, useHDR ? RenderTextureFormat.DefaultHDR : RenderTextureFormat.ARGB32,
                                     true, FilterMode.Trilinear, 16, hizMipCount + 1);

                CopyRTHistoryManager(copyScreenColor, screenColor);
            }
            else
            {
                ReleaseRTHistoryManager(screenColor);
                screenColor = CreateRTHistoryManager(true, supportVR, false, cameraWidth, cameraHeight, useHDR ? RenderTextureFormat.DefaultHDR : RenderTextureFormat.ARGB32,
                                     true, FilterMode.Trilinear, 16, hizMipCount + 1);
            }

            if (scattererOcean)
            { 
                combinedGBufferAndOceanNormalsAndSmoothness = new RenderTexture(tracingWidth, tracingHeight, 0, RenderTextureFormat.ARGB2101010, 0);
                oceanMask = new RenderTexture(tracingWidth, tracingHeight, 0, RenderTextureFormat.R8, 0);

                combinedGBufferAndOceanNormalsAndSmoothness.Create();
                oceanMask.Create();
            }
        }

        void ReprojectAndBlurScreenTexture(CommandBuffer cb, bool isVRRightEye, int cameraWidth, int cameraHeight)
        {
            // Reproject last frame's shading to be able to reflect reflections+transparencies
            cb.SetGlobalTexture("lastFrameColor", screenColor[false, isVRRightEye, 0]);
            cb.SetGlobalTexture("currentFrameColor", BuiltinRenderTextureType.CameraTarget);
            cb.SetRenderTarget(screenColor[true, isVRRightEye, 0], 0);
            cb.DrawMesh(quadMesh, Matrix4x4.identity, ssrMaterial, 0, SsrShaderPassName.ReprojectGbufferShading);

            // TODO: Use compute shader to get rid of flip flopping
            Vector2 currentMipLevelDimensions = new Vector2(cameraWidth, cameraHeight);
            cb.SetGlobalInt("mipLevelToRead", 0);

            for (int currentMipLevel = 1; currentMipLevel < screenColor[true, isVRRightEye, 0].mipmapCount; currentMipLevel++)
            {
                cb.SetGlobalInt("currentMipLevel", currentMipLevel);

                currentMipLevelDimensions = new Vector2((int)(currentMipLevelDimensions.x / 2f), (int)(currentMipLevelDimensions.y / 2f));
                cb.SetGlobalVector("currentMipLevelDimensions", currentMipLevelDimensions);

                // Downscale from previous mip Level while blurring horizontally
                cb.SetRenderTarget(screenColor[false, isVRRightEye, 0], currentMipLevel);

                cb.SetGlobalTexture("deferredSSRColorBuffer", screenColor[true, isVRRightEye, 0]);
                cb.DrawMesh(quadMesh, Matrix4x4.identity, blurMaterial, 0, BlurShaderPassName.DownsampleAndBlurHorizontal);

                cb.SetGlobalInt("mipLevelToRead", currentMipLevel);

                // Do vertical blur
                cb.SetRenderTarget(screenColor[true, isVRRightEye, 0], currentMipLevel);
                cb.SetGlobalTexture("deferredSSRColorBuffer", screenColor[false, isVRRightEye, 0]);
                cb.DrawMesh(quadMesh, Matrix4x4.identity, blurMaterial, 0, BlurShaderPassName.BlurVertical);
            }
        }

        private void GenerateHiZ(int hizMipCount, CommandBuffer cb, int cameraWidth, int cameraHeight)
        {
            if (useComputeForHiZ)
            {
                GenerateHiZWithCompute(cb, hizMipCount, cameraWidth, cameraHeight);
            }
            else
            {
                GenerateHiZWithShader(cb, hizMipCount, cameraWidth, cameraHeight);
            }
        }

        private void GenerateHiZWithShader(CommandBuffer cb, int hizMipCount, int cameraWidth, int cameraHeight)
        {
            bool useFlip = true;

            Vector2 currentMipLevelDimensions = new Vector2(cameraWidth, cameraHeight);
            Vector2 previousMipLevelDimensions = currentMipLevelDimensions;

            for (int currentMipLevel = 0; currentMipLevel < hizMipCount; currentMipLevel++)
            {
                RenderTexture currentHiZTarget = hiZTextures[useFlip, false, 0];
                RenderTexture previousHiZTarget = hiZTextures[!useFlip, false, 0];

                cb.SetRenderTarget(currentHiZTarget, currentMipLevel);
                cb.SetGlobalTexture("PreviousHiZTexture", currentMipLevel == 0 ? new RenderTargetIdentifier(BuiltinRenderTextureType.ResolvedDepth) : previousHiZTarget);

                previousMipLevelDimensions = currentMipLevelDimensions;
                currentMipLevelDimensions = new Vector2((int)(currentMipLevelDimensions.x / 2f), (int)(currentMipLevelDimensions.y / 2f));

                cb.SetGlobalVector("hiZPreviousMipLevelDimensions", previousMipLevelDimensions);
                cb.SetGlobalVector("hiZCurrentMipLevelDimensions", currentMipLevelDimensions);
                cb.SetGlobalInt("hiZPreviousMipLevel", Mathf.Max(0, currentMipLevel - 1));
                cb.SetGlobalInt("hiZCurrentMipLevel", currentMipLevel);
                cb.SetGlobalInt("previousTextureIsFullResDepthBuffer", currentMipLevel == 0 ? 1 : 0);

                cb.DrawMesh(quadMesh, Matrix4x4.identity, generateHiZMaterial, 0, 0);

                // Unity doesn't let us read from one mip and write to another so flip-flop instead
                // This is only when not using compute
                if (!useFlip)
                {
                    cb.CopyTexture(hiZTextures[!useFlip, false, 0], 0, currentMipLevel, hiZTextures[useFlip, false, 0], 0, currentMipLevel);
                }

                useFlip = !useFlip;
            }
        }

        private void GenerateHiZWithCompute(CommandBuffer cb, int hizMipCount, int cameraWidth, int cameraHeight)
        {
            Vector2 currentMipLevelDimensions = new Vector2(cameraWidth, cameraHeight);
            Vector2 previousMipLevelDimensions = currentMipLevelDimensions;

            cb.SetComputeIntParam(generateHiZComputeShader, "usingReverseZ", SystemInfo.usesReversedZBuffer ? 1 : 0);
            cb.SetComputeIntParam(generateHiZComputeShader, "firstIteration", 1);

            cb.SetComputeTextureParam(generateHiZComputeShader, 0, "DepthTexture", new RenderTargetIdentifier(BuiltinRenderTextureType.ResolvedDepth), 0);

            for (int currentMipLevel = 0; currentMipLevel < hizMipCount; currentMipLevel++)
            {
                previousMipLevelDimensions = currentMipLevelDimensions;
                currentMipLevelDimensions = new Vector2((int)(currentMipLevelDimensions.x / 2f), (int)(currentMipLevelDimensions.y / 2f));

                cb.SetComputeTextureParam(generateHiZComputeShader, 0, "WriteRT", hiZTextures[true, false, 0], currentMipLevel);
                cb.SetComputeTextureParam(generateHiZComputeShader, 0, "ReadRT", hiZTextures[true, false, 0], Mathf.Max(currentMipLevel - 1, 0));

                cb.SetComputeVectorParam(generateHiZComputeShader, "hiZPreviousMipLevelDimensions", previousMipLevelDimensions);
                cb.SetComputeVectorParam(generateHiZComputeShader, "hiZCurrentMipLevelDimensions", currentMipLevelDimensions);

                cb.DispatchCompute(generateHiZComputeShader, 0, Mathf.CeilToInt(currentMipLevelDimensions.x / 8),
                                                                Mathf.CeilToInt(currentMipLevelDimensions.y / 8), 1);

                if (currentMipLevel == 0)
                {
                    cb.SetComputeIntParam(generateHiZComputeShader, "firstIteration", 0);
                }
            }
        }

        public static readonly int useSSROnCurrentCamera = Shader.PropertyToID("useSSROnCurrentCamera");

        void OnPreRender()
        {
            Shader.SetGlobalInt(useSSROnCurrentCamera, 1);

            if (useHDR != targetCamera.allowHDR || supportVR != VREnabled()) // also need to detect width/height changes here
            {
                RecreateTexturesAndBuffers(1, false);
            }

            if (FlightGlobals.currentMainBody != null)
                Shader.SetGlobalVector("SSRPlanetPosition", FlightGlobals.currentMainBody.transform.position);
            


            // At the moment SSR doesn't work correctly in screenshots, the hit distances are wrong and there
            // are gaps in the intersections, maybe some issue with the projection matrix
            // I also disabled screenshot supersizing for now because the reprojected history is low-res
            // and the increased resolution can cause it to run out of iterations
            /*
            bool screenShotModeEnabled = GameSettings.TAKE_SCREENSHOT.GetKeyDown();
            if (ssrScreenShotModeEnabled != screenShotModeEnabled)
            {
                int superSizingFactor = screenShotModeEnabled ? Mathf.Max(GameSettings.SCREENSHOT_SUPERSIZE, 1) : 1;

                RecreateTexturesAndBuffers(superSizingFactor, true);
                ssrScreenShotModeEnabled = screenShotModeEnabled;
            }
            */

            bool isVRRightEye = targetCamera.stereoActiveEye == Camera.MonoOrStereoscopicEye.Right;

            targetCamera.AddCommandBuffer(SSRCameraEvent, ssrCommandBuffer[true, isVRRightEye, 0]);
            targetCamera.AddCommandBuffer(ScreenCopyCameraEvent, screenCopyCommandBuffer[true, isVRRightEye, 0]);

            targetCamera.depthTextureMode = DepthTextureMode.Depth | DepthTextureMode.MotionVectors;

            if (ssrMaterial != null)
            {
                var textureSpaceProjectionMatrix = new Matrix4x4();
                textureSpaceProjectionMatrix.SetRow(0, new Vector4(0.5f, 0f, 0f, 0.5f));
                textureSpaceProjectionMatrix.SetRow(1, new Vector4(0f, 0.5f, 0f, 0.5f));

                if (isRunningOpenGL)
                {
                    // OpenGL depth is -1 to 1, normalize it to match what is stored in depth texture when tracing
                    textureSpaceProjectionMatrix.SetRow(2, new Vector4(0f, 0f, 0.5f, 0.5f));
                }
                else
                {
                    textureSpaceProjectionMatrix.SetRow(2, new Vector4(0f, 0f, 1f, 0f));
                }

                textureSpaceProjectionMatrix.SetRow(3, new Vector4(0f, 0f, 0f, 1f));

                Matrix4x4 cameraProjectionMatrix;

                if (supportVR)
                    cameraProjectionMatrix = targetCamera.GetStereoProjectionMatrix(isVRRightEye ? Camera.StereoscopicEye.Right : Camera.StereoscopicEye.Left);
                    //cameraProjectionMatrix = targetCamera.GetStereoNonJitteredProjectionMatrix(isVRRightEye ? Camera.StereoscopicEye.Right : Camera.StereoscopicEye.Left);
                else
                    cameraProjectionMatrix = targetCamera.projectionMatrix;
                    //cameraProjectionMatrix = targetCamera.nonJitteredProjectionMatrix;

                Matrix4x4 projectionMatrix = GL.GetGPUProjectionMatrix(cameraProjectionMatrix, false);
                textureSpaceProjectionMatrix *= projectionMatrix;

                ssrMaterial.SetMatrix("textureSpaceProjectionMatrix", textureSpaceProjectionMatrix); // maybe just do these in shader?
            }
        }

        void OnPostRender()
        {
            bool isVRRightEye = targetCamera.stereoActiveEye == Camera.MonoOrStereoscopicEye.Right;

            targetCamera.RemoveCommandBuffer(SSRCameraEvent, ssrCommandBuffer[true, isVRRightEye, 0]);
            targetCamera.RemoveCommandBuffer(ScreenCopyCameraEvent, screenCopyCommandBuffer[true, isVRRightEye, 0]);

            bool doneRendering = targetCamera.stereoActiveEye != Camera.MonoOrStereoscopicEye.Left;

            if (doneRendering)
            {
                Shader.SetGlobalInt(useSSROnCurrentCamera, 0);
            }
        }

        void OnDestory()
        {
            ReleaseRenderTextures();

            RemoveAndReleaseCommandBuffers();

            CameraToSSR.Remove(targetCamera);
        }

        private void RemoveAndReleaseCommandBuffers()
        {
            if (targetCamera != null)
            {
                targetCamera.RemoveCommandBuffer(SSRCameraEvent, ssrCommandBuffer[true, true, 0]);
                targetCamera.RemoveCommandBuffer(ScreenCopyCameraEvent, screenCopyCommandBuffer[true, true, 0]);

                if (supportVR)
                {
                    targetCamera.RemoveCommandBuffer(SSRCameraEvent, ssrCommandBuffer[true, false, 0]);
                    targetCamera.RemoveCommandBuffer(ScreenCopyCameraEvent, screenCopyCommandBuffer[true, false, 0]);
                }

                ReleaseCBHistoryManager(ssrCommandBuffer);
                ReleaseCBHistoryManager(screenCopyCommandBuffer);
            }
        }

        private void ReleaseRenderTextures()
        {
            ReleaseRTHistoryManager(ssrColor);
            ReleaseRTHistoryManager(ssrHitDistance);
            ReleaseRTHistoryManager(screenColor);
            ReleaseRTHistoryManager(hiZTextures);

            if (combinedGBufferAndOceanNormalsAndSmoothness != null)
            { 
                combinedGBufferAndOceanNormalsAndSmoothness.Release();
            }

            if (oceanMask != null)
            {
                oceanMask.Release();
            }
        }

        public int CalculateMipLevel(int textureWidth, int textureHeight, int targetSize)
        {
            int mipLevel = 0;

            while (textureWidth > targetSize || textureHeight > targetSize)
            {
                textureWidth = Mathf.Max(1, textureWidth / 2);
                textureHeight = Mathf.Max(1, textureHeight / 2);
                mipLevel++;
            }

            return mipLevel;
        }
    }
}