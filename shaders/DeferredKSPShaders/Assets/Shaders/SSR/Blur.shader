Shader "Deferred/Blur"
{
    SubShader
    {
        Cull Off
        ZWrite Off
        ZTest Always

        // 0 Horizontal blurring pass, 5 taps, not combined, for reading from a previous mipLevel
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment gaussianBlurFrag

            #define HORIZONTAL_BLUR

            #include "UnityCG.cginc"
            #include "BlurShader.cginc"

            ENDCG
        }

        // 1 Vertical blurring pass, combined 5 tap weights into 3 taps
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment gaussianBlurFrag

            #define COMBINED_TAPS

            #include "UnityCG.cginc"
            #include "BlurShader.cginc"

            ENDCG
        }

        // 2 Single-pass normals-aware 3x3 blur filter, with variable stride for covering a large
        // area in multiple iterations. Essentially a normals-only implementaion of "à trous" filter
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment normalsAwareBlurFrag

            #pragma multi_compile ___ HALF_RESOLUTION_TRACING
            #pragma multi_compile ___ PRECOMBINED_NORMALS_AND_SMOOTHNESS

            #include "UnityCG.cginc"
            #include "BlurShader.cginc"

            ENDCG
        }

        // 3 Same as above but only the vertical x3 part, to use on the first iteration when
        // blurring with half resolution tracing so that vertical and horizontal are blurred evenly
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment normalsAwareBlurFrag

            #define HALF_RESOLUTION_TRACING
            #pragma multi_compile ___ PRECOMBINED_NORMALS_AND_SMOOTHNESS
            #define VERTICAL_BLUR

            #include "UnityCG.cginc"
            #include "BlurShader.cginc"

            ENDCG
        }
    }
}
