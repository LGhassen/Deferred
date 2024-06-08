Shader "Deferred/SubpixelMorphologicalAntialiasing"
{
	SubShader
	{
		Cull Off ZWrite Off ZTest Always


		// 0 - Edge detection (Depth mode)
		Pass
		{
			CGPROGRAM

			#pragma vertex VertEdge
			#pragma fragment FragDepthEdge
			#define SMAA_PRESET_HIGH
			#include "SMAABridge.cginc"

			ENDCG
		}

		// 1 - Edge detection (Medium, color mode)
		Pass
		{
			CGPROGRAM

			#pragma vertex VertEdge
			#pragma fragment FragEdge
			#define SMAA_PRESET_MEDIUM
			#include "SMAABridge.cginc"

			ENDCG
		}

		// 2 - Edge detection (High, color mode)
		Pass
		{
			CGPROGRAM

			#pragma vertex VertEdge
			#pragma fragment FragEdge
			#define SMAA_PRESET_HIGH
			#include "SMAABridge.cginc"

			ENDCG
		}

		// 3 - Blend Weights Calculation (Depth mode)
		Pass
		{
			CGPROGRAM

			#pragma vertex VertBlend
			#pragma fragment FragBlend
			#define SMAA_PRESET_MEDIUM
			#include "SMAABridge.cginc"

			ENDCG
		}

		// 4 - Blend Weights Calculation (Medium, color mode)
		Pass
		{
			CGPROGRAM

			#pragma vertex VertBlend
			#pragma fragment FragBlend
			#define SMAA_PRESET_MEDIUM
			#include "SMAABridge.cginc"

			ENDCG
		}

		// 5 - Blend Weights Calculation ((High, color mode)
		Pass
		{
			CGPROGRAM

			#pragma vertex VertBlend
			#pragma fragment FragBlend
			#define SMAA_PRESET_HIGH
			#include "SMAABridge.cginc"

			ENDCG
		}

		// 6 - Neighborhood Blending
		Pass
		{
			CGPROGRAM

			#pragma vertex VertNeighbor
			#pragma fragment FragNeighbor
			#include "SMAABridge.cginc"

			ENDCG
		}
	}
}
