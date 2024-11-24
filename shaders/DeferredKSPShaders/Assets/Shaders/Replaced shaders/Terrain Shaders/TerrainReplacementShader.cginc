sampler2D _steepTex;
sampler2D _steepBumpMap;

float4 _floatingOriginOffset;
float _factor; // This is the factor that controls by how much the size of the tiling increases every zoom level

float _steepPower;
float _albedoBrightness;
float _PlanetOpacity;

float4 _specularColor;

// Stock variables that tweak the vertex color
float _contrast;
float4 _tintColor;

struct Input
{
    float3 worldPos;
    float3 worldSpaceNormal;
    float4 worldToTangent0;
    float4 worldToTangent1;
    float4 worldToTangent2;

    float4 atlasTextureArrayCoordinates;
    float4 atlasTextureArrayStrengths;
    
    float4 vertexColor;
    float cliffDotProduct;
    
    float4 screenPos;
};

#include "./AtlasUtils.cginc"
#include "./NonAtlasUtils.cginc"
#include "./TriplanarUtils.cginc"

void TerrainReplacementVertexShader(inout appdata_full v, out Input o)
{
    UNITY_INITIALIZE_OUTPUT(Input, o);

    float3 worldNormal = UnityObjectToWorldNormal(v.normal);
 
    TANGENT_SPACE_ROTATION;

    float3x3 worldToTangent = mul(rotation, (float3x3) unity_WorldToObject);
    o.worldToTangent0 = float4(worldToTangent[0], worldNormal.x);
    o.worldToTangent1 = float4(worldToTangent[1], worldNormal.y);
    o.worldToTangent2 = float4(worldToTangent[2], worldNormal.z);

    o.worldSpaceNormal = worldNormal;
    
    // Atlas indices and strengths are packed per vertex and are not safe to interpolate before unpacking
    // The packing is done by PQSMod_TextureAtlas
    o.atlasTextureArrayCoordinates = UnpackAtlasTextureIndices(v.texcoord2.x);
    o.atlasTextureArrayStrengths = UnpackAtlasTextureStrengths(v.texcoord2.y);
    
    o.cliffDotProduct = v.texcoord1.y; // This seems to be precalculated in the PQSMod UVPlanetRelativePosition
    
#if defined(ATLAS_TEXTUREARRAY_ON)
    // Use vertexColors as they are for the atlas shader since it looks better. It is only used on stock Kerbin
    // and not adopted by modders so it doesn't have to be accurate to the original 
    o.vertexColor.rgb = v.color.rgb;
#else
    // Not entirely sure about this, but results are closest to how stock looks
    o.vertexColor.rgb = lerp(_tintColor.a * _tintColor.rgb, v.color.rgb, _contrast);    
#endif

    // The alpha channel of the vertex Color contains the relative (0-1) altitude calculated by PQSMod_AltitudeAlpha
    o.vertexColor.a = v.color.a;
    
    o.screenPos = ComputeScreenPos(UnityObjectToClipPos(v.vertex));
}

void SampleZoomLevel(
    float3 worldPos,
    float3 triplanarWeights,
    float cliffDotProduct,
    int zoomLevel,
    float4 atlasTextureArrayCoordinates,
    float4 atlasTextureArrayStrengths,
    float3 textureWeights,
    out float4 diffuseColor,
    out float3 normalX,
    out float3 normalY,
    out float3 normalZ)
{
    float tiling = 1.0 / (pow(_factor, zoomLevel) * 50000.0); // Idk about the 50000.0 but my tiling was too small
    float3 uv = (worldPos + _floatingOriginOffset.xyz) * tiling;
    
    diffuseColor = 0.0.xxxx;
    normalX = 0.0.xxx, normalY = 0.0.xxx, normalZ = 0.0.xxx; // Separate normals for the 3 planes
    
#if defined(STEEP_TEXTURING_ON)
    [branch]
    if (cliffDotProduct < 0.999)
#endif
    {
        #if defined(ATLAS_TEXTUREARRAY_ON)
            SampleAtlasTextures(triplanarWeights, uv, atlasTextureArrayCoordinates, atlasTextureArrayStrengths, diffuseColor, normalX, normalY, normalZ);
        #else
            SampleNonAtlasTextures(triplanarWeights, uv, textureWeights, _lowTiling, _midTiling, _highTiling, _lowBumpTiling, _midBumpTiling,
                                        _highBumpTiling, cliffDotProduct, diffuseColor, normalX, normalY, normalZ);
        #endif
    }
  
#if defined(STEEP_TEXTURING_ON)
    SampleAndBlendSteep(triplanarWeights, uv, _steepTiling, cliffDotProduct, diffuseColor, normalX, normalY, normalZ);
#endif
}

