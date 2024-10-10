sampler2D _CameraDepthTexture;
sampler2D deferredSSRColorBuffer;
float2 currentMipLevelDimensions;
int mipLevelToRead;
int currentMipLevel;

struct v2f
{
    float4 pos : SV_POSITION;
    float2 uv : TEXCOORD0;
};

v2f vert(appdata_img v)
{
    v2f o = (v2f) 0;
    o.pos = float4(v.vertex.xy * 2.0, 0.0, 1.0);
    o.uv = ComputeScreenPos(o.pos);

    return o;
}

float4 gaussianBlurFrag(v2f i) : SV_Target
{
    float2 texelSize = 1.0.xx / currentMipLevelDimensions;

#if defined (HORIZONTAL_BLUR)
    texelSize.y = 0.0;
#else
    texelSize.x = 0.0;
#endif
    
#if defined (COMBINED_TAPS)
    // Combined weights and offsets using 3 taps of bilinear filtering to get 5 taps
    float3 color = tex2Dlod(deferredSSRColorBuffer, float4(i.uv + float2(-1.213, -1.213) * texelSize, 0.0, mipLevelToRead)) * 0.305f;
    color += tex2Dlod(deferredSSRColorBuffer, float4(i.uv + float2(0.0, 0.0) * texelSize, 0.0, mipLevelToRead)) * 0.390f;
    color += tex2Dlod(deferredSSRColorBuffer, float4(i.uv + float2(1.213, 1.213) * texelSize, 0.0, mipLevelToRead)) * 0.305f;
#else
    // Separate weights, to be used when reading multiple averaged texels from a previous mipLevel
    float3 color = tex2Dlod(deferredSSRColorBuffer, float4(i.uv + int2(-2, -2) * texelSize, 0.0, mipLevelToRead)) * 0.061f;
    color += tex2Dlod(deferredSSRColorBuffer, float4(i.uv + int2(-1, -1) * texelSize, 0.0, mipLevelToRead)) * 0.244f;
    color += tex2Dlod(deferredSSRColorBuffer, float4(i.uv + int2(0, 0) * texelSize, 0.0, mipLevelToRead)) * 0.390f;
    color += tex2Dlod(deferredSSRColorBuffer, float4(i.uv + int2(1, 1) * texelSize, 0.0, mipLevelToRead)) * 0.244f;
    color += tex2Dlod(deferredSSRColorBuffer, float4(i.uv + int2(2, 2) * texelSize, 0.0, mipLevelToRead)) * 0.061f;
#endif

    return float4(color, 1.0);
}

sampler2D _CameraGBufferTexture1; // alpha = smoothness
sampler2D _CameraGBufferTexture2; // normal = rgb

float blurOffset;
float prevBlurOffset;
sampler2D ssrHitDistance;

#include "HiZtracing.cginc"
#include "ConeUtils.cginc"

