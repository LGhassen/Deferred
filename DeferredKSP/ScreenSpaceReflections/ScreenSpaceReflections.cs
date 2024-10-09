using UnityEngine;
using UnityEngine.Rendering;

namespace Deferred
{
    public class ScreenSpaceReflections : MonoBehaviour
    {
        Camera targetCamera;

        int cameraWidth, cameraHeight;

        CommandBuffer ssrCommandBuffer;

        RenderTexture hiZRTflip, hiZRTflop;
        RenderTexture screenColorFlip, screenColorFlop;

        // Should I use my flip-flop or history manager structures here?
        RenderTexture ssrColorAndConfidence, finalSsrColor, ssrHitDistance, ssrHitDistanceBlur;

        public Material ssrMaterial, blurMaterial, generateHiZMaterial;
        public ComputeShader generateHiZComputeShader;

        Mesh quadMesh;

        public bool useHalfResolutionTracing = true;
        
        bool useComputeForHiZ = true;
        bool isRunningOpenGL = false;


        private void Start()
        {
            targetCamera = GetComponent<Camera>();
            RenderingUtils.GetCameraRenderDimensions(targetCamera, out cameraWidth, out cameraHeight);

            useComputeForHiZ = SystemInfo.supportsComputeShaders;
            isRunningOpenGL  = SystemInfo.graphicsDeviceVersion.Contains("OpenGL");

            int screenMipCount = CalculateMipLevel(cameraWidth, cameraHeight, 8);
            int hizMipCount = screenMipCount - 1; // Don't copy the built-in camera depth texture into mip 0, reuse it to save one mip

            // This will need to resize when taking screenshots
            int tracingWidth = cameraWidth;
            int tracingHeight = cameraHeight;

            if (useHalfResolutionTracing)
            {
                tracingWidth /= 2;

                // Maybe move these a bit down and set all properties for materials in a single place?
                ssrMaterial.EnableKeyword("HALF_RESOLUTION_TRACING");
                blurMaterial.EnableKeyword("HALF_RESOLUTION_TRACING");
            }
            else
            {
                ssrMaterial.DisableKeyword("HALF_RESOLUTION_TRACING");
                blurMaterial.DisableKeyword("HALF_RESOLUTION_TRACING");
            }

            CreateRenderTextures(hizMipCount, tracingWidth, tracingHeight);

            var go = GameObject.CreatePrimitive(PrimitiveType.Quad);
            quadMesh = Mesh.Instantiate(go.GetComponent<MeshFilter>().sharedMesh);
            Destroy(go);


            /*
            clearAmbientCommandBuffer = new CommandBuffer();

            clearAmbientCommandBuffer.SetRenderTarget(BuiltinRenderTextureType.CameraTarget);
            clearAmbientCommandBuffer.ClearRenderTarget(false, true, UnityEngine.Color.black);

            // TODO: remove this
            targetCamera.AddCommandBuffer(CameraEvent.BeforeLighting, clearAmbientCommandBuffer);    // Clear out ambient and reflections before lighting, will add my own in the ssr shader after lighting
            */


            CreateSSRCommandBuffer(screenMipCount, hizMipCount);
        }

