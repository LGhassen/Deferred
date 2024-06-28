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
			o.Albedo = tex2D(_MainTex, IN.uv_MainTex);
			o.Smoothness = 0.5;
			o.Normal = float3(0.0,0.0,1.0);
			o.Metallic = 0.0;
			o.Alpha = 1.0;
		}

        ENDCG
    }
    Fallback "Standard"
}