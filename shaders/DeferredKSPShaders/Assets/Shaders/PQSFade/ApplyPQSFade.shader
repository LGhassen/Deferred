Shader "Deferred/ApplyPQSFade"
{
    SubShader
    {
        // No culling or depth
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            // Only affect fragments with the PQS stencil
            Stencil
            {
                Ref 1
                ReadMask 1
                Comp Equal
                Pass Keep
            }

            Blend SrcAlpha OneMinusSrcAlpha

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            sampler2D backgroundCopyRT;
            float _PlanetOpacity;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                return float4(tex2Dlod(backgroundCopyRT, float4(i.uv, 0.0, 0.0)).rgb, _PlanetOpacity);
            }
            ENDCG
        }
    }
}