        private void CreateSSRCommandBuffer(int screenMipCount, int hizMipCount)
        {
            ssrCommandBuffer = new CommandBuffer();
            ssrCommandBuffer.name = "Deferred screenspace reflections";

            GenerateHiZ(hizMipCount, ssrCommandBuffer);

            ssrMaterial.SetTexture("hiZTexture", hiZRTflip);
            ssrMaterial.SetInt("hiZMipLevelCount", screenMipCount);
            ssrMaterial.SetVector("BufferSize", new Vector2(cameraWidth, cameraHeight)); // rename this variable to screen size or other
            blurMaterial.SetVector("BufferSize", new Vector2(cameraWidth, cameraHeight));
            
            BlurInputScreenTexture(ssrCommandBuffer);

            ssrCommandBuffer.SetGlobalTexture("ScreenColor", screenColorFlip); // doesn't need to be global, also rename variable

            RenderTargetIdentifier[] ssrTargets = { new RenderTargetIdentifier(ssrColorAndConfidence), new RenderTargetIdentifier(ssrHitDistance)};

            ssrCommandBuffer.SetRenderTarget(ssrTargets, ssrColorAndConfidence.depthBuffer);
            ssrCommandBuffer.DrawMesh(quadMesh, Matrix4x4.identity, ssrMaterial, 0, 1); // tracing pass

            ssrCommandBuffer.SetGlobalTexture("ssrColor", ssrColorAndConfidence);
            ssrCommandBuffer.SetGlobalTexture("ssrHitDistance", ssrHitDistance);

            BlurHitDistanceTexture();
            PerformNormalsAwareScreenBlur();
            //hiZCommandBuffer.CopyTexture(ssrColorAndConfidence, 0, 0, finalSsrColor, 0, 0);

            ssrCommandBuffer.SetGlobalTexture("ssrOutput", finalSsrColor);

            ssrCommandBuffer.SetRenderTarget(BuiltinRenderTextureType.CameraTarget);
            ssrCommandBuffer.DrawMesh(quadMesh, Matrix4x4.identity, ssrMaterial, 0, 0); // Compose pass. TODO: do it differently, also put tracing pass first

            ssrCommandBuffer.Blit(BuiltinRenderTextureType.CameraTarget, screenColorFlip); // this copies the history, remove it and make it a step to reproject first instead

            targetCamera.AddCommandBuffer(CameraEvent.AfterSkybox, ssrCommandBuffer); // change event, needs to be after motion vectors are computed
        }

        private void PerformNormalsAwareScreenBlur()
        {
            float maxScreenSizeToCover = 0.05f;
            float pixelSizeToCover = maxScreenSizeToCover * Mathf.Max(cameraWidth, cameraHeight);

            float iterations = Mathf.Ceil(Mathf.Log(pixelSizeToCover, 2f));

            bool useFlip = true;

            RenderTexture currentTarget = null;
            RenderTexture previousTarget = null;

            for (int iteration = 0; iteration < iterations; iteration++)
            {
                currentTarget = useFlip ? finalSsrColor : ssrColorAndConfidence;
                previousTarget = useFlip ? ssrColorAndConfidence : finalSsrColor;

                ssrCommandBuffer.SetGlobalFloat("blurOffset", Mathf.Pow(2, iteration));
                ssrCommandBuffer.SetGlobalFloat("prevBlurOffset", Mathf.Pow(2, iteration - 1));

                ssrCommandBuffer.SetRenderTarget(currentTarget, 0);
                ssrCommandBuffer.SetGlobalTexture("colorBuffer", previousTarget); // rename this
                ssrCommandBuffer.DrawMesh(quadMesh, Matrix4x4.identity, blurMaterial, 0, iteration == 0 ? 3 : 2); // TODO: name passes

                if (iteration == 0)
                    ssrCommandBuffer.SetGlobalInt("isFirstIteration", 0);

                useFlip = !useFlip;
            }

            ssrCommandBuffer.SetGlobalTexture("ssrColor", currentTarget);
        }

        // This will fuzzy out the edges of objects reflected in rough surfaces, making it look closer to the reference
        // I think maybe merge this with the normals aware blur method and do a description there
        // Could also make a reusable blurring method for this and the initial screenColor, code looks similar
        private void BlurHitDistanceTexture()
        {
            Vector2 currentMipLevelDimensions = new Vector2(cameraWidth, cameraHeight);

            ssrCommandBuffer.SetGlobalInt("mipLevelToRead", 0);

            // Blur mip level texture, TODO: change this to blur distance

            for (int currentMipLevel = 1; currentMipLevel <= ssrHitDistance.mipmapCount; currentMipLevel++)
            {
                ssrCommandBuffer.SetGlobalInt("currentMipLevel", currentMipLevel);

                currentMipLevelDimensions = new Vector2((int)(currentMipLevelDimensions.x / 2f), (int)(currentMipLevelDimensions.y / 2f));
                ssrCommandBuffer.SetGlobalVector("currentMipLevelDimensions", currentMipLevelDimensions);

                // Downscale from previous mip Level while blurring horizontally
                ssrCommandBuffer.SetRenderTarget(ssrHitDistanceBlur, currentMipLevel);
                ssrCommandBuffer.SetGlobalTexture("colorBuffer", ssrHitDistance);
                ssrCommandBuffer.DrawMesh(quadMesh, Matrix4x4.identity, blurMaterial, 0, 0);

                ssrCommandBuffer.SetGlobalInt("mipLevelToRead", currentMipLevel);

                // Do vertical blur
                ssrCommandBuffer.SetRenderTarget(ssrHitDistance, currentMipLevel);
                ssrCommandBuffer.SetGlobalTexture("colorBuffer", ssrHitDistanceBlur);
                ssrCommandBuffer.DrawMesh(quadMesh, Matrix4x4.identity, blurMaterial, 0, 1);
            }
        }

