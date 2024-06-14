// Modified version of Unity built-in shader source.
// This adds the diffuse ambient evaluation here

Shader "Deferred/Internal-DeferredReflections" {
Properties {
    _SrcBlend ("", Float) = 1
    _DstBlend ("", Float) = 1
}
SubShader {

// Calculates reflection contribution from a single probe (rendered as cubes) or default reflection (rendered as full screen quad)
Pass {
    ZWrite Off
    ZTest LEqual
    Blend [_SrcBlend] [_DstBlend]
CGPROGRAM
#pragma target 3.0
#pragma vertex vert_deferred
#pragma fragment frag

#include "UnityCG.cginc"
#include "UnityDeferredLibrary.cginc"
#include "UnityStandardUtils.cginc"
#include "UnityGBuffer.cginc"
#include "UnityStandardBRDF.cginc"
#include "UnityPBSLighting.cginc"

sampler2D _CameraGBufferTexture0;
sampler2D _CameraGBufferTexture1;
sampler2D _CameraGBufferTexture2;

int useReflectionProbeOnCurrentCamera;
float deferredAmbientBrightness, deferredAmbientTint;

half3 distanceFromAABB(half3 p, half3 aabbMin, half3 aabbMax)
{
    return max(max(p - aabbMax, aabbMin - p), half3(0.0, 0.0, 0.0));
}

float3 legacyAmbientColor;

half4 frag (unity_v2f_deferred i) : SV_Target
{
    // Stripped from UnityDeferredCalculateLightParams, refactor into function ?
    i.ray = i.ray * (_ProjectionParams.z / i.ray.z);
    float2 uv = i.uv.xy / i.uv.w;

    // read depth and reconstruct world position
    float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv);
    depth = Linear01Depth (depth);
    float4 viewPos = float4(i.ray * depth,1);
    float3 worldPos = mul (unity_CameraToWorld, viewPos).xyz;

    half4 gbuffer0 = tex2D (_CameraGBufferTexture0, uv);
    half4 gbuffer1 = tex2D (_CameraGBufferTexture1, uv);
    half4 gbuffer2 = tex2D (_CameraGBufferTexture2, uv);
    UnityStandardData data = UnityStandardDataFromGbuffer(gbuffer0, gbuffer1, gbuffer2);

    float3 eyeVec = normalize(worldPos - _WorldSpaceCameraPos);
    half oneMinusReflectivity = 1 - SpecularStrength(data.specularColor);

    half3 worldNormalRefl = reflect(eyeVec, data.normalWorld);

    // Unused member don't need to be initialized
    UnityGIInput d;
    d.worldPos = worldPos;
    d.worldViewDir = -eyeVec;
    d.probeHDR[0] = unity_SpecCube0_HDR;
    d.boxMin[0].w = 1; // 1 in .w allow to disable blending in UnityGI_IndirectSpecular call since it doesn't work in Deferred

    float blendDistance = unity_SpecCube1_ProbePosition.w; // will be set to blend distance for this probe
    #ifdef UNITY_SPECCUBE_BOX_PROJECTION
    d.probePosition[0]  = unity_SpecCube0_ProbePosition;
    d.boxMin[0].xyz     = unity_SpecCube0_BoxMin - float4(blendDistance,blendDistance,blendDistance,0);
    d.boxMax[0].xyz     = unity_SpecCube0_BoxMax + float4(blendDistance,blendDistance,blendDistance,0);
    #endif

    Unity_GlossyEnvironmentData g = UnityGlossyEnvironmentSetup(data.smoothness, d.worldViewDir, data.normalWorld, data.specularColor);

    UnityLight light;
    light.color = half3(0, 0, 0);
    light.dir = half3(0, 1, 0);

    UnityIndirect ind;
    ind.diffuse = 0;
    ind.specular = 0;

    [branch]
    if (useReflectionProbeOnCurrentCamera > 0)
    {
        ind.specular = UnityGI_IndirectSpecular(d, data.occlusion, g);

        ind.diffuse = deferredAmbientBrightness * Unity_GlossyEnvironment (UNITY_PASS_TEXCUBE(unity_SpecCube0), d.probeHDR[0], data.normalWorld, 0.55);
        ind.diffuse = lerp(length(ind.diffuse).xxx, ind.diffuse, deferredAmbientTint); // Limit the tint because it overpowers other colors without white balance
    }

    float diffuseMagnitude = length(ind.diffuse);

    float legacyAmbientMagnitude = length(legacyAmbientColor);

    ind.diffuse = lerp(legacyAmbientColor, ind.diffuse, saturate((diffuseMagnitude - legacyAmbientMagnitude) * 100.0));

    ind.diffuse *= data.occlusion; // Take the occlusion into account for the one IVA where it's used and maybe future AO implementations

    half3 rgb = UNITY_BRDF_PBS (data.diffuseColor, data.specularColor, oneMinusReflectivity, data.smoothness, data.normalWorld, -eyeVec, light, ind).rgb;

    // Calculate falloff value, so reflections on the edges of the probe would gradually blend to previous reflection.
    // Also this ensures that pixels not located in the reflection probe AABB won't
    // accidentally pick up reflections from this probe.
    half3 distance = distanceFromAABB(worldPos, unity_SpecCube0_BoxMin.xyz, unity_SpecCube0_BoxMax.xyz);
    half falloff = saturate(1.0 - length(distance)/blendDistance);

    return half4(rgb, falloff);
}

ENDCG
}

// Adds reflection buffer to the lighting buffer
Pass
{
    ZWrite Off
    ZTest Always
    Blend [_SrcBlend] [_DstBlend]

    CGPROGRAM
        #pragma target 3.0
        #pragma vertex vert
        #pragma fragment frag
        #pragma multi_compile ___ UNITY_HDR_ON

        #include "UnityCG.cginc"

        sampler2D _CameraReflectionsTexture;

        struct v2f {
            float2 uv : TEXCOORD0;
            float4 pos : SV_POSITION;
        };

        v2f vert (float4 vertex : POSITION)
        {
            v2f o;
            o.pos = UnityObjectToClipPos(vertex);
            o.uv = ComputeScreenPos (o.pos).xy;
            return o;
        }

        half4 frag (v2f i) : SV_Target
        {
            half4 c = tex2D (_CameraReflectionsTexture, i.uv);
            #ifdef UNITY_HDR_ON
            return float4(c.rgb, 0.0f);
            #else
            return float4(exp2(-c.rgb), 0.0f);
            #endif

        }
    ENDCG
}

}
Fallback Off
}