// Every zoom level covers a distance _factor times bigger than the previous one
// Use log base _factor to find the zoom level
void FindCurrentZoomLevel(float cameraDistance, out float zoomLevel, out float zoomTransition)
{
    zoomLevel = log(cameraDistance) / log(_factor);
    zoomTransition = frac(zoomLevel);
    zoomLevel = max(zoomLevel - zoomTransition, 0.0);
}

void SampleZoomableTextures(
    float cameraDistance,
    float3 worldPos,
    float3 triplanarWeights,
    float cliffDotProduct,
    float4 atlasTextureArrayCoordinates,
    float4 atlasTextureArrayStrengths,
    float3 nonAtlasTextureWeights,
    out float4 diffuseColor,
    out float3 normalX,
    out float3 normalY,
    out float3 normalZ)
{
    float zoomLevel, zoomTransition;
    FindCurrentZoomLevel(cameraDistance, zoomLevel, zoomTransition);
    
    // Sample current zoom level
    float4 currentZoomLevelDiffuse = 0.0.xxxx;
    float3 currentZoomLevelNormalX = 0.0.xxx, currentZoomLevelNormalY = 0.0.xxx, currentZoomLevelNormalZ = 0.0.xxx;
    
    SampleZoomLevel(worldPos, triplanarWeights, cliffDotProduct, zoomLevel, atlasTextureArrayCoordinates, atlasTextureArrayStrengths,
                    nonAtlasTextureWeights,currentZoomLevelDiffuse, currentZoomLevelNormalX, currentZoomLevelNormalY, currentZoomLevelNormalZ);

    
    // Sample next zoom level
    float4 nextZoomLevelDiffuse = 0.0.xxxx;
    float3 nextZoomLevelNormalX = 0.0.xxx, nextZoomLevelNormalY = 0.0.xxx, nextZoomLevelNormalZ = 0.0.xxx;
    
    SampleZoomLevel(worldPos, triplanarWeights, cliffDotProduct, zoomLevel + 1, atlasTextureArrayCoordinates, atlasTextureArrayStrengths,
                    nonAtlasTextureWeights, nextZoomLevelDiffuse, nextZoomLevelNormalX, nextZoomLevelNormalY, nextZoomLevelNormalZ);
    
    // Blend results
    diffuseColor = lerp(currentZoomLevelDiffuse, nextZoomLevelDiffuse, zoomTransition);
    normalX = lerp(currentZoomLevelNormalX, nextZoomLevelNormalX, zoomTransition);
    normalY = lerp(currentZoomLevelNormalY, nextZoomLevelNormalY, zoomTransition);
    normalZ = lerp(currentZoomLevelNormalZ, nextZoomLevelNormalZ, zoomTransition);
}

void SampleLegacyNonZoomableTextures(
    float cameraDistance,
    float3 worldPos,
    float3 triplanarWeights,
    float cliffDotProduct,
    float3 nonAtlasTextureWeights,
    out float4 diffuseColor,
    out float3 normalX,
    out float3 normalY,
    out float3 normalZ)
{
    float nearFarTilingTransition = saturate((cameraDistance - _groundTexStart) / (_groundTexEnd - _groundTexStart));
    
    // Idk about the 50000.0 but my tiling was too small    
    float3 uv = (worldPos + _floatingOriginOffset.xyz) / 50000.0;

    float4 nearDiffuse = 0.0.xxxx;
    float3 nearNormalX = 0.0.xxx, nearNormalY = 0.0.xxx, nearNormalZ = 0.0.xxx;
    
#if defined(LEGACY_PROJECTION_SHADER)
    diffuseColor = 0.0.xxxx;
    normalX = 0.0.xxx; normalY = 0.0.xxx; normalZ = 0.0.xxx;
    SampleLegacyProjectionTextures(triplanarWeights, uv, nonAtlasTextureWeights, diffuseColor);
    return;
#else
    #if !defined(SEPARATE_NEAR_FAR_BUMP_MAP_TILINGS_ON)
        _lowBumpFarTiling = _lowBumpNearTiling;
        _midBumpFarTiling = _midBumpNearTiling;
        _highBumpFarTiling = _highBumpNearTiling;
    #endif
    
        SampleNonAtlasTextures(triplanarWeights, uv, nonAtlasTextureWeights, _lowNearTiling, _midNearTiling, _highNearTiling, _lowBumpNearTiling, _midBumpNearTiling,
                            _highBumpNearTiling, cliffDotProduct, nearDiffuse, nearNormalX, nearNormalY, nearNormalZ);
    
    #if defined(STEEP_TEXTURING_ON)
        SampleAndBlendSteep(triplanarWeights, uv, _steepNearTiling, cliffDotProduct, nearDiffuse, nearNormalX, nearNormalY, nearNormalZ);
    #endif
    
        float4 farDiffuse = 0.0.xxxx;
        float3 farNormalX = 0.0.xxx, farNormalY = 0.0.xxx, farNormalZ = 0.0.xxx;
    
        SampleNonAtlasTextures(triplanarWeights, uv, nonAtlasTextureWeights, _lowMultiFactor, _midMultiFactor, _highMultiFactor, _lowBumpFarTiling, _midBumpFarTiling,
                            _highBumpFarTiling, cliffDotProduct, farDiffuse, farNormalX, farNormalY, farNormalZ);

    #if defined(STEEP_TEXTURING_ON)
        SampleAndBlendSteep(triplanarWeights, uv, _steepTiling, cliffDotProduct, farDiffuse, farNormalX, farNormalY, farNormalZ);
    #endif
    
        // Blend results
        diffuseColor = lerp(nearDiffuse, farDiffuse, nearFarTilingTransition);
        normalX = lerp(nearNormalX, farNormalX, nearFarTilingTransition);
        normalY = lerp(nearNormalY, farNormalY, nearFarTilingTransition);
        normalZ = lerp(nearNormalZ, farNormalZ, nearFarTilingTransition);
#endif
}

