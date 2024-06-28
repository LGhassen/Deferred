sampler2D _steepTex;
sampler2D _steepBumpMap;

float4 _floatingOriginOffset;
float _factor; // This is the factor that controls by how much the size of the tiling increases every zoom level

float _steepPower;
float _albedoBrightness;
float _PlanetOpacity;

float4 _specularColor;

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
    o.vertexColor = v.color;
    
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
            SampleNonAtlasTextures(triplanarWeights, uv, textureWeights, diffuseColor, normalX, normalY, normalZ);
        #endif
    }
  
#if defined(STEEP_TEXTURING_ON)
    // Sample cliff if needed
    float4 cliffColor = 0.0.xxxx;
    float3 cliffNormalX = float3(0.0, 0.0, 1.0), cliffNormalY = float3(0.0, 0.0, 1.0), cliffNormalZ = float3(0.0, 0.0, 1.0);
    
    #if defined(ATLAS_TEXTUREARRAY_ON)
        uv *= _AtlasTiling;
    #else
        uv *= _midTiling; // This probably doesn't match stock but I tried using steepTiling and nearSteepTiling and got weird results, probably both ignore zoom levels
#endif
    
    // Triplanar UVs
    float2 xUV = uv.yz;
    float2 yUV = uv.xz;
    float2 zUV = uv.xy;
    
    [branch]
    if (cliffDotProduct > 0.001)
    {
        cliffColor = triplanarWeights.x * tex2D(_steepTex, xUV) + triplanarWeights.y * tex2D(_steepTex, yUV) + triplanarWeights.z * tex2D(_steepTex, zUV);
        cliffNormalX = UnpackNormal(tex2D(_steepBumpMap, xUV));
        cliffNormalY = UnpackNormal(tex2D(_steepBumpMap, yUV));
        cliffNormalZ = UnpackNormal(tex2D(_steepBumpMap, zUV));
    }
    
    // Blend the regular results with the cliff/steep ones
    diffuseColor = lerp(diffuseColor, cliffColor, cliffDotProduct);
    normalX = lerp(normalX, cliffNormalX, cliffDotProduct);
    normalY = lerp(normalY, cliffNormalY, cliffDotProduct);
    normalZ = lerp(normalZ, cliffNormalZ, cliffDotProduct);
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

void DeferredTerrainReplacementShader(Input i, inout SurfaceOutputStandard o)
{    
    float cameraDistance = length(i.worldPos - _WorldSpaceCameraPos);
    cameraDistance = max(cameraDistance, 3.0); // Got some weird artifacts close to the camera

    float zoomLevel, zoomTransition;
    FindCurrentZoomLevel(cameraDistance, zoomLevel, zoomTransition);
    
    float cliffDotProduct = saturate(i.cliffDotProduct * _steepPower);
    float3 triplanarWeights = GetTriplanarWeights(i.worldSpaceNormal);
    
    float3 nonAtlasTextureWeights = GetNonAtlasTextureWeights(i.vertexColor.a); // The alpha channel of the vertex Color contains the relative (0-1)
                                                                                // altitude calculated by PQSMod_AltitudeAlpha

    // Sample current zoom level
    float4 currentZoomLevelDiffuse = 0.0.xxxx;
    float3 currentZoomLevelNormalX = 0.0.xxx, currentZoomLevelNormalY = 0.0.xxx, currentZoomLevelNormalZ = 0.0.xxx;
    
    SampleZoomLevel(i.worldPos, triplanarWeights, cliffDotProduct, zoomLevel, i.atlasTextureArrayCoordinates, i.atlasTextureArrayStrengths, nonAtlasTextureWeights,
                    currentZoomLevelDiffuse, currentZoomLevelNormalX, currentZoomLevelNormalY, currentZoomLevelNormalZ);

    // Sample next zoom level
    float4 nextZoomLevelDiffuse = 0.0.xxxx;
    float3 nextZoomLevelNormalX = 0.0.xxx, nextZoomLevelNormalY = 0.0.xxx, nextZoomLevelNormalZ = 0.0.xxx;
    
    SampleZoomLevel(i.worldPos, triplanarWeights, cliffDotProduct, zoomLevel + 1, i.atlasTextureArrayCoordinates, i.atlasTextureArrayStrengths, nonAtlasTextureWeights,
                    nextZoomLevelDiffuse, nextZoomLevelNormalX, nextZoomLevelNormalY, nextZoomLevelNormalZ);

    // Blend results
    float4 diffuse = lerp(currentZoomLevelDiffuse, nextZoomLevelDiffuse, zoomTransition);
    float3 normalX = lerp(currentZoomLevelNormalX, nextZoomLevelNormalX, zoomTransition);
    float3 normalY = lerp(currentZoomLevelNormalY, nextZoomLevelNormalY, zoomTransition);
    float3 normalZ = lerp(currentZoomLevelNormalZ, nextZoomLevelNormalZ, zoomTransition);
    
    // Calculate the resulting normal from triplanar normals
    float3 worldNormal = CalculateTriplanarWorldNormal(normalX, normalY, normalZ, i.worldSpaceNormal, triplanarWeights);
    
    // The resulting normal is unfortunately in world space, convert it back to tanget space which is what surface shaders use
    // This is awful and a waste of calculations but I'm too lazy to do this in a normal shader now
    // As seen in https://forum.unity.com/threads/triplanar-shader-using-world-normals-bump-mapping-help.426757/
    float3 tangetSpaceNormal = normalize(float3(dot(worldNormal, i.worldToTangent0.xyz),
                                                dot(worldNormal, i.worldToTangent1.xyz),
                                                dot(worldNormal, i.worldToTangent2.xyz)));

#if defined(ATLAS_TEXTUREARRAY_ON)
    diffuse.rgb *= 1.75;    // My shader is darker than the stock one for some reason so make it brighter
#endif
    
    diffuse.rgb *= i.vertexColor.rgb;

    o.Smoothness = diffuse.a;
    
#if defined(ATLAS_TEXTUREARRAY_OFF)
    float specularColorLength = saturate(length(_specularColor.rgb));
    o.Smoothness *= sqrt(max(specularColorLength, 0.1));
#endif
        
    o.Albedo = diffuse * _albedoBrightness;
    o.Normal = tangetSpaceNormal;
    o.Emission = 0.0;
    o.Occlusion = 1.0;
    //o.Specular = _specularColor.rgb;
    o.Metallic = 0.0;
}