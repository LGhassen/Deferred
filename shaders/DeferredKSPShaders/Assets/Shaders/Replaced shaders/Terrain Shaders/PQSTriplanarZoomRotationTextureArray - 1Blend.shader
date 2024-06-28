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

        _albedoBrightness("Albedo Brightness", Float) = 2.0

        _PlanetOpacity("Opacity of transition to scaled", Float) = 1.0
        _specularColor("Specular Color", Color) = (0.2, 0.2, 0.2, 0.2)
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