void DeferredTerrainReplacementShader(Input i, inout SurfaceOutputStandard o)
{    
    float cameraDistance = length(i.worldPos - _WorldSpaceCameraPos);
    cameraDistance = max(cameraDistance, 3.0); // Got some weird artifacts close to the camera
    
    float cliffDotProduct = saturate(i.cliffDotProduct * _steepPower);
    float3 triplanarWeights = GetTriplanarWeights(i.worldSpaceNormal);
    
    float3 nonAtlasTextureWeights = GetNonAtlasTextureWeights(i.vertexColor.a);

    float4 diffuse = 0.0.xxxx;
    float3 normalX = 0.0.xxx, normalY = 0.0.xxx, normalZ = 0.0.xxx;
    
#if defined(LEGACY_NON_ZOOMABLE_TERRAIN_SHADER)
    SampleLegacyNonZoomableTextures(cameraDistance, i.worldPos, triplanarWeights, i.cliffDotProduct,
                            nonAtlasTextureWeights, diffuse, normalX, normalY, normalZ);
#else
    SampleZoomableTextures(cameraDistance, i.worldPos, triplanarWeights, i.cliffDotProduct, i.atlasTextureArrayCoordinates,
                            i.atlasTextureArrayStrengths, nonAtlasTextureWeights, diffuse, normalX, normalY, normalZ);
#endif
    
    // Calculate the resulting normal from triplanar normals
    float3 worldNormal = CalculateTriplanarWorldNormal(normalX, normalY, normalZ, i.worldSpaceNormal, triplanarWeights);
    
    // The resulting normal is unfortunately in world space, convert it back to tanget space which is what surface shaders use
    // This is awful and a waste of calculations but I'm too lazy to do this in a normal shader now
    // As seen in https://forum.unity.com/threads/triplanar-shader-using-world-normals-bump-mapping-help.426757/
    float3 tangetSpaceNormal = normalize(float3(dot(worldNormal, i.worldToTangent0.xyz),
                                                dot(worldNormal, i.worldToTangent1.xyz),
                                                dot(worldNormal, i.worldToTangent2.xyz)));


#if defined(ATLAS_TEXTUREARRAY_ON)
    // Since the atlas shader is only used on stock Kerbin, and not adopted by modders
    // We can use different color blending that looks better
    diffuse.rgb *= 1.75 * i.vertexColor.rgb;
#else
    // Approximates stock look for the most part, only a little bit off
    diffuse.rgb = lerp(i.vertexColor.rgb, i.vertexColor.rgb * diffuse.rgb, 0.8).rgb;
#endif
    
#if defined(LEGACY_NON_ZOOMABLE_TERRAIN_SHADER)
    o.Smoothness = 0.1; // the originals are lambertian so go with low smoothness
#elif defined(ATLAS_TEXTUREARRAY_OFF)
    float specularColorLength = saturate(length(_specularColor.rgb));
    o.Smoothness = sqrt(max(specularColorLength, 0.1)) * diffuse.a;
#else
    o.Smoothness = diffuse.a;
#endif
        
    o.Albedo = diffuse * _albedoBrightness;
    
#if defined(LEGACY_PROJECTION_SHADER)
    o.Normal = float3(0.0, 0.0, 1.0);
#else
    o.Normal = tangetSpaceNormal;
#endif
    o.Emission = 0.0;
    o.Occlusion = 1.0;
    o.Metallic = 0.0;
    
#if UNITY_PASS_DEFERRED
	// In deferred rendering do not use the flat ambient because Deferred adds its own ambient as a composite of flat ambient and probe
    // Also do not use #pragma skip_variants LIGHTPROBE_SH because it impacts lighting in forward and some elements can still render in
	// forward e.g through the VAB scene doors
	unity_SHAr = 0.0.xxxx;
	unity_SHAg = 0.0.xxxx;
	unity_SHAb = 0.0.xxxx;
#endif
}