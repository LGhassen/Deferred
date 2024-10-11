int hiZMipLevelCount;
int2 ScreenResolution;

sampler2D hiZTexture;

float GetMinDepth(float2 ray, float level)
{
    [branch]
    if (level <= 0)
    {
        return tex2Dlod(_CameraDepthTexture, float4(ray.xy, 0.0, 0.0)).r;
    }
    else
    {
        return tex2Dlod(hiZTexture, float4(ray.xy, 0.0, level - 1)).r;
    }
}

int2 GetCellCountInCurrentLevel(int mipLevel)
{
    uint2 size = ScreenResolution;
    size = size >> mipLevel;
    
#if defined(HALF_RESOLUTION_TRACING)
    if (mipLevel == 0)
        size.x /= 2;
#endif
    
    return size;
}

float FindDistanceToNextCell(float3 rayPosition, float3 viewDirection, int2 cellCountInCurrentLevel)
{
    float2 cellSize = 1.0 / cellCountInCurrentLevel;

    float2 currentCellStartUV = floor(rayPosition.xy * cellCountInCurrentLevel) * cellSize;
    float2 currentCellEndUV = currentCellStartUV + cellSize;

    // TODO: This can be factored out to the start of the loop since viewDirection doesn't change
    float closestXEdge = viewDirection.x > 0.0 ? currentCellEndUV.x : currentCellStartUV.x;
    float closestYEdge = viewDirection.y > 0.0 ? currentCellEndUV.y : currentCellStartUV.y;

    float2 solutions = float2((closestXEdge - rayPosition.x) / viewDirection.x,
                                          (closestYEdge - rayPosition.y) / viewDirection.y);
    
#if defined(HALF_RESOLUTION_TRACING)
    float2 mip0cellSize = 0.5 / uint2(uint(ScreenResolution.x) / 2, ScreenResolution.y);
#else
    float2 mip0cellSize = 0.5 / ScreenResolution;
#endif
    
    // Pick the closest edge, add a small offset to it to really move inside the cell and avoid precision issues
    float result = solutions.x < solutions.y ? solutions.x + mip0cellSize.x : solutions.y + mip0cellSize.y;

    return result;
}

#define START_LEVEL 1
#define EXIT_LEVEL 0
            
#define HIERARCHICAL_ITERATIONS 128

// All positions and directions in textureSpace (clipSpace but 0-1 xy)
bool FindHierarchicalRayIntersection(float3 startPosition, float3 viewDirection, out float3 rayPosition, out uint iterationCount)
{
    float distanceToFirstCell = FindDistanceToNextCell(startPosition, viewDirection, GetCellCountInCurrentLevel(0));
    rayPosition = startPosition + viewDirection * distanceToFirstCell * 2; // offset start pos to avoid self intersections;

    float invViewDirectionZ = 1.0 / viewDirection.z;

    int currentMipLevel = START_LEVEL;
    iterationCount = 0;

    float minDepth = 0.0;
          
    while (currentMipLevel >= EXIT_LEVEL && iterationCount < HIERARCHICAL_ITERATIONS)
    {
        minDepth = GetMinDepth(rayPosition.xy, currentMipLevel);
                    
        float distanceToNextCell = FindDistanceToNextCell(rayPosition, viewDirection, GetCellCountInCurrentLevel(currentMipLevel));

        float distanceToMoveForward = 0.0;

        // If we are not behind the depth plane, go to the closest positive intersection
        // (either cell edge or depth intersection) and finetune step size (mipLevel) as needed
#if defined(UNITY_REVERSED_Z)
        if (rayPosition.z > minDepth)
#else
        if (rayPosition.z < minDepth)
#endif
        {
            float distanceToMinDepthPlane = (minDepth - rayPosition.z) * invViewDirectionZ; // Can be negative meaning the intersect is behind us

            if (distanceToNextCell < distanceToMinDepthPlane || distanceToMinDepthPlane < 0.0)
            {
                distanceToMoveForward = distanceToNextCell;
                currentMipLevel = min(currentMipLevel + 1, hiZMipLevelCount);
            }
            else
            {
                distanceToMoveForward = distanceToMinDepthPlane;
                currentMipLevel--;
            }
        }
        else
        {
            float worldRayCameraDistance = LinearEyeDepth(rayPosition.z);
            float worldPlaneCameraDistance = LinearEyeDepth(minDepth);
                        
            float worldRayPlaneDistance = worldRayCameraDistance - worldPlaneCameraDistance;
            
            float thickness = max(1.0, 0.01 * worldRayCameraDistance);
            
            // We are behind the depth plane, keep marching behind the surface if we are beyond the max thickness
            // But only at mip 0 so we don't skip the actual intersect, otherwise finetune the intersect
            if (currentMipLevel == EXIT_LEVEL && worldRayPlaneDistance > thickness)
            {
                // If we are beyond the max thickness, we have no choice but to take linear steps
                // in this case take larger steps to avoid wasting all the steps here
                distanceToMoveForward = 4 * distanceToNextCell;
            }
            else
            {
                currentMipLevel--;
            }
        }

        if (distanceToMoveForward > 0.0)
        {
            rayPosition += viewDirection * distanceToMoveForward;

            // Exit it if off screen, but not beyond the far clip plane as that can count count as a hit
#if defined(UNITY_REVERSED_Z)
            if (any(rayPosition.xy >= 1.0.xx) || any(rayPosition.xy <= 0.0.xx) || rayPosition.z >= 1.0)
#else
            if (any(rayPosition.xy >= 1.0.xx) || any(rayPosition.xy <= 0.0.xx) || rayPosition.z <= 0.0)
#endif
            {
                return false;
            }
        }

        iterationCount++;
    }

    // If beyond the far clip plane but there's something in the depth buffer, most likely we
    // are tracing behind a thin occluder which shouldn't count as an intersect
#if defined(UNITY_REVERSED_Z)
    if (rayPosition.z <= 0.0 && minDepth != 0.0)
#else
    if (rayPosition.z >= 1.0 && minDepth != 1.0)
#endif
    {
        return false;
    }
    
#if !defined(REFLECT_SKY)
    if (minDepth == 0.0)
        return false;
#endif
    
    if (currentMipLevel < EXIT_LEVEL)
    {
        return true;
    }

    return false;
}

