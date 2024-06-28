// A copy-paste of KSP/Emissive/Bumped Specular
Shader "KSP/Scenery/Emissive/Bumped Specular"
{
    Properties 
    {
        _MainTex("Color Map", 2D) = "gray" {}
        _BumpMap("Normal Map", 2D) = "bump" {}
        _Emissive("Emissive Map", 2D) = "white" {}
        _Shininess ("Shininess", Range (0.0, 1.0)) = 0.5
        _Color ("Part Color", Color) = (1.0, 1.0, 1.0, 1.0)
        _SpecColor ("Specular Color", Color) = (0.5, 0.5, 0.5, 1.0)
        _EmissiveColor("Emissive Color", Color) = (0.0, 0.0, 0.0, 1.0)
        [PerRendererData]_RimFalloff("Rim Falloff", Range(0.0, 10.0) ) = 0.1
        [PerRendererData]_RimColor("Rim Color", Color) = (0.0, 0.0, 0.0, 0.0)
        [PerRendererData]_TemperatureColor("Temperature Color", Color) = (0.0, 0.0, 0.0, 0.0)
        [PerRendererData]_BurnColor ("Burn Color", Color) = (1.0, 1.0, 1.0, 1.0)
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

        #define SPECULAR_ON
        #define NORMALMAP_ON
        #define EMISSIVEMAP_ON
        
        #include "../ReplacementShader.cginc"
		#pragma surface DeferredSpecularReplacementShader StandardSpecular 
        #pragma target 3.0

        ENDCG
    }
    Fallback "Standard"
}