using System;
using UnityEngine;
using UnityEngine.XR;
using System.Linq;
using UnityEngine.Rendering;

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
                    UnityEngine.Object.Destroy(renderTexture);
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

            // Is this needed? won't cam.PixelWidth and height provide the right result?
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

        public static Camera FindCamera(string name)
        {
            return Camera.allCameras.FirstOrDefault(_cam => _cam.name == name);
        }

        public class HistoryManager<T>
        {
            private T[,,] array = null;

            private bool flipFlop = false;
            private bool vr = false;
            private bool cubemap = false;

            public bool FlipFlop { get => flipFlop; }
            public bool VR { get => vr; }
            public bool Cubemap { get => cubemap; }

            public HistoryManager(bool flipFlop, bool VR, bool cubemap)
            {
                this.flipFlop = flipFlop;
                this.vr = VR;
                this.cubemap = cubemap;

                array = new T[flipFlop ? 2 : 1, VR ? 2 : 1, cubemap ? 6 : 1];
            }

            public void GetDimensions(out int x, out int y, out int z)
            {
                x = array.GetLength(0);
                y = array.GetLength(1);
                z = array.GetLength(2);
            }

            private void CalculateIndices(bool flip, bool VRRightEye, int cubemapFace, out int x, out int y, out int z)
            {
                x = flipFlop && !flip ? 1 : 0;
                y = vr && !VRRightEye ? 1 : 0;
                z = Cubemap ? cubemapFace : 0;
            }

            public T this[bool flip, bool VRRightEye, int cubemapFace]
            {
                get
                {
                    CalculateIndices(flip, VRRightEye, cubemapFace, out int x, out int y, out int z);
                    return array[x, y, z];
                }
                set
                {
                    CalculateIndices(flip, VRRightEye, cubemapFace, out int x, out int y, out int z);
                    array[x, y, z] = value;
                }
            }

            public T this[int x, int y, int z]
            {
                get
                {
                    x = Math.Min(x, array.GetLength(0)); y = Math.Min(y, array.GetLength(1)); z = Math.Min(z, array.GetLength(2));
                    return array[x, y, z];
                }
                set
                {
                    x = Math.Min(x, array.GetLength(0)); y = Math.Min(y, array.GetLength(1)); z = Math.Min(z, array.GetLength(2));
                    array[x, y, z] = value;
                }
            }
        }

        public static HistoryManager<RenderTexture> CreateRTHistoryManager(bool flipFlop, bool VR, bool cubemap, int width, int height, RenderTextureFormat format, bool useMips,
                                                                          FilterMode filterMode, int anisoLevel = 0, int mipCount = -1,
                                                                          TextureDimension dimension = TextureDimension.Tex2D, int depth = 0, bool randomReadWrite = false,
                                                                          TextureWrapMode wrapMode = TextureWrapMode.Repeat, bool autoGenerateMips = false)
        {
            var historyManager = new HistoryManager<RenderTexture>(flipFlop, VR, cubemap);

            historyManager.GetDimensions(out int x, out int y, out int z);

            for (int i = 0; i < x; i++)
            {
                for (int j = 0; j < y; j++)
                {
                    for (int k = 0; k < z; k++)
                    {
                        historyManager[i, j, k] = CreateRenderTexture(width, height, format, useMips, filterMode, anisoLevel, mipCount,
                                                                      dimension, depth, randomReadWrite, wrapMode, autoGenerateMips);
                    }
                }
            }

            return historyManager;
        }

        public static void ReleaseRTHistoryManager(HistoryManager<RenderTexture> historyManager)
        {
            if (historyManager != null)
            {
                historyManager.GetDimensions(out int x, out int y, out int z);

                for (int i = 0; i < x; i++)
                {
                    for (int j = 0; j < y; j++)
                    {
                        for (int k = 0; k < z; k++)
                        {
                            var rt = historyManager[i, j, k];
                            if (rt != null)
                            {
                                rt.Release();
                            }

                            historyManager[i, j, k] = null;
                        }
                    }
                }
            }
        }

        public static RenderTexture CreateRenderTexture(int width, int height, RenderTextureFormat format, bool useMips, FilterMode filterMode, int anisoLevel = 0, int mipCount = -1,
                                                        TextureDimension dimension = TextureDimension.Tex2D, int depth = 0, bool randomReadWrite = false,
                                                        TextureWrapMode wrapMode = TextureWrapMode.Repeat, bool autoGenerateMips = false)
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
    }
}