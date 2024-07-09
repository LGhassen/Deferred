Shader "Deferred/CopyGBuffer"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        // No culling or depth
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            sampler2D _CameraGBufferTexture0, _CameraGBufferTexture1, _CameraGBufferTexture2, _CameraGBufferTexture3, _CameraDepthTexture, emissionCopyRT;
            int GbufferDebugMode;

            int logarithmicLightBuffer;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            sampler2D _MainTex;


            float4x4 CameraToWorld;

            fixed4 frag (v2f i) : SV_Target
            {
                float2 uv = i.uv;

                float depth = tex2Dlod(_CameraDepthTexture, float4(uv, 0.0, 0.0));

                if (GbufferDebugMode < 7)
                {
    #if defined(SHADER_API_GLES) || defined(SHADER_API_GLES3) || defined(SHADER_API_GLCORE)
                    if (depth == 1.0)
    #else
                    if (depth == 0.0)
    #endif
                    {
                        return 0.0.xxxx;
                    }
                }

                [branch]
                if (GbufferDebugMode == 0 || GbufferDebugMode == 6)
                {
                    half4 gbuffer0 = tex2Dlod (_CameraGBufferTexture0, float4(uv, 0.0, 0.0)); // Diffuse RGB, Occlusion A
                    
                    float3 result = GbufferDebugMode == 0 ? gbuffer0.rgb : gbuffer0.aaa;
                    return float4(result, 1.0);
                }
                else if (GbufferDebugMode == 1 || GbufferDebugMode == 3)
                {
                    half4 gbuffer1 = tex2Dlod (_CameraGBufferTexture1, float4(uv, 0.0, 0.0)); // Specular RGB, Smoothness A

                    float3 result = GbufferDebugMode == 1 ? gbuffer1.rgb : gbuffer1.aaa;
                    return float4(result, 1.0);
                }
                else if (GbufferDebugMode == 2)
                {
                    return float4 (tex2Dlod(_CameraGBufferTexture2, float4(uv, 0.0, 0.0)).rgb, 1.0); // Normals
                }
                else if (GbufferDebugMode == 4)
                {
                    float3 emission = tex2Dlod(emissionCopyRT, float4(uv, 0.0, 0.0)).rgb;
                    
                    emission = logarithmicLightBuffer > 0 ? -log2(emission) : emission;
                    return float4(emission, 1.0);
                }
                else if (GbufferDebugMode == 5)
                {
                    float3 emissionAndAmbient = tex2Dlod(_CameraGBufferTexture3, float4(uv, 0.0, 0.0)).rgb;
                    float3 emission = tex2Dlod(emissionCopyRT, float4(uv, 0.0, 0.0)).rgb;
                    
                    emissionAndAmbient = logarithmicLightBuffer > 0 ? -log2(emissionAndAmbient) : emissionAndAmbient;
                    emission = logarithmicLightBuffer > 0 ? -log2(emission) : emission;

                    float3 ambient = max(emissionAndAmbient - emission, 0.0.xxx);

                    return float4(ambient, 1.0);
                }
                else
                {
                    // Reflection probe debug mode


                    #if defined(UNITY_REVERSED_Z)
	                    float4 clipPos = float4(uv, 0.0, 1.0);
                    #else
                        float4 clipPos = float4(uv, 1.0, 1.0);
                    #endif

	                clipPos.xyz = 2.0f * clipPos.xyz - 1.0f;

                    float4 camPos = mul(unity_CameraInvProjection, clipPos);
	                float4 worldPos = mul(CameraToWorld, camPos);

                    float3 worldDir = normalize(worldPos.xyz/worldPos.w - _WorldSpaceCameraPos);

                    float4 reflection = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, worldDir, 0.0);
                    reflection.rgb = DecodeHDR(reflection, unity_SpecCube0_HDR);

                    return float4(reflection.rgb, 1.0);
                }
            }
            ENDCG
        }
    }
}
