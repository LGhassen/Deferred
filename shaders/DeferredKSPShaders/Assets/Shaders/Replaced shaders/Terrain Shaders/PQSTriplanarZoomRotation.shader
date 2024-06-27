Shader "Terrain/PQS/PQS Triplanar Zoom Rotation"
{
    Properties
    {
        _AtlasTex("Atlas Color Texture Array", 2DArray) = "white" {}
        _NormalTex("Atlas Normals Texture Array", 2DArray) = "bump" {}
        _steepTex("Cliff Color Texture", 2D) = "white" {}
        _steepBumpMap("Cliff Normals Texture", 2D) = "bump" {}

        _AtlasTiling("Atlas Texture Tiling", Float) = 100000.0

        _steepPower("Cliff Blend Power", Float) = 1.0
        _steepNearTiling("Steep Near Tiling", Float) = 1.0
        _steepTiling("Steep Far Tiling", Float) = 1.0

        _factor("Tiling increase between zoom levels", Float) = 10.0

        _albedoBrightness("Albedo Brightness", Float) = 2.0

        _PlanetOpacity("Opacity of transition to scaled", Float) = 1.0

        // Non-atlas Properties
        _lowTex("Low Color Texture", 2D) = "white" {}
        _midTex("Mid Color Texture", 2D) = "white" {}
        _highTex("High Color Texture", 2D) = "white" {}
        _midBumpMap("High Normal Map", 2D) = "bump" {}

        _lowTiling("Low Tiling", Float) = 100000.0
        _midTiling("Mid Tiling", Float) = 100000.0
        _highTiling("High Tiling", Float) = 100000.0
        
        _midBumpTiling("Mid Bump Tiling", Float) = 100000.0
        
        // These heights seem to be 0-1, maybe assuming zero is the deepest point underwater and 1.0 is the highest mountain
        _lowStart("Low Start Relative Height", Float) = 0.0
        _lowEnd("Low End Relative Height", Float) = 0.3
        _highStart("High Start Relative Height", Float) = 0.8
        _highEnd("High End Relative Height", Float) = 1.0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }

        Stencil
        {
            Ref 1
            Comp Always
            Pass Replace
        }  

        CGPROGRAM

        #pragma multi_compile STEEP_TEXTURING_ON STEEP_TEXTURING_OFF
        
        #define ATLAS_TEXTUREARRAY_OFF
        #define ATLAS_TEXTURE_COUNT 0

        #pragma multi_compile LOW_TEXTURING_ON LOW_TEXTURING_OFF
        #pragma multi_compile HIGH_TEXTURING_ON HIGH_TEXTURING_OFF

        #include "./TerrainReplacementShader.cginc"
        #pragma surface DeferredTerrainReplacementShader Standard vertex:TerrainReplacementVertexShader
        #pragma target 4.0

        ENDCG
    }
    FallBack "Standard"
}