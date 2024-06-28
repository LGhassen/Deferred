// This is the same as Diffuse groundColor KSC but with normals and 3 grass textures for some reason
// I still ignore all the provided scales and only use the first grass Texture here and it looks the same or unnoticeable
Shader "KSP/Scenery/Diffuse Ground KSC Specular"
{
    Properties
    {
        _NearGrassTexture("Near Grass Color Texture", 2D) = "gray" {}
        _TarmacTexture("Ground Color Texture", 2D) = "gray" {}
        _NearGrassNormal("Near Grass Normal Texture", 2D) = "gray" {}
        _TarmacNormal("Ground Normal Texture", 2D) = "gray" {}
        _BlendMaskTexture("Blend Mask", 2D) = "gray" {}

        _GrassColor("Grass Color", Color) = (1.0, 1.0 ,1.0 ,1.0)
        _TarmacColor("Tarmac Color", Color) = (1.0, 1.0 ,1.0 ,1.0)

        _SpecularColor("Specular Color", Color) = (0.5, 0.5, 0.5, 1)

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
        #pragma surface surf Standard vertex:vertexShader
        #pragma target 3.0

        sampler2D _NearGrassTexture;
        sampler2D _TarmacTexture;
        sampler2D _NearGrassNormal;
        sampler2D _TarmacNormal;
        sampler2D _BlendMaskTexture;

        float4 _GrassColor;
        float4 _TarmacColor;
        float4 _SpecularColor;

        //float _NearGrassTiling, _MidGrassTiling, _FarGrassTiling; // 0.01, 0.05 and 1.0 in the stock game
        //float _MidGrassBlendDistance, _FarGrassBlendDistance;     // 15.0 and 80 in the stock game

        struct Input
        {
            float2 uv_TarmacTexture;
            float2 uv2_BlendMaskTexture;
            float3 viewDir;
            float3 vertexPos;
            float3 worldPos;
            float4 screenPos;
        };

        void vertexShader(inout appdata_full v, out Input o)
        {
            UNITY_INITIALIZE_OUTPUT(Input, o);
            o.vertexPos = v.vertex;
        }

        void surf(Input i, inout SurfaceOutputStandard o)
        {
            float4 groundColor = tex2D(_TarmacTexture, i.uv_TarmacTexture);
            float3 groundNormal = UnpackNormalDXT5nm(tex2D(_TarmacNormal, i.uv_TarmacTexture));
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
            float4 grassColor10 = tex2D(_NearGrassTexture, i.vertexPos.xz / currentScale * 3.0);
            float4 grassColor11 = tex2D(_NearGrassTexture, i.vertexPos.xz / nextScale * 3.0);

            float3 grassNormal10 = UnpackNormalDXT5nm(tex2D(_NearGrassNormal, i.vertexPos.xz / currentScale * 3.0));
            float3 grassNormal11 = UnpackNormalDXT5nm(tex2D(_NearGrassNormal, i.vertexPos.xz / nextScale * 3.0));

            float4 grass = _GrassColor * lerp(grassColor10, grassColor11, fractionalPart);
            float3 grassNormal = lerp(grassNormal10, grassNormal11, fractionalPart);

            // Blend between groundColor and grass based on the blend mask, this appears to be working correctly
            float4 color = lerp(grass, _TarmacColor * groundColor, blendMask);
            float3 normal = lerp(grassNormal, groundNormal, blendMask);

            // I didn't follow my usual blinn-phong conversion logic here and went with something that looks better
            // since this shader is only used in one place and with one set of textures
            o.Smoothness = 0.75 * sqrt(sqrt(max(color.a, 0.0000001)));

            o.Albedo = color;
            o.Normal = normal;
            o.Emission = GetEmission(i.viewDir, o.Normal);
        }
        ENDCG
    }
    Fallback "Diffuse"
}