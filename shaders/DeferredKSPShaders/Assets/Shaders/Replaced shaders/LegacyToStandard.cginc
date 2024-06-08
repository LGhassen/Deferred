// Highly questionable blinn phong to smoothness conversion that kinda works
// to maintain the original look of parts
float GetSmoothnessFromLegacyParams(float3 specularColor, float shininess, float specularMap)
{
    float smoothness = shininess * specularMap;
    smoothness = max(smoothness, 0.0000001);
    
    smoothness = sqrt(sqrt(smoothness));
    
    float specularColorMag = length(specularColor);
    specularColorMag = max(specularColorMag, 0.0000001);
    return smoothness * pow(specularColorMag, 1.0 / 40.0);
}