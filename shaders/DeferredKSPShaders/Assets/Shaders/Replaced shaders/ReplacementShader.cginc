#include "Emission.cginc"
#include "../LegacyToStandard.cginc"
#include "../Dissolve.cginc"
#include "../DitherFunctions.cginc"

sampler2D _MainTex;
sampler2D _BumpMap;
sampler2D _Emissive;
sampler2D _LightMap;

float _Shininess;

float4 _Color;
float4 _BurnColor;
float4 _EmissiveColor;
float4 _LightColor1;
float4 _LightColor2;
float _Occlusion;

float _Opacity;
float _Cutoff;

struct Input
{
    float4 color : COLOR;
    float2 uv_MainTex;
    
#if defined (NORMALMAP_ON)
    float2 uv_BumpMap;
#endif
    
#if defined (EMISSIVEMAP_ON)
    float2 uv_Emissive;
#endif
    
#if defined(EMISSIVE_LIGHTMAP_ON)
    float2 uv2_LightMap;
#endif
    
    float2 uv_SpecMap;
    
    float3 worldPos;
    float3 viewDir;
    float4 screenPos;
};



void DeferredSpecularReplacementShader(Input i, inout SurfaceOutputStandardSpecular o)
{
    o.Occlusion = 1.0;
    
#if defined (DITHER_FADE_ON)
    float2 screenUV = i.screenPos.xy / i.screenPos.w;
    ditherClipTexture(screenUV, _Opacity);
#elif defined (DISSOLVE_FADE_ON)
    DissolveClip(i.worldPos, _Opacity);
#endif
    
#if defined (IGNORE_VERTEX_COLOR_ON)
    float4 vertexColor = 1.0.xxxx;
#else
    float4 vertexColor = i.color;
#endif
    
    float4 color = _Color * vertexColor * _BurnColor * tex2D(_MainTex, (i.uv_MainTex));
    
#if defined (NORMALMAP_ON)
    float3 normal = UnpackNormalDXT5nm(tex2D(_BumpMap, i.uv_BumpMap));
#else
    float3 normal = float3(0.0, 0.0, 1.0);
#endif

#if defined (EMISSIVEMAP_ON)
    float3 emissionMap = _EmissiveColor.a * _EmissiveColor.rgb * tex2D(_Emissive, i.uv_Emissive).rgb;
#elif defined(EMISSIVE_LIGHTMAP_ON)
    float4 lightmap = tex2D(_LightMap, i.uv2_LightMap);
    float occlusionPower = pow(lightmap.a, _Occlusion);
    float3 emissionMap = (lightmap.r * _LightColor1 + lightmap.g * _LightColor2) * color.rgb * occlusionPower;
    //o.Occlusion = lightmap.b * occlusionPower;  // the ambient lightMap is broken on several cockpits and doesn't match the props so ignore it
    o.Occlusion = occlusionPower;
#else    
    float3 emissionMap = 0.0.xxx;
#endif

#if defined (SPECULAR_ON)
    GetStandardSpecularPropertiesFromLegacy(_Shininess, color.a, _SpecColor, o.Smoothness, o.Specular);
#else
    GetStandardSpecularPropertiesFromLegacy(0.5, color.a, 0.5.xxx, o.Smoothness, o.Specular); // Just some settigs that work ok for diffuse parts
    
    if (color.a >= 0.99)
    {
        o.Smoothness = 0.45; // Some IVAs have color.a always set to 1.0 so we can't rely on that or the IVAs are ultra shiny
                             // Especially since diffuse parts weren't supposed to have specular maps but some parts have them anyway
    }
    
#endif
    
    o.Albedo = color.rgb;
    o.Normal = normal;
    o.Emission = emissionMap + GetEmission(i.viewDir, o.Normal);
    
#if defined (FORWARD_FADE_ON)
    o.Alpha = _Opacity * color.a;
#endif
    
#if UNITY_PASS_DEFERRED
			// In deferred rendering do not use the flat ambient because Deferred adds its own ambient as a composite of flat ambient and probe
            // Also do not use #pragma skip_variants LIGHTPROBE_SH because it impacts lighting in forward and some elements can still render in
			// forward e.g through the VAB scene doors
			unity_SHAr = 0.0.xxxx;
			unity_SHAg = 0.0.xxxx;
			unity_SHAb = 0.0.xxxx;
#endif
}

sampler2D _SpecMap;

void DeferredSpecularMappedReplacementShader(Input i, inout SurfaceOutputStandardSpecular o)
{
#if defined (DITHER_FADE_ON)
    float2 screenUV = i.screenPos.xy / i.screenPos.w;
    ditherClipTexture(screenUV, _Opacity);
#elif defined (DISSOLVE_FADE_ON)
    DissolveClip(i.worldPos, _Opacity);
#endif
    
    float4 vertexColor = i.color;
    float4 color = _Color * vertexColor * _BurnColor * tex2D(_MainTex, (i.uv_MainTex));
    float3 specularColor = tex2D(_SpecMap, (i.uv_SpecMap)).rgb;
    
#if defined (NORMALMAP_ON)
    float3 normal = UnpackNormalDXT5nm(tex2D(_BumpMap, i.uv_BumpMap));
#else
    float3 normal = float3(0.0, 0.0, 1.0);
#endif
    
#if defined (EMISSIVEMAP_ON)
    float3 emissionMap = _EmissiveColor.a * _EmissiveColor.rgb * tex2D(_Emissive, i.uv_Emissive).rgb;
#else 
    float3 emissionMap = 0.0.xxx;
#endif
    
    o.Albedo = color.rgb;
    o.Normal = normal;
    o.Emission = emissionMap + GetEmission(i.viewDir, o.Normal);
    o.Smoothness = _Shininess; // This is how the stock Mapped shaders work unfortunately, ignoring
                               // the alpha channel of the color texture. Going to keep the same
                               // behaviour for compatibility with all the existing part mods
    o.Specular = specularColor;
    
#if UNITY_PASS_DEFERRED
			// In deferred rendering do not use the flat ambient because Deferred adds its own ambient as a composite of flat ambient and probe
            // Also do not use #pragma skip_variants LIGHTPROBE_SH because it impacts lighting in forward and some elements can still render in
			// forward e.g through the VAB scene doors
			unity_SHAr = 0.0.xxxx;
			unity_SHAg = 0.0.xxxx;
			unity_SHAb = 0.0.xxxx;
#endif
}