        private void CreateRenderTextures(int hizMipCount, int tracingWidth, int tracingHeight)
        {
            hiZRTflip = CreateRenderTexture("hiZ RT flip", cameraWidth / 2, cameraHeight / 2, RenderTextureFormat.RFloat, true, FilterMode.Point, 0, hizMipCount, TextureDimension.Tex2D, 0, useComputeForHiZ);

            if (!useComputeForHiZ)
                hiZRTflop = CreateRenderTexture("hiZ RT flop", cameraWidth / 2, cameraHeight / 2, RenderTextureFormat.RFloat, true, FilterMode.Point, 0, hizMipCount);

            screenColorFlip = CreateRenderTexture("screen color flip", cameraWidth, cameraHeight, RenderTextureFormat.ARGBHalf, true, FilterMode.Trilinear, 16, hizMipCount + 1);
            screenColorFlop = CreateRenderTexture("screen color flop", cameraWidth, cameraHeight, RenderTextureFormat.ARGBHalf, true, FilterMode.Trilinear, 16, hizMipCount + 1);

            ssrColorAndConfidence = CreateRenderTexture(tracingWidth, tracingHeight, RenderTextureFormat.ARGBHalf, false, FilterMode.Bilinear);
            finalSsrColor = CreateRenderTexture(tracingWidth, tracingHeight, RenderTextureFormat.ARGBHalf, false, FilterMode.Bilinear);

            ssrHitDistance = CreateRenderTexture(tracingWidth, tracingHeight, RenderTextureFormat.RFloat, true, FilterMode.Bilinear, 0, 4);
            ssrHitDistanceBlur = CreateRenderTexture(tracingWidth, tracingHeight, RenderTextureFormat.RFloat, true, FilterMode.Bilinear, 0, 4);
        }

        void BlurInputScreenTexture(CommandBuffer cb)
        {
            //hiZCommandBuffer.Blit(BuiltinRenderTextureType.CameraTarget, screenColorFlip);

            // TODO: Use compute shader to get rid of flip flopping

            Vector2 currentMipLevelDimensions = new Vector2(cameraWidth, cameraHeight);
            cb.SetGlobalInt("mipLevelToRead", 0);

            for (int currentMipLevel = 1; currentMipLevel < screenColorFlip.mipmapCount; currentMipLevel++)
            {
                cb.SetGlobalInt("currentMipLevel", currentMipLevel);

                currentMipLevelDimensions = new Vector2((int)(currentMipLevelDimensions.x / 2f), (int)(currentMipLevelDimensions.y / 2f));
                cb.SetGlobalVector("currentMipLevelDimensions", currentMipLevelDimensions);

                // Downscale from previous mip Level while blurring horizontally
                cb.SetRenderTarget(screenColorFlop, currentMipLevel);
                cb.SetGlobalTexture("colorBuffer", screenColorFlip);
                cb.DrawMesh(quadMesh, Matrix4x4.identity, blurMaterial, 0, 0);

                cb.SetGlobalInt("mipLevelToRead", currentMipLevel);

                // Do vertical blur
                cb.SetRenderTarget(screenColorFlip, currentMipLevel);
                cb.SetGlobalTexture("colorBuffer", screenColorFlop);
                cb.DrawMesh(quadMesh, Matrix4x4.identity, blurMaterial, 0, 1);
            }
        }

