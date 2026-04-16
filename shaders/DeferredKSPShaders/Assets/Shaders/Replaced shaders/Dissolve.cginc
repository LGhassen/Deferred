#include "../NoiseSimplex.cginc"

void DissolveClip(float3 pos, float alpha)
{
    [branch]
    if (alpha > 0.99)
        return;

    float noise = snoise(pos * 2.0) * 0.5 + 0.5;
    
    alpha = saturate((alpha - 0.2) / 0.8);
    
    if (noise > alpha || alpha == 0)
        discard;
}