float4 normalsAwareBlurFrag(v2f i) : SV_Target
{
    float2 halfResUV = i.uv.xy;
    float2 fullResTexelSize = 1.0 / ScreenResolution;

#if defined(HALF_RESOLUTION_TRACING)
    float2 fullResUV = GetFullResUVFromHalfResUV(i.uv.xy);
    float2 halfResTexelSize = 1.0 / uint2(ScreenResolution.x/2u, ScreenResolution.y); // TODO: maybe pass these in?
#else
    float2 fullResUV = i.uv.xy;
    float2 halfResTexelSize = fullResTexelSize;
#endif

    float zdepth = tex2Dlod(_CameraDepthTexture, float4(fullResUV, 0.0, 0.0));
    float4 centerColor = tex2Dlod(deferredSSRColorBuffer, float4(halfResUV, 0.0, 0));

#if defined(UNITY_REVERSED_Z)
    if (zdepth == 0.0)
#else
    if (zdepth == 1.0)
#endif
        return centerColor;

    
    float smoothness = tex2Dlod(_CameraGBufferTexture1, float4(fullResUV, 0.0, 0.0)).a;

    [branch]
    if (smoothness > 0.96 || smoothness < 0.4) // Disable on perfect mirror surfaces, and every rough surfaces don't have SSR
    {
        return centerColor;
    }


#if defined (VERTICAL_BLUR)
    uint kernelCount = 3;
    uint centerPixelId = 1;
    
    float kernel[3] = { 0.25, 1.0, 0.25 };
    int2 offset[3] = { int2(0, -1), int2(0, 0), int2(0, 1)};
    
#else
    uint kernelCount = 9;
    uint centerPixelId = 4;

    float kernel[9] =
    {
        0.25, 0.25, 0.25,
        0.25, 1.0, 0.25,
        0.25, 0.25, 0.25,
    };

    // This kernel is small enough that making it separable 3x3 doesn't help performance
    int2 offset[9] =
    {
        int2(-1, -1), int2(-1, 0), int2(-1, 1),
        int2(0, -1), int2(0, 0), int2(0, 1),
        int2(1, -1), int2(1, 0), int2(1, 1),
    };
#endif
    
    // Renormalize because 10-bit texture will mess up dot products
    float3 currentNormal = normalize(tex2Dlod(_CameraGBufferTexture2, float4(fullResUV, 0.0, 0.0)).rgb * 2.0 - 1.0.xxx);
 
    float hitDistance = tex2Dlod(ssrHitDistance, float4(halfResUV, 0.0, 3.0));
    
    float sizeInPixels;
    GetConeMipLevel(hitDistance, smoothness, sizeInPixels);

    float blurStrength = 1.0;

    if (sizeInPixels <= blurOffset)
    {
        blurStrength = saturate((sizeInPixels - prevBlurOffset) / (blurOffset - prevBlurOffset));
    }

    if (blurStrength < 0.001)
    {
        return centerColor;
    }

    float2 offsetSize = blurOffset.xx;

#if defined(HALF_RESOLUTION_TRACING)
    offsetSize.x *= 0.5;
#endif

    float4 color = 0.0;
    float totalWeight = 0;
    
    [unroll]
    for (uint k = 0; k < kernelCount; k++)
    {
        float2 sampleOffset = offset[k] * offsetSize;

        float2 sampleHalfResUV = halfResUV + sampleOffset * halfResTexelSize;

        // These help with smooth blurring on edges but I need to retest if they are actually needed, just a mirror repeat
        if (sampleHalfResUV.x > 1.0)
            sampleHalfResUV.x = 1.0 - (sampleHalfResUV.x - 1.0);

        if (sampleHalfResUV.x < 0.0)
            sampleHalfResUV.x = -sampleHalfResUV.x;

        if (sampleHalfResUV.y > 1.0)
            sampleHalfResUV.y = 1.0 - (sampleHalfResUV.y - 1.0);

        if (sampleHalfResUV.y < 0.0)
            sampleHalfResUV.y = -sampleHalfResUV.y;
        
#if defined(HALF_RESOLUTION_TRACING)
        float2 sampleFullResUV = GetFullResUVFromHalfResUV(sampleHalfResUV);
#else
        float2 sampleFullResUV = sampleHalfResUV;
#endif
        
        float3 normal = normalize(tex2Dlod(_CameraGBufferTexture2, float4(sampleFullResUV, 0.0, 0.0)).rgb * 2.0 - 1.0.xxx);

        float normalTolerance = 0.0025;
        
        // These are the same formulas used in the "à trous" filter paper for edge-stopping
        // I used very low normals tolerance to not overblur rough surfaces
        float3 normalDifference = currentNormal - normal;
        float normalDistanceSquared = max(dot(normalDifference, normalDifference), 0.0);
        float normalWeight = min(exp(-(normalDistanceSquared) / normalTolerance), 1.0);
        
        float weight = kernel[k] * normalWeight;
        

        if (k != centerPixelId)
        {
            weight *= blurStrength;
        }
        
        [branch]
        if (weight > 0.001)
        {
            float4 sampleColor = tex2Dlod(deferredSSRColorBuffer, float4(sampleHalfResUV, 0.0, 0.0));
            
            color += sampleColor * weight;
            totalWeight += weight;
        }
    }

    color /= max(totalWeight, 1e-8);

    // Smoothly fade to perfect mirror reflections
    color = lerp(color, centerColor, saturate((smoothness - 0.92) / 0.04));
    
    return color;
}