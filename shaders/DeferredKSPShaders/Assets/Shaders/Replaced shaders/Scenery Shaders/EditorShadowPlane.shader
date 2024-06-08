// The editor scenes render on two separate cameras, the building/propo meshes render first
// then the craft and parts render second without clearing the depth buffer in between.
// This means that when the parts render there is no floor mesh to the VAB/SPH to cast shadows on
// This shader only exists to darken the background to display a shadow
// This shader has to use forward rendering which will make it render after deferred lighting anyway
Shader "KSP/Scenery/Invisible Shadow Receiver"
{
    SubShader 
    { 
        Tags { "RenderType" = "Transparent" "Queue" = "Geometry" }

        Pass
        {
            Blend DstColor Zero // Multiplicative

            Zwrite Off
            ZTest On
            
            Tags {"LightMode" = "ForwardBase"}

            CGPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "AutoLight.cginc"

            #pragma multi_compile_fwdbase
 
            struct v2f
            { 
                float4 pos : SV_POSITION;
                LIGHTING_COORDS(1, 2)
            };
 
            v2f vert (appdata_base v)
            {
                v2f o;

                o.pos = UnityObjectToClipPos(v.vertex);

                TRANSFER_VERTEX_TO_FRAGMENT(o);

                return o;
            }

            float4 frag (v2f i) : COLOR
            {
                float shadow = 0.5 + 0.5 * LIGHT_ATTENUATION(i);
                return shadow.xxxx;
            }

            ENDCG
        }
    }
}