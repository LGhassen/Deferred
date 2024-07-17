Shader "Terrain/PQS/PQS Triplanar Zoom Rotation Texture Array - 1 Blend"
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

        _albedoBrightness("Albedo Brightness", Float) = 1.0

        _PlanetOpacity("Opacity of transition to scaled", Float) = 1.0
        _specularColor("Specular Color", Color) = (0.2, 0.2, 0.2, 0.2)

        // Non-atlas Properties
        _lowTex("Low Color Texture", 2D) = "white" {}
        _midTex("Mid Color Texture", 2D) = "white" {}
        _highTex("High Color Texture", 2D) = "white" {}

        _lowBumpMap ("Low Normal Map", 2D) = "bump" {}
        _midBumpMap("Mid Normal Map", 2D) = "bump" {}
        _highBumpMap ("High Normal Map", 2D) = "bump" {}

        _lowTiling("Low Tiling", Float) = 100000.0
        _midTiling("Mid Tiling", Float) = 100000.0
        _highTiling("High Tiling", Float) = 100000.0
        
        _lowBumpTiling ("Low Bump Tiling", Float) = 100000.0
        _midBumpTiling("Mid Bump Tiling", Float) = 100000.0
        _highBumpTiling ("High Bump Tiling", Float) = 100000.0

        // Tiling properties for legacy non-zoomable terrain shaders that blend between near/far
        _lowNearTiling("Low Near Tiling", Float) = 1000.0
        _lowMultiFactor("Low Far Tiling", Float) = 10.0
        _lowBumpNearTiling ("Low Bump Near Tiling", Float) = 1.0
        _lowBumpFarTiling ("Low Bump Far Tiling", Float) = 1.0

        _midNearTiling("Mid Near Tiling", Float) = 1000.0
        _midMultiFactor("Mid Far Tiling", Float) = 10.0
        _midBumpNearTiling("Mid Bump Near Tiling", Float) = 1.0
        _midBumpFarTiling ("Mid Bump Far Tiling", Float) = 1.0

        _highNearTiling("High Near Tiling", Float) = 1000.0
        _highMultiFactor("High Far Tiling", Float) = 10.0
        _highBumpNearTiling ("High Bump Near Tiling", Float) = 1.0
        _highBumpFarTiling ("High Bump Far Tiling", Float) = 1.0
        
        // These control the distance at which we transition from near tiling to farTiling
        _groundTexStart("Far tiling transition start", Float) = 2000.0
        _groundTexEnd("Far tiling transition end", Float) = 10000.0

        // These heights seem to be 0-1, maybe assuming zero is the deepest point underwater and 1.0 is the highest mountain
        _lowStart("Low Start Relative Height", Float) = 0.0
        _lowEnd("Low End Relative Height", Float) = 0.3
        _highStart("High Start Relative Height", Float) = 0.8
        _highEnd("High End Relative Height", Float) = 1.0

        _tintColor("Vertex color tint", Color) = (1.0, 1.0, 1.0, 0.0)
        _contrast("Original vertex color strength", Float) = 1.0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }

        Stencil
        {
            Ref 2
            Comp Always
            Pass Replace
        }  

        CGPROGRAM

        #pragma multi_compile STEEP_TEXTURING_ON STEEP_TEXTURING_OFF
        #define ATLAS_TEXTUREARRAY_ON
        #define ATLAS_TEXTURE_COUNT 1

        #include "./TerrainReplacementShader.cginc"
        #pragma surface DeferredTerrainReplacementShader Standard vertex:TerrainReplacementVertexShader
        #pragma target 4.0

        ENDCG
    }
    FallBack "Standard"
}