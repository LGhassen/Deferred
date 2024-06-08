UNITY_DECLARE_TEX2DARRAY(_AtlasTex);
UNITY_DECLARE_TEX2DARRAY(_NormalTex);
float _AtlasTiling;

// Work out the packed indices for the atlas textures which are packed into a single float in the uv data
// This is the inverse of the logic used in the PQSMod_TextureAtlas to perform the packing
// For some reason I had to change the formula to not multiply every value by 10 (ie results
// are divided by 10 compared to the original value), not sure why
float4 UnpackAtlasTextureIndices(float packedIndices)
{
    float4 indices;
    
    [unroll]
    for (int i = 3; i >= 0; i--)
    {
        indices[i] = (packedIndices % 32);
        packedIndices = (packedIndices - indices[i]) / 32;
    }
    
    return indices;
}

// Work out the packed strengths for the atlas textures which are packed into a single float in the uv data
// This is also the inverse of the logic used in the PQSMod_TextureAtlas to perform the packing
// Couldn't make a neat loop out of this
float4 UnpackAtlasTextureStrengths(float packedStrengths)
{
    float4 strengths;
    
    strengths[0] = (int) (packedStrengths / 40000.0f);
    packedStrengths -= strengths[0] * 40000.0f;
    strengths[0] /= 200.0f;

    strengths[1] = (int) (packedStrengths / 200.0f);
    packedStrengths -= strengths[1] * 200.0f;
    strengths[1] /= 100.0f;

    strengths[2] = packedStrengths / 100.0f;

    strengths[3] = 1.0f - strengths[0] - strengths[1] - strengths[2];

    return strengths;
}

void SampleAtlasTextures(
    float3 triplanarWeights,
    float3 uv,
    float4 atlasTextureArrayCoordinates,
    float4 atlasTextureArrayStrengths,
    inout float4 diffuseColor,
    inout float3 normalX,
    inout float3 normalY,
    inout float3 normalZ)
{
    uv *= _AtlasTiling;
    
    // Triplanar UVs
    float2 xUV = uv.yz;
    float2 yUV = uv.xz;
    float2 zUV = uv.xy;
    
    // Sample and blend diffuse for all the atlas textures
    [unroll]
    for (int atlasId = 0; atlasId < ATLAS_TEXTURE_COUNT; atlasId++)
    {
        [branch]
        if (atlasTextureArrayStrengths[atlasId] > 0.001)
        {
            float4 atlasTexture = triplanarWeights.x * UNITY_SAMPLE_TEX2DARRAY(_AtlasTex, float3(xUV, atlasTextureArrayCoordinates[atlasId])) +
                                  triplanarWeights.y * UNITY_SAMPLE_TEX2DARRAY(_AtlasTex, float3(yUV, atlasTextureArrayCoordinates[atlasId])) +
                                  triplanarWeights.z * UNITY_SAMPLE_TEX2DARRAY(_AtlasTex, float3(zUV, atlasTextureArrayCoordinates[atlasId]));
        
            diffuseColor += atlasTexture * atlasTextureArrayStrengths[atlasId];
        }
    }
    
    // Sample and blend normals for all the atlas textures
    // Here I'm doing the equivalent of a simple lerp on all the tangent-space normals textures, which I'm sure is a big no-no
    // but I'm not spending more time on this
    [unroll]
    for (atlasId = 0; atlasId < ATLAS_TEXTURE_COUNT; atlasId++)
    {
        [branch]
        if (atlasTextureArrayStrengths[atlasId] > 0.001)
        {
            half3 atlasNormalX = UnpackNormal(UNITY_SAMPLE_TEX2DARRAY(_NormalTex, float3(xUV, atlasTextureArrayCoordinates[atlasId])));
            half3 atlasNormalY = UnpackNormal(UNITY_SAMPLE_TEX2DARRAY(_NormalTex, float3(yUV, atlasTextureArrayCoordinates[atlasId])));
            half3 atlasNormalZ = UnpackNormal(UNITY_SAMPLE_TEX2DARRAY(_NormalTex, float3(zUV, atlasTextureArrayCoordinates[atlasId])));
        
            normalX += atlasNormalX * atlasTextureArrayStrengths[atlasId];
            normalY += atlasNormalY * atlasTextureArrayStrengths[atlasId];
            normalZ += atlasNormalZ * atlasTextureArrayStrengths[atlasId];
        }
    }
}