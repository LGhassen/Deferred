// This is slightly different from other shaders so far in that it blends between multiple textures and that the grass texture
// is tiled based on position and not UV
// It also blends between multiple grass textures but I just use the first one and it looks the same so idk
// I also didn't bother using any of the provided grass tiling and blendDistance params and just used my own
// repeating/zoomable texture logic
Shader "KSP/Scenery/Diffuse Ground KSC"
{
    Properties
    {
        _NearGrassTexture("Near Grass Color Texture", 2D) = "gray" {}
        _TarmacTexture("Ground Color Texture", 2D) = "gray" {}
        _BlendMaskTexture("Blend Mask", 2D) = "gray" {}

        _GrassColor("Grass Color", Color) = (1.0, 1.0, 1.0, 1.0)
        _TarmacColor("Ground Color", Color) = (1.0, 1.0, 1.0, 1.0)

        [PerRendererData]_RimFalloff("Rim Falloff", Range(0.0, 10.0)) = 0.1
        [PerRendererData]_RimColor("Rim Color", Color) = (0.0, 0.0, 0.0, 0.0)
    }

    SubShader
    {
        Tags{ "RenderType" = "Opaque" }

        Stencil
        {
            Ref 3
            Comp Always
            Pass Replace
        }

        CGPROGRAM
        #include "../Emission.cginc"
        #include "../LegacyToStandard.cginc"
        #pragma surface surf Standard vertex:vertexShader
        #pragma target 3.0

        sampler2D _NearGrassTexture;
        sampler2D _BlendMaskTexture;
        sampler2D _TarmacTexture;

        float4 _GrassColor;
        float4 _TarmacColor;

        struct Input
        {
            float2 uv_TarmacTexture;
            float2 uv2_BlendMaskTexture;
            float3 vertexPos;
            float3 worldPos;
            float3 viewDir;
        };

        void vertexShader (inout appdata_full v, out Input o) 
        {
            UNITY_INITIALIZE_OUTPUT(Input, o);
            o.vertexPos = v.vertex;
        }

        void surf(Input i, inout SurfaceOutputStandard o)
        {
            float4 groundColor = tex2D(_TarmacTexture,(i.uv_TarmacTexture));
            float blendMask = tex2D(_BlendMaskTexture,(i.uv2_BlendMaskTexture));

            float cameraDistance = length(_WorldSpaceCameraPos - i.worldPos);

            // Blend between different scales of the grass texture depending on distance
            // This is different from how the stock shader works (there are parameters for preset scales and blend distances) but this looks fine
            float textureScale = 10.0;

            // Based on the distance figure out the two scales to blend between, log10 looked good
            float currentPower = max(log10(cameraDistance/textureScale), 0.0);
            float fractionalPart = frac(currentPower);
            currentPower -= fractionalPart;
            float nextPower = currentPower + 1;

            float currentScale = pow(10.0, currentPower) * textureScale;
            float nextScale = pow(10.0, nextPower) * textureScale;

            // Sample grass textures
            float4 grassColor0 = tex2D(_NearGrassTexture, i.vertexPos.xz / currentScale * 3.0);
            float4 grassColor1 = tex2D(_NearGrassTexture, i.vertexPos.xz / nextScale * 3.0);

            float4 grass = _GrassColor * lerp(grassColor0, grassColor1, fractionalPart);
            
            // Blend between groundColor and grass based on the blend mask, this appears to be working correctly
            float4 color;
            color.rgb = lerp(grass.rgb, _TarmacColor.rgb * groundColor, blendMask);
            
            // I didn't follow my usual blinn-phong conversion logic here and went with something that looks better
            // Also froze the max smoothness since some mods have custom textures with 1.0 specular
            float tarmacSmoothness = 0.25 * sqrt(max(groundColor.a * _TarmacColor.a, 0.0000001));
            float grassSmoothness = 0.1 * grass.a;

            o.Smoothness = lerp(grassSmoothness, tarmacSmoothness, blendMask);

            o.Albedo = color.rgb;
            o.Normal = float3(0.0, 0.0, 1.0);
            o.Emission = GetEmission(i.viewDir, o.Normal);
        }
        ENDCG
    }
    Fallback "Diffuse"
}