Shader "Deferred/DummyForwardShader"
{
    SubShader 
    { 
        Tags { "RenderType" = "Transparent" "Queue" = "Geometry" "IgnoreProjector" = "True" }

        Pass
        {
            Zwrite Off
            ZTest Off
            
            Tags {"LightMode" = "ForwardBase"}

            CGPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "AutoLight.cginc"

            //#pragma multi_compile_fwdbase
 
            struct v2f
            { 
                float4 pos : SV_POSITION;
            };
 
            v2f vert (appdata_base v)
            {
                v2f o;

                o.pos = float4(2.0, 2.0, 2.0, 1.0); // Outside clip space, this just culls the vertex entirely

                return o;
            }

            float4 frag (v2f i) : COLOR
            {
                return 0.0.xxxx;
            }

            ENDCG
        }
    }
}