float ApplyEdgeFade(float2 uv)
{
    float aspectRatio = (float) ScreenResolution.y / ScreenResolution.x;

    float2 distanceToEdge = uv > 0.5.xx ? 1.0 - uv : uv;
    distanceToEdge.y *= aspectRatio;
    distanceToEdge = saturate(distanceToEdge / 0.04);

    return distanceToEdge.x * distanceToEdge.y;
}

float2 GetFullResUVFromHalfResUV(float2 uv)
{
    uint2 currentPixel = uv * uint2(uint(ScreenResolution.x) / 2, ScreenResolution.y);
    currentPixel.x *= 2;
    uv = (currentPixel + 0.5.xx) / ScreenResolution;
    
    return uv;
}

float2 GetHalfResUVFromFullResUV(float2 uv, out float2 texelSize)
{
    uint2 halfResScreenResolution = uint2(uint(ScreenResolution.x) / 2, ScreenResolution.y);
    texelSize = 1.0 / halfResScreenResolution;

    uint2 currentPixel = uv * ScreenResolution;
    currentPixel.x /= 2;
    uv = (currentPixel + 0.5.xx) / halfResScreenResolution;
    
    return uv;
}

float3 getPreciseWorldPosFromDepth(float2 uv, float zdepth)
{
    float depth = Linear01Depth(zdepth);

#if defined(UNITY_REVERSED_Z)
    zdepth = 1 - zdepth;
#endif

    float4 clipPos = float4(uv, zdepth, 1.0);
    clipPos.xyz = 2.0f * clipPos.xyz - 1.0f;

    float4 camPos = mul(unity_CameraInvProjection, clipPos);
    camPos.xyz /= camPos.w;

    float3 rayDirection = normalize(camPos.xyz);

    float3 cameraForwardDir = float3(0.0, 0.0, -1.0);
    float aa = dot(rayDirection, cameraForwardDir);

    camPos.xyz = rayDirection * depth / aa * _ProjectionParams.z;
    camPos.z = -camPos.z;

    float4 worldPos = mul(unity_CameraToWorld, float4(camPos.xyz, 1.0));
    return (worldPos.xyz / worldPos.w);
}

float4 ReadSSRResult(float2 uv, float3 worldNormal, sampler2D ssrTexture, sampler2D normalsTexture)
{
#if defined(HALF_RESOLUTION_TRACING)
    float2 halfResTexelSize;
    float2 halfResUV = GetHalfResUVFromFullResUV(uv, halfResTexelSize);

    float2 ssrUV = halfResUV;

    uint2 pixelCoords = uv * ScreenResolution;
    bool pixelIsEven = pixelCoords.x % 2u == 0u;

    if (!pixelIsEven)
    {
        // Check how close are the two normals to each other, if close enough interpolate their SSR, else use the closest
        float2 halfUV0 = halfResUV;
        float2 halfUV1 = halfResUV + float2(halfResTexelSize.x, 0);

        float2 fullUV0 = GetFullResUVFromHalfResUV(halfUV0);
        float2 fullUV1 = GetFullResUVFromHalfResUV(halfUV1);

        float3 normal0 = normalize(tex2Dlod(normalsTexture, float4(fullUV0, 0.0, 0.0)).rgb * 2.0 - 1.0.xxx);
        float3 normal1 = normalize(tex2Dlod(normalsTexture, float4(fullUV1, 0.0, 0.0)).rgb * 2.0 - 1.0.xxx);

        if (dot(normal0, normal1) > 0.99)
        {
            ssrUV =  halfResUV + 0.5 * float2(halfResTexelSize.x, 0);
        }
        else if (dot(normal0, worldNormal) > dot(normal1, worldNormal))
        {
            ssrUV = halfUV0;
        }
        else
        {
            ssrUV = halfUV1;
        }
    }

    return tex2Dlod(ssrTexture, float4(ssrUV, 0.0, 0.0));
#else
    return tex2Dlod(ssrTexture, float4(uv, 0.0, 0.0));
#endif 
}