// SMAA from Scatterer to use in editors since deferred rendering breaks traditional MSAA in those
using UnityEngine;
using UnityEngine.Rendering;

namespace Deferred
{
    public class SubpixelMorphologicalAntialiasing : MonoBehaviour
    {
        Camera targetCamera;
        CommandBuffer SMAACommandBuffer;
        Material SMAAMaterial;

        enum Pass { EdgeDetection = 0, BlendWeights = 3, NeighborhoodBlending = 6 }
        public enum Quality { DepthMode = 0, Medium = 1, High = 2 }

        private static CameraEvent SMAACameraEvent = CameraEvent.AfterForwardAlpha; // BeforeImageEffects doesn't work well

        Quality quality;

        RenderTexture flip, flop;
        static Texture2D areaTex, searchTex;
        bool initialized = false;

        public Quality QualityUsed { get => quality; }

        public SubpixelMorphologicalAntialiasing()
        {
            targetCamera = GetComponent<Camera>();

            targetCamera.forceIntoRenderTexture = true;

            int width, height;

            if (targetCamera.activeTexture)
            {
                width = targetCamera.activeTexture.width;
                height = targetCamera.activeTexture.height;
            }
            else
            {
                width = Screen.width;
                height = Screen.height;
            }

            bool hdrEnabled = targetCamera.allowHDR;
            var colorFormat = hdrEnabled ? RenderTextureFormat.DefaultHDR : RenderTextureFormat.ARGB32;

            flip = new RenderTexture(width, height, 0, colorFormat);
            flip.anisoLevel = 1;
            flip.antiAliasing = 1;
            flip.volumeDepth = 0;
            flip.useMipMap = false;
            flip.autoGenerateMips = false;
            flip.wrapMode = TextureWrapMode.Clamp;
            flip.filterMode = FilterMode.Bilinear;
            flip.Create();

            flop = new RenderTexture(width, height, 0, colorFormat);
            flop.anisoLevel = 1;
            flop.antiAliasing = 1;
            flop.volumeDepth = 0;
            flop.useMipMap = false;
            flop.autoGenerateMips = false;
            flip.wrapMode = TextureWrapMode.Clamp;
            flip.filterMode = FilterMode.Bilinear;
            flop.Create();

            SMAAMaterial = new Material(ShaderLoader.Instance.DeferredShaders[("Deferred/SubpixelMorphologicalAntialiasing")]);

            if (areaTex == null)
                areaTex = (Texture2D)ShaderLoader.Instance.LoadedTextures["AreaTex"];
            if (searchTex == null)
                searchTex = (Texture2D)ShaderLoader.Instance.LoadedTextures["SearchTex"];

            SMAAMaterial.SetTexture("_AreaTex", areaTex);
            SMAAMaterial.SetTexture("_SearchTex", searchTex);

            quality = Quality.High;

            SMAACommandBuffer = new CommandBuffer();
        }

        static readonly int MainTextureProperty = Shader.PropertyToID("_MainTexture");
        static readonly int BlendTexproperty = Shader.PropertyToID("_BlendTex");

        public void OnPreCull()
        {
            if (!initialized)
            {
                SMAACommandBuffer.Clear();

                SMAACommandBuffer.SetRenderTarget(flop);
                SMAACommandBuffer.ClearRenderTarget(false, true, Color.clear);

                SMAACommandBuffer.SetRenderTarget(flip);
                SMAACommandBuffer.ClearRenderTarget(false, true, Color.clear);

                SMAACommandBuffer.SetGlobalTexture(MainTextureProperty, BuiltinRenderTextureType.CameraTarget);

                SMAACommandBuffer.Blit(null, flip, SMAAMaterial, (int)Pass.EdgeDetection + (int)quality);       //screen to flip with edge detection

                SMAACommandBuffer.SetGlobalTexture(MainTextureProperty, flip);
                SMAACommandBuffer.Blit(null, flop, SMAAMaterial, (int)Pass.BlendWeights + (int)quality);        //flip to flop with blendweights
                SMAACommandBuffer.SetGlobalTexture(BlendTexproperty, flop);
                SMAACommandBuffer.SetGlobalTexture(MainTextureProperty, BuiltinRenderTextureType.CameraTarget);
                SMAACommandBuffer.Blit(null, flip, SMAAMaterial, (int)Pass.NeighborhoodBlending);               //neighborhood blending to flip
                SMAACommandBuffer.Blit(flip, BuiltinRenderTextureType.CameraTarget);                            //blit back to screen

                targetCamera.AddCommandBuffer(SMAACameraEvent, SMAACommandBuffer);
                initialized = true;
            }
        }

        public void OnDestroy()
        {
            SMAAMaterial = null;

            if (SMAACommandBuffer != null)
            {
                targetCamera.RemoveCommandBuffer(SMAACameraEvent, SMAACommandBuffer);
                SMAACommandBuffer.Clear();
            }

            if (flip)
                flip.Release();

            if (flop)
                flop.Release();
        }
    }
}
