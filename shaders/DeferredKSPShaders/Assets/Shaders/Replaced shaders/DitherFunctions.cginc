// Credits to gkjohnson https://github.com/gkjohnson/unity-dithered-transparency-shader
/*
MIT License

Copyright (c) 2017 Garrett Johnson

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

#ifndef __DITHER_FUNCTIONS__
#define __DITHER_FUNCTIONS__
#include "UnityCG.cginc"

// Returns > 0 if not clipped, < 0 if clipped based
// on the dither
// For use with the "clip" function
// pos is the fragment position in screen space from [0,1]
float isDithered(float2 pos, float alpha) {
    pos *= _ScreenParams.xy;

    // Define a dither threshold matrix which can
    // be used to define how a 4x4 set of pixels
    // will be dithered
    float DITHER_THRESHOLDS[16] =
    {
        1.0 / 17.0,  9.0 / 17.0,  3.0 / 17.0, 11.0 / 17.0,
        13.0 / 17.0,  5.0 / 17.0, 15.0 / 17.0,  7.0 / 17.0,
        4.0 / 17.0, 12.0 / 17.0,  2.0 / 17.0, 10.0 / 17.0,
        16.0 / 17.0,  8.0 / 17.0, 14.0 / 17.0,  6.0 / 17.0
    };

    uint index = (uint(pos.x) % 4) * 4 + uint(pos.y) % 4;
    return alpha - DITHER_THRESHOLDS[index];
}


sampler2D _DeferredDitherBlueNoise;
float4 _DeferredDitherBlueNoise_TexelSize;

// Returns whether the pixel should be discarded based
// on the dither texture
// pos is the fragment position in screen space from [0,1]
float isDitheredTexture(float2 pos, float alpha)
{
    uint2 screenCoords = pos * _ScreenParams.xy;
    
    uint2 blueNoiseCoords = uint2(screenCoords.x % uint(_DeferredDitherBlueNoise_TexelSize.z),
                                 screenCoords.y % uint(_DeferredDitherBlueNoise_TexelSize.w));
    
    float2 blueNoiseUV = ((float2) blueNoiseCoords + 0.5.xx) / _DeferredDitherBlueNoise_TexelSize.zw;

    float texValue = tex2Dlod(_DeferredDitherBlueNoise, float4(blueNoiseUV, 0.0, 0.0)).r;
    
    // ensure that we clip if the alpha is zero by
    // subtracting a small value when alpha == 0, because
    // the clip function only clips when < 0
    return alpha - texValue - 0.0001 * (1 - ceil(alpha));
}

// Helpers that call the above functions and clip if necessary
void ditherClip(float2 pos, float alpha)
{
    [branch]
    if (alpha > 0.99)
        return;
    
    clip(isDithered(pos, alpha));
}

void ditherClipTexture(float2 pos, float alpha)
{   
    // Tighten transition to hide ugly dithering patterns as long as possible
    alpha = saturate((alpha - 0.2) / 0.6);
    
    [branch]
    if (alpha > 0.99)
        return;
    
    clip(isDitheredTexture(pos, alpha));
}
#endif