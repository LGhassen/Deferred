using UnityEngine;
using UnityEngine.XR;

namespace Deferred
{
    public static class RenderingUtils
    {
        public static void EnsureRenderTexture(ref RenderTexture renderTexture, int width, int height, RenderTextureFormat format)
        {
            if (renderTexture == null || renderTexture.width != width || renderTexture.height != height || renderTexture.format != format)
            {
                if (renderTexture != null)
                {
                    renderTexture.Release();
                    Object.Destroy(renderTexture);
                }

                renderTexture = new RenderTexture(width, height, 0, format);
                renderTexture.Create();
            }
        }

        public static void GetCameraRenderDimensions(Camera targetCamera, out int width, out int height)
        {
            if (VREnabled())
            {
                GetEyeTextureResolution(out width, out height);
                return;
            }

            if (targetCamera.activeTexture != null)
            {
                width = targetCamera.activeTexture.width;
                height = targetCamera.activeTexture.height;
            }
            else
            {
                width = Screen.width;
                height = Screen.height;
            }
        }

        public static bool? unifiedCameraMode = null;

        public static bool IsUnifiedCameraMode()
        {
            if (unifiedCameraMode == null)
            {
                unifiedCameraMode = SystemInfo.graphicsDeviceVersion.Contains("Direct3D");
            }
            return unifiedCameraMode.Value;
        }

        public static void GetEyeTextureResolution(out int width, out int height)
        {
            width = XRSettings.eyeTextureWidth;
            height = XRSettings.eyeTextureHeight;
        }

        public static bool VREnabled()
        {
            return XRSettings.loadedDeviceName != string.Empty;
        }
    }
}