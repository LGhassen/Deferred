// NDF formula as seen in: https://agraphicsguynotes.com/posts/sample_microfacet_brdf/
// To get an approximate specular cone angle, simply take the NDF formula and try to put bounds
// on it that capture most of the energy. I went with E = 0.5 empirically
inline float ApproximateGGXSpecularConeAngle(float smoothness)
{
    float E = 0.5;
    float roughness = 1.0 - smoothness;
    return atan(roughness * roughness * E / (1.0 - E));
}

inline float GetConeMipLevel(float hitDistance, float smoothness, out float sizeInPixels)
{
    // Approximate the ray as a cone to get the radius of the area to sample
    float coneAngle = ApproximateGGXSpecularConeAngle(smoothness);
    
    float coneLength = hitDistance;
    float rightTriangleOppositeSide = coneLength * tan(coneAngle);

    sizeInPixels = 0.75 * rightTriangleOppositeSide * max(BufferSize.x, BufferSize.y); // 0.75  is a fudge  factor to match the
                                                                                       // reference importance sampled version
                
    float ssrMipLevel = log2(sizeInPixels);
    
    return ssrMipLevel;
}

// Approximate specular elongation using hardware anisotropic filtering
// Originally I used a LUT as explained in "Approximate models for physically based rendering" to get
// a physically-based result, approximating the full GGX specular lobe with a few gaussian lobes.
// Because of issues with the LUT provided and edge cases in the code, I decided to use a much simpler
// empirical approximation as seen here
inline float GetConeMipLevelAndAnisotropicDerivatives(float hitDistance, float3 textureSpaceReflectionDirection,
                                                      float smoothness, float dotVN, out float2 ddx, out float2 ddy)
{
    
    // Approximate the ray as a cone to get the radius of the area to sample
    float coneAngle = ApproximateGGXSpecularConeAngle(smoothness);
    
    float coneLength = hitDistance;
    float rightTriangleOppositeSide = coneLength * tan(coneAngle);

    float sizeInPixels = 0.75 * rightTriangleOppositeSide * max(BufferSize.x, BufferSize.y); // 0.75  is a fudge  factor to match the reference importance sampled version
                
    float ssrMipLevel = log2(sizeInPixels);

    // My simplistic approximation for specular elongation, tweaked by comparing to the true importance sampled reference
    float elongationFactor = lerp(4.0, 1.0, dotVN); // Apply only when grazing
    
    // Calculate custom derivatives for anisotropic filtering
    ddx = float2(rightTriangleOppositeSide / elongationFactor, 0.0);
    ddy = float2(0.0, rightTriangleOppositeSide * elongationFactor);

    // Then rotate them to match the orientation of the surface in screen space
    float2 verticalVector = float2(0.0, 1.0);
    float cosTheta = dot(textureSpaceReflectionDirection, verticalVector);

    //float det = textureSpaceReflectionDirection.y * verticalVector.x - textureSpaceReflectionDirection.x * verticalVector.y;
    float det = -textureSpaceReflectionDirection.x;

    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
    sinTheta = sign(det) * sinTheta;

    float2x2 rotationMatrix = float2x2(cosTheta, -sinTheta, sinTheta, cosTheta);

    ddx = mul(rotationMatrix, ddx);
    ddy = mul(rotationMatrix, ddy);
    
    return ssrMipLevel;
}