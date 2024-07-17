sampler2D _lowTex;
sampler2D _midTex;
sampler2D _highTex;

sampler2D _lowBumpMap;
sampler2D _midBumpMap;
sampler2D _highBumpMap;

float _lowTiling;
float _midTiling;
float _highTiling;

// Used only in zoomable shaders
float _lowBumpTiling;
float _midBumpTiling;
float _highBumpTiling;

// Used only in non-zoomable shaders
float _groundTexStart;
float _groundTexEnd;

float _lowNearTiling;
float _lowMultiFactor;
float _lowBumpNearTiling;
float _lowBumpFarTiling;

float _midNearTiling;
float _midMultiFactor;
float _midBumpNearTiling;
float _midBumpFarTiling;

float _highNearTiling;
float _highMultiFactor;
float _highBumpNearTiling;
float _highBumpFarTiling;

float _steepNearTiling;
float _steepTiling;

// Altitudes for where the different textures are used, otherwise use mid texture
float _lowStart;
float _lowEnd;
float _highStart;
float _highEnd;

float3 GetNonAtlasTextureWeights(float relativeAltitude)
{
    float3 textureWeights;
    
    // From _lowStart, we use the low texture then it's weight decreases until it reaches _lowEnd
    // The alpha channel of the vertex Color contains the relative (0-1) altitude calculated by PQSMod_AltitudeAlpha
    textureWeights.x = 1.0 - saturate((relativeAltitude - _lowStart) / (_lowEnd - _lowStart));
    
    // From _highStart to _highEnd the weight of the high texture increases
    textureWeights.z = saturate((relativeAltitude - _highStart) / (_highEnd - _highStart));
    
    // In between those two we use the mid texture
    textureWeights.y = 1.0 - textureWeights.x - textureWeights.z;
    
    return textureWeights;
}

float4 SampleTriplanarDiffuse(sampler2D tex, float3 triplanarWeights, float3 uv)
{
    return triplanarWeights.x * tex2D(tex, uv.yz) + triplanarWeights.y * tex2D(tex, uv.xz) + triplanarWeights.z * tex2D(tex, uv.xy);
}

void SampleTriplanarNormals(sampler2D tex, float weight, float3 uv, inout float3 normalX, inout float3 normalY, inout float3 normalZ)
{
    normalX += weight * UnpackNormalDXT5nm(tex2D(tex, uv.yz));
    normalY += weight * UnpackNormalDXT5nm(tex2D(tex, uv.xz));
    normalZ += weight * UnpackNormalDXT5nm(tex2D(tex, uv.xy));
}

void SampleAndBlendSteep(
    float3 triplanarWeights,
    float3 uv,
    float steepTiling,
    float cliffDotProduct,
    inout float4 diffuseColor,
    inout float3 normalX,
    inout float3 normalY,
    inout float3 normalZ)
{
    float4 cliffColor = 0.0.xxxx;
    float3 cliffNormalX = float3(0.0, 0.0, 1.0), cliffNormalY = float3(0.0, 0.0, 1.0), cliffNormalZ = float3(0.0, 0.0, 1.0);
    
#if defined(ATLAS_TEXTUREARRAY_ON)
    uv *= _AtlasTiling;
#else
    uv *= steepTiling;
#endif
    
    [branch]
    if (cliffDotProduct > 0.001)
    {
        cliffColor = SampleTriplanarDiffuse(_steepTex, triplanarWeights, uv);
        SampleTriplanarNormals(_steepBumpMap, 1.0, uv, cliffNormalX, cliffNormalY, cliffNormalZ);
    }
    
    // Blend the regular results with the cliff/steep ones
    diffuseColor = lerp(diffuseColor, cliffColor, cliffDotProduct);
    normalX = lerp(normalX, cliffNormalX, cliffDotProduct);
    normalY = lerp(normalY, cliffNormalY, cliffDotProduct);
    normalZ = lerp(normalZ, cliffNormalZ, cliffDotProduct);
}

void SampleNonAtlasTextures(
    float3 triplanarWeights,
    float3 uv,
    float3 textureStrengths,
    float lowTiling,
    float midTiling,
    float highTiling,
    float lowBumpTiling,
    float midBumpTiling,
    float highBumpTiling,
    float cliffDotProduct,
    inout float4 diffuseColor,
    inout float3 normalX,
    inout float3 normalY,
    inout float3 normalZ)
{
     
#if defined(STEEP_TEXTURING_ON)
    [branch]
    if (cliffDotProduct < 0.999)
#endif
    {
#if defined(LOW_TEXTURING_ON)
        diffuseColor += textureStrengths.x * SampleTriplanarDiffuse(_lowTex, triplanarWeights, uv * lowTiling);
#endif

        diffuseColor += textureStrengths.y * SampleTriplanarDiffuse(_midTex, triplanarWeights, uv * midTiling);
    
#if defined(HIGH_TEXTURING_ON)
        diffuseColor += textureStrengths.z * SampleTriplanarDiffuse(_highTex, triplanarWeights, uv * highTiling);
#endif
    
#if defined(SEPARATE_LOW_HIGH_BUMP_MAPS_ON)
        
    #if defined(LOW_TEXTURING_ON)
        SampleTriplanarNormals(_lowBumpMap, textureStrengths.x, uv * lowBumpTiling, normalX, normalY, normalZ);
    #endif
 
        SampleTriplanarNormals(_midBumpMap, textureStrengths.y, uv * midBumpTiling, normalX, normalY, normalZ);
    
    #if defined(HIGH_TEXTURING_ON)
        SampleTriplanarNormals(_highBumpMap, textureStrengths.z, uv * highBumpTiling, normalX, normalY, normalZ);
    #endif
        
#else
        SampleTriplanarNormals(_midBumpMap, 1.0, uv * midBumpTiling, normalX, normalY, normalZ);
#endif
    }
}