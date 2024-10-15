using UnityEngine;
using UnityEngine.Rendering;

namespace Deferred
{ 
    // PQS uses alpha transparency to fade to the scaled space
    // Traditional alpha fade is impossible in deferred rendering, and dithered fade looked distracting on the PQS terrain
    // and caused a few more issues with visual mods like clouds visible through dithered mountains
    // This script implements a custom replacement which can only fade to what the previous camera rendered (which is perfect here)
    // It works by copying the previous camera output, then compositing it with the output of the g-buffer lighting pass
    // The fade is only applied to the terrain fragments by checking the stencil buffer
    public class DeferredPQSFade : MonoBehaviour
    {
        CommandBuffer backgroundCopyCommandBuffer = null;
        CommandBuffer applyFadeCommandBuffer = null;

        Camera targetCamera;
        RenderTexture backgroundCopyRT = null;

        Material applyFadeMaterial;

        private static int planetOpacityProperty = Shader.PropertyToID("_PlanetOpacity");
        private static int backgroundCopyRTProperty = Shader.PropertyToID("backgroundCopyRT");

        private void Awake()
        {
            targetCamera = GetComponent<Camera>();

            backgroundCopyCommandBuffer = new CommandBuffer();
            backgroundCopyCommandBuffer.name = "Deferred PQS fade background copy CommandBuffer";

            applyFadeCommandBuffer = new CommandBuffer();
            applyFadeCommandBuffer.name = "Deferred PQS fade apply CommandBuffer";

            applyFadeMaterial = new Material(ShaderLoader.DeferredShaders["Deferred/ApplyPQSFade"]);
        }

        void OnPreRender()
        {
            if (targetCamera.stereoActiveEye != Camera.MonoOrStereoscopicEye.Right)
            { 
                float fade = -1f;

                if (FlightGlobals.currentMainBody != null)
                {
                    if (FlightGlobals.currentMainBody.pqsController != null)
                    {
                        var pqscontroller = FlightGlobals.currentMainBody.pqsController;

                        if (pqscontroller.surfaceMaterial != null)
                        {
                            fade = pqscontroller.surfaceMaterial.GetFloat(planetOpacityProperty);
                        }
                    }
                }

                if (fade > 0f && fade <= 1f)
                {
                    if (enabled && targetCamera != null)
                    {
                        int width, height;
                        RenderingUtils.GetCameraRenderDimensions(targetCamera, out width, out height);

                        RenderingUtils.EnsureRenderTexture(ref backgroundCopyRT, width, height, targetCamera.allowHDR ? RenderTextureFormat.ARGBHalf : RenderTextureFormat.ARGB32);

                        backgroundCopyCommandBuffer.Clear();

                        backgroundCopyCommandBuffer.Blit(new RenderTargetIdentifier(BuiltinRenderTextureType.CameraTarget), backgroundCopyRT);
                        targetCamera.AddCommandBuffer(CameraEvent.BeforeGBuffer, backgroundCopyCommandBuffer);

                        applyFadeMaterial.SetTexture(backgroundCopyRTProperty, backgroundCopyRT);
                        applyFadeMaterial.SetFloat(planetOpacityProperty, fade);

                        applyFadeCommandBuffer.Clear();
                        applyFadeCommandBuffer.Blit(null, new RenderTargetIdentifier(BuiltinRenderTextureType.CameraTarget), applyFadeMaterial);
                        targetCamera.AddCommandBuffer(CameraEvent.AfterFinalPass, applyFadeCommandBuffer);
                    }
                }
                else if (backgroundCopyRT != null)
                {
                    backgroundCopyRT.Release();
                    Object.Destroy(backgroundCopyRT);
                }
            }
        }

        void OnPostRender()
        {
            if (targetCamera.stereoActiveEye != Camera.MonoOrStereoscopicEye.Left)
            { 
                if (backgroundCopyCommandBuffer != null)
                {
                    targetCamera.RemoveCommandBuffer(CameraEvent.BeforeGBuffer, backgroundCopyCommandBuffer);
                }

                if (applyFadeCommandBuffer != null)
                {
                    targetCamera.RemoveCommandBuffer(CameraEvent.AfterFinalPass, applyFadeCommandBuffer);
                }
            }
        }

        private void OnDestroy()
        {
            if (backgroundCopyRT != null)
            {
                backgroundCopyRT.Release();
                Object.Destroy(backgroundCopyRT);
            }

            if (backgroundCopyCommandBuffer != null)
            {
                targetCamera.RemoveCommandBuffer(CameraEvent.BeforeGBuffer, backgroundCopyCommandBuffer);
                backgroundCopyCommandBuffer.Clear();
            }

            if (applyFadeCommandBuffer != null)
            {
                targetCamera.RemoveCommandBuffer(CameraEvent.AfterFinalPass, applyFadeCommandBuffer);
                applyFadeCommandBuffer.Clear();
            }
        }
    }
}