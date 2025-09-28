using UnityEngine;
using UnityEngine.Rendering;

namespace Deferred
{ 
    public class GBufferDebug : MonoBehaviour
    {
        CommandBuffer emissionCopyCommandBuffer = null;
        CommandBuffer gbufferCopyCommandBuffer = null;
        CommandBuffer gbufferDisplayCommandBuffer = null;

        Camera targetCamera;
        RenderTexture gbufferCopyRT = null;
        RenderTexture emissionCopyRT = null;

        Material copyGBufferMaterial, displayGBufferMaterial;

        public static DebugMode debugMode = DebugMode.Normals;

        public enum DebugMode
        {
            Albedo,
            SpecularColor,
            Normals,
            Smoothness,
            Emission,
            Ambient,
            Occlusion,
            ReflectionProbe,
        }

        private void Awake()
        {
            targetCamera = GetComponent<Camera>();

            emissionCopyCommandBuffer = new CommandBuffer();
            emissionCopyCommandBuffer.name = "Deferred debug emission copy CommandBuffer";

            gbufferCopyCommandBuffer = new CommandBuffer();
            gbufferCopyCommandBuffer.name = "Deferred debug gbuffer copy CommandBuffer";

            gbufferDisplayCommandBuffer = new CommandBuffer();
            gbufferDisplayCommandBuffer.name = "Deferred debug display CommandBuffer";

            copyGBufferMaterial = new Material(ShaderLoader.DeferredShaders["Deferred/CopyGBuffer"]);
            displayGBufferMaterial = new Material(ShaderLoader.DeferredShaders["Deferred/DisplayGBuffer"]);
        }

        void OnPreRender()
        {
            if (enabled && targetCamera != null)
            {
                int width, height;
                RenderingUtils.GetCameraRenderDimensions(targetCamera, out width, out height);

                RenderingUtils.EnsureRenderTexture(ref emissionCopyRT, width, height, targetCamera.allowHDR ? RenderTextureFormat.ARGBHalf : RenderTextureFormat.ARGB32);
                RenderingUtils.EnsureRenderTexture(ref gbufferCopyRT, width, height, targetCamera.allowHDR ? RenderTextureFormat.ARGBHalf : RenderTextureFormat.ARGB32);

                emissionCopyCommandBuffer.Clear();
                emissionCopyCommandBuffer.Blit(targetCamera.allowHDR ? BuiltinRenderTextureType.CameraTarget : BuiltinRenderTextureType.GBuffer3, emissionCopyRT);
                emissionCopyCommandBuffer.SetGlobalTexture("emissionCopyRT", emissionCopyRT);

                targetCamera.AddCommandBuffer(CameraEvent.BeforeReflections, emissionCopyCommandBuffer);

                gbufferCopyCommandBuffer.Clear();
                copyGBufferMaterial.SetInt("GbufferDebugMode", (int)debugMode);
                copyGBufferMaterial.SetInt("logarithmicLightBuffer", targetCamera.allowHDR ? 0 : 1);
                copyGBufferMaterial.SetMatrix("CameraToWorld", targetCamera.cameraToWorldMatrix);

                gbufferCopyCommandBuffer.Blit(null, gbufferCopyRT, copyGBufferMaterial);

                targetCamera.AddCommandBuffer(CameraEvent.BeforeLighting, gbufferCopyCommandBuffer);

                gbufferDisplayCommandBuffer.Clear();
                gbufferDisplayCommandBuffer.Blit(gbufferCopyRT, new RenderTargetIdentifier(BuiltinRenderTextureType.CameraTarget), displayGBufferMaterial);

                if (debugMode == DebugMode.ReflectionProbe)
                    targetCamera.AddCommandBuffer(CameraEvent.AfterForwardAlpha, gbufferDisplayCommandBuffer);
                else
                    targetCamera.AddCommandBuffer(CameraEvent.BeforeForwardAlpha, gbufferDisplayCommandBuffer);
            }
        }

        void OnPostRender()
        {
            if (emissionCopyCommandBuffer != null)
            {
                targetCamera.RemoveCommandBuffer(CameraEvent.BeforeReflections, emissionCopyCommandBuffer);
            }

            if (gbufferCopyCommandBuffer != null)
            {
                targetCamera.RemoveCommandBuffer(CameraEvent.BeforeLighting, gbufferCopyCommandBuffer);
            }

            if (gbufferDisplayCommandBuffer != null)
            {
                targetCamera.RemoveCommandBuffer(CameraEvent.BeforeForwardAlpha, gbufferDisplayCommandBuffer);
                targetCamera.RemoveCommandBuffer(CameraEvent.AfterForwardAlpha, gbufferDisplayCommandBuffer);
            }
        }

        private void OnDestroy()
        {
            if (gbufferCopyRT != null)
            {
                gbufferCopyRT.Release();
                Object.Destroy(gbufferCopyRT);
            }

            if (gbufferCopyCommandBuffer != null)
            {
                targetCamera.RemoveCommandBuffer(CameraEvent.BeforeLighting, gbufferCopyCommandBuffer);
                gbufferCopyCommandBuffer.Clear();
            }

            if (gbufferDisplayCommandBuffer != null)
            {
                targetCamera.RemoveCommandBuffer(CameraEvent.BeforeForwardAlpha, gbufferDisplayCommandBuffer);
                targetCamera.RemoveCommandBuffer(CameraEvent.AfterForwardAlpha, gbufferDisplayCommandBuffer);
                gbufferDisplayCommandBuffer.Clear();
            }
        }
    }
}