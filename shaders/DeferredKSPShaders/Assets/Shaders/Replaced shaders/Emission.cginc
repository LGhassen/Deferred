float _RimFalloff;
float4 _RimColor;
float4 _TemperatureColor;

float3 GetTemperatureEmission()
{   
    return _TemperatureColor.a * _TemperatureColor.rgb;
}

// Just a classic fresnel effect as seen in https://www.ronja-tutorials.com/post/012-fresnel/
float3 GethighlightingEmission(float3 viewDir, float3 normal)
{
    float fresnel = dot(viewDir, normal);
    fresnel = saturate(1 - fresnel);
    fresnel = pow(fresnel, _RimFalloff);

    return _RimColor.a * fresnel * _RimColor.rgb;
}

float3 GetEmission(float3 viewDir, float3 normal)
{
    return GetTemperatureEmission() + GethighlightingEmission(viewDir, normal);
}