        private void GenerateHiZ(int hizMipCount, CommandBuffer cb)
        {
            if (useComputeForHiZ)
            {
                GenerateHiZWithCompute(cb, hizMipCount);
            }
            else
            {
                GenerateHiZWithShader(cb, hizMipCount);
            }
        }

        private void GenerateHiZWithShader(CommandBuffer cb, int hizMipCount)
        {
            bool useFlip = true;

            Vector2 currentMipLevelDimensions = new Vector2(cameraWidth, cameraHeight);
            Vector2 previousMipLevelDimensions = currentMipLevelDimensions;

            for (int currentMipLevel = 0; currentMipLevel < hizMipCount; currentMipLevel++)
            {
                RenderTexture currentHiZTarget = useFlip ? hiZRTflip : hiZRTflop;
                RenderTexture previousHiZTarget = useFlip ? hiZRTflop : hiZRTflip;

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
                    cb.CopyTexture(hiZRTflop, 0, currentMipLevel, hiZRTflip, 0, currentMipLevel);
                }

                useFlip = !useFlip;
            }
        }

        private void GenerateHiZWithCompute(CommandBuffer cb, int hizMipCount)
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

                cb.SetComputeTextureParam(generateHiZComputeShader, 0, "WriteRT", hiZRTflip, currentMipLevel);
                cb.SetComputeTextureParam(generateHiZComputeShader, 0, "ReadRT", hiZRTflip, Mathf.Max(currentMipLevel - 1, 0));

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

        void Update()
        {
            // TODO: move to on pre-render for VR and to avoid lag
            // Also shader properties
            // Also remove the inverse matrix not sure we need it
            // Consider even not doing this matrix and doing it all in shader manually
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

                var projectionMatrix = GL.GetGPUProjectionMatrix(targetCamera.projectionMatrix, false);
                textureSpaceProjectionMatrix *= projectionMatrix;

                ssrMaterial.SetMatrix("textureSpaceProjectionMatrix", textureSpaceProjectionMatrix); // maybe just do these in shader?
            }
        }

        void OnDestory()
        {
            ReleaseRenderTextures();

            if (ssrCommandBuffer != null && targetCamera != null)
                targetCamera.RemoveCommandBuffer(CameraEvent.AfterSkybox, ssrCommandBuffer);
        }

        private void ReleaseRenderTextures()
        {
            if (hiZRTflip != null)
                hiZRTflip.Release();

            if (hiZRTflop != null)
                hiZRTflop.Release();
        }


        public static RenderTexture CreateRenderTexture(int width, int height, RenderTextureFormat format, bool useMips, FilterMode filterMode, int anisoLevel = 0, int mipCount = -1, TextureDimension dimension = TextureDimension.Tex2D, int depth = 0, bool randomReadWrite = false, TextureWrapMode wrapMode = TextureWrapMode.Repeat, bool autoGenerateMips = false)
        {
            RenderTexture rt;

            if (mipCount == -1)
                rt = new RenderTexture(width, height, 0, format);
            else
                rt = new RenderTexture(width, height, 0, format, mipCount);

            rt.anisoLevel = 1;
            rt.antiAliasing = 1;
            rt.dimension = dimension;
            rt.volumeDepth = depth;
            rt.useMipMap = useMips;
            rt.autoGenerateMips = autoGenerateMips;
            rt.filterMode = filterMode;
            rt.enableRandomWrite = randomReadWrite;
            rt.wrapMode = wrapMode;
            rt.anisoLevel = anisoLevel;
            rt.Create();

            return rt;
        }

        public static RenderTexture CreateRenderTexture(string name, int width, int height, RenderTextureFormat format, bool useMips, FilterMode filterMode, int anisoLevel = 0, int mipCount = -1, TextureDimension dimension = TextureDimension.Tex2D, int depth = 0, bool randomReadWrite = false, TextureWrapMode wrapMode = TextureWrapMode.Repeat, bool autoGenerateMips = false)
        {
            RenderTexture rt = CreateRenderTexture(width, height, format, useMips, filterMode, anisoLevel, mipCount, dimension, depth, randomReadWrite, wrapMode, autoGenerateMips);
            rt.name = name;
            return rt;
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