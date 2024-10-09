Shader "Deferred/GenerateHiZ"
{
	SubShader
	{
		Pass
		{
			ZTest Always
			Cull Off
			ZWrite Off

			CGPROGRAM

			#pragma vertex vert
			#pragma fragment frag

			#include "UnityCG.cginc"

			struct v2f
			{
				float4 pos : SV_POSITION;
				float2 uv : TEXCOORD0;
			};

			Texture2D PreviousHiZTexture;

			float2 hiZPreviousMipLevelDimensions, hiZCurrentMipLevelDimensions;
			int hiZPreviousMipLevel;

			int previousTextureIsFullResDepthBuffer;

			v2f vert( appdata_img v )
			{
				v2f o = (v2f)0;
				o.pos = float4(v.vertex.xy * 2.0, 0.0, 1.0);
				o.uv = ComputeScreenPos(o.pos);

				return o;
			}

			float2 frag(v2f input) : SV_Target
			{
				float2 inverseRenderDimensions = 1.0.xx / max(1.0.xx, hiZCurrentMipLevelDimensions);

				int2 startCoords = (input.uv - 0.5f * inverseRenderDimensions) * hiZPreviousMipLevelDimensions;
				int2 endCoords = ceil((input.uv + 0.5f * inverseRenderDimensions) * hiZPreviousMipLevelDimensions);

				startCoords = clamp(startCoords, 0, hiZPreviousMipLevelDimensions);
				endCoords = clamp(endCoords, 0, hiZPreviousMipLevelDimensions);

				#if defined(UNITY_REVERSED_Z)
					float closestDepth = 0.0;
					float farthestDepth = 1.0;
				#else
					float closestDepth = 1.0;
					float farthestDepth = 0.0;
				#endif

				for (int y = startCoords.y; y < endCoords.y; y++)
				{
					for (int x = startCoords.x; x < endCoords.x; x++)
					{
						float2 previousDepths = PreviousHiZTexture.Load(int3(x, y, hiZPreviousMipLevel)).rg;

						if (previousTextureIsFullResDepthBuffer > 0.0)
							previousDepths.g = previousDepths.r;

						
						#if defined(UNITY_REVERSED_Z)
							closestDepth = max(closestDepth,   previousDepths.r);
							farthestDepth = min(farthestDepth, previousDepths.g);
						#else
							closestDepth = min(closestDepth,   previousDepths.r);
							farthestDepth = max(farthestDepth, previousDepths.g);
						#endif
					}
				}

				return float2(closestDepth, farthestDepth);
			}

			ENDCG
		}
	}
	Fallback off
}