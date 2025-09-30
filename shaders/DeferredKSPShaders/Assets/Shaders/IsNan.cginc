bool IsNanFloat(float input)
{
	// turns out this isn't reliable enough, from https://developer.download.nvidia.com/cg/isnan.html
	// return s != s;
    return (input < 0.0 || input > 0.0 || input == 0.0) ? false : true;
}

bool IsNanFloat3(float3 input)
{
    return IsNanFloat(input.r) || IsNanFloat(input.g) || IsNanFloat(input.b);
}

bool IsNanFloat4(float4 input)
{
    return IsNanFloat(input.r) || IsNanFloat(input.g) || IsNanFloat(input.b) || IsNanFloat(input.a);
}