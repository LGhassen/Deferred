sampler2D _lowTex;
sampler2D _midTex;
sampler2D _highTex;
sampler2D _midBumpMap; // There seems to be only one normal map for all the different textures, wtf?

float _lowTiling;
float _midTiling;
float _highTiling;
float _midBumpTiling;

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

void SampleNonAtlasTextures(
    float3 triplanarWeights,
    float3 uv,
    float3 textureStrengths,
    inout float4 diffuseColor,
    inout float3 normalX,
    inout float3 normalY,
    inout float3 normalZ)
{
    
#if defined(LOW_TEXTURING_ON)
    diffuseColor += textureStrengths.x * SampleTriplanarDiffuse(_lowTex, triplanarWeights, uv * _lowTiling);
#endif
 
    diffuseColor += textureStrengths.y * SampleTriplanarDiffuse(_midTex, triplanarWeights, uv * _midTiling);
    
#if defined(HIGH_TEXTURING_ON)
    diffuseColor += textureStrengths.z * SampleTriplanarDiffuse(_highTex, triplanarWeights, uv * _highTiling);
#endif

    // There don't seem to be bumpmaps for low and high ???
    float3 normalsUV = uv * _midBumpTiling;

    normalX += UnpackNormalDXT5nm(tex2D(_midBumpMap, normalsUV.yz));
    normalY += UnpackNormalDXT5nm(tex2D(_midBumpMap, normalsUV.xz));
    normalZ += UnpackNormalDXT5nm(tex2D(_midBumpMap, normalsUV.xy));
}