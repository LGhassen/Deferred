// Whiteout normals blending from https://bgolus.medium.com/normal-mapping-for-a-triplanar-shader-10bf39dca05a#da52
float3 CalculateTriplanarWorldNormal(float3 normalX, float3 normalY, float3 normalZ, float3 worldNormal, float3 triplanarWeights)
{
    // Swizzle world normals into tangent space and apply Whiteout blend
    normalX = half3(normalX.xy + worldNormal.zy, abs(normalX.z) * worldNormal.x);
    normalY = half3(normalY.xy + worldNormal.xz, abs(normalY.z) * worldNormal.y);
    normalZ = half3(normalZ.xy + worldNormal.xy, abs(normalZ.z) * worldNormal.z);

    // Swizzle tangent normals to match world orientation and triblend
    return normalize(normalX.zyx * triplanarWeights.x + normalY.xzy * triplanarWeights.y + normalZ.xyz * triplanarWeights.z);
}

float3 GetTriplanarWeights(float3 normal)
{
    // The higher triplanarSharpness the sharper the transition between the planar maps will be
    float triplanarSharpness = 8.0;
    
    float3 blendWeights = pow(abs(normal), triplanarSharpness);

    // Divide our blend mask by the sum of it's components, this will make x+y+z=1
    return blendWeights / max(blendWeights.x + blendWeights.y + blendWeights.z, 1e-10);
}