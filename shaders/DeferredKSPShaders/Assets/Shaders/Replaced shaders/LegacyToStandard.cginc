#define blinnPhongShininessPower 0.215

// An exact conversion from blinn-phong to PBR is impossible, but the look can be approximated perceptually
// and by observing how blinn-phong looks and feels at various settings, although it can never be perfect
// 1) The specularColor can be used as is in the PBR specular flow, just needs to be divided by PI so it sums up to 1 over the hemisphere
// 2) Blinn-phong shininess doesn't stop feeling shiny unless at very low values, like below 0.04
// while the PBR smoothness feels more linear -> map shininess to smoothness accordingly using a function
// that increases very quickly at first then slows down, I went with something like x^(1/4) or x^(1/6) then made the power configurable
// I tried various mappings from the literature but nothing really worked as well as this
// 3) Finally I noticed that some parts still looked very shiny like the AV-R8 winglet while in stock they looked rough thanks a low
// specularColor but high shininess and specularMap, so I multiplied the smoothness by the sqrt of the specularColor and that caps
// the smoothness when specularColor is low
void GetStandardSpecularPropertiesFromLegacy(float legacyShininess, float specularMap, float3 legacySpecularColor, 
                                             out float smoothness, out float3 specular)
{
    legacySpecularColor = saturate(legacySpecularColor);
    
    smoothness = pow(legacyShininess, blinnPhongShininessPower) * specularMap;
    smoothness *= sqrt(length(legacySpecularColor));

    specular = legacySpecularColor * (1 / UNITY_PI);
}