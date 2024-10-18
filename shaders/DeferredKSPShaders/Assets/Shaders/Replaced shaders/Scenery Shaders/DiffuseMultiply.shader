Shader "KSP/Scenery/Diffuse Multiply"
{
    Properties 
    {
        _MainTex("Color Map", 2D) = "gray" {}
        _Color ("Part Color", Color) = (1.0, 1.0, 1.0, 1.0)
    }
    SubShader 
    {
        Tags { "RenderType"="Opaque" }

        Stencil
        {
            Ref 3
            Comp Always
            Pass Replace
        }  

        CGPROGRAM
        #include "../ReplacementShader.cginc"
        #pragma surface surf Standard
        #pragma target 3.0

        // This shader seems to ignore alpha channel smoothness and _Color property, not sure what's the point
        void surf (Input IN, inout SurfaceOutputStandard o)
        {
            float4 _TarmacColor = float4(0.89.xxx, 1.0); // hack to equalize mismatching color settings in the KSC

            float4 groundColor = tex2D(_MainTex, IN.uv_MainTex) * _TarmacColor;

            o.Albedo = groundColor.rgb;
            o.Smoothness = 0.25 * sqrt(max(groundColor.a, 0.0000001)); // match shading in DiffuseKSCGroundSpecular
            o.Normal = float3(0.0,0.0,1.0);
            o.Metallic = 0.0;
            o.Alpha = 1.0;

#if UNITY_PASS_DEFERRED
            // In deferred rendering do not use the flat ambient because Deferred adds its own ambient as a composite of flat ambient and probe
            // Also do not use #pragma skip_variants LIGHTPROBE_SH because it impacts lighting in forward and some elements can still render in
            // forward e.g through the VAB scene doors
            unity_SHAr = 0.0.xxxx;
            unity_SHAg = 0.0.xxxx;
            unity_SHAb = 0.0.xxxx;
#endif
        }

        ENDCG
    }
    Fallback "Standard"
}