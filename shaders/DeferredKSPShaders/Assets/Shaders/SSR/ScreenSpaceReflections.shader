Shader "Deferred/ScreenSpaceReflections"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        // No culling or depth
        Cull Off
        ZWrite Off
        ZTest Always

        Pass    // Composes the final lighting, reading from the SSR buffer and the reflection probe
        {
            Blend One One // Additive

            CGPROGRAM

            #pragma vertex vert

            #include "UnityCG.cginc"

            #pragma target 3.0
            #pragma fragment frag

            #pragma multi_compile ___ HALF_RESOLUTION_TRACING

            sampler2D ssrOutput;

            #include "UnityCG.cginc"
            #include "UnityDeferredLibrary.cginc"
            #include "UnityStandardUtils.cginc"
            #include "UnityGBuffer.cginc"
            #include "UnityStandardBRDF.cginc"
            #include "UnityPBSLighting.cginc"
            #include "HiZTracing.cginc"

            sampler2D _CameraGBufferTexture0;
            sampler2D _CameraGBufferTexture1; // alpha = smoothness
            sampler2D _CameraGBufferTexture2; // normal = rgb

            sampler2D oceanGbufferDepth;
            sampler2D oceanGbufferFresnel;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert (appdata v)
            {
                v2f o;
				o.vertex = float4(v.vertex.xy * 2.0, 0.0, 1.0);
                o.uv = ComputeScreenPos(o.vertex);

                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                i.uv /= i.uv.w;

                float zdepth = tex2Dlod(_CameraDepthTexture, i.uv);

                if (zdepth == 0.0)
                    return 0.0.xxxx;

                float smoothness = tex2Dlod(_CameraGBufferTexture1, i.uv).a;
                float3 worldNormal = tex2Dlod(_CameraGBufferTexture2, i.uv).rgb * 2.0 - 1.0.xxx;
                float3 worldPos = getPreciseWorldPosFromDepth(i.uv.xy, zdepth);

                float3 viewVector = normalize(worldPos - _WorldSpaceCameraPos);

                half4 gbuffer0 = tex2D (_CameraGBufferTexture0, i.uv);
                half4 gbuffer1 = tex2D (_CameraGBufferTexture1, i.uv);
                half4 gbuffer2 = tex2D (_CameraGBufferTexture2, i.uv);
                UnityStandardData data = UnityStandardDataFromGbuffer(gbuffer0, gbuffer1, gbuffer2);

                float3 eyeVec = normalize(worldPos - _WorldSpaceCameraPos);
                half oneMinusReflectivity = 1 - SpecularStrength(data.specularColor);

                UnityLight light;
                light.color = half3(0, 0, 0);
                light.dir = half3(0, 1, 0);

                UnityIndirect ind;
                ind.diffuse = 0;
                ind.specular = 0;

                float blendDistance = unity_SpecCube1_ProbePosition.w; // will be set to blend distance for this probe

                // Unused member don't need to be initialized
                UnityGIInput d;
                d.worldPos = worldPos;
                d.worldViewDir = -eyeVec;
                d.probeHDR[0] = unity_SpecCube0_HDR;
                d.boxMin[0].w = 1; // 1 in .w allow to disable blending in UnityGI_IndirectSpecular call since it doesn't work in Deferred
        
                #ifdef UNITY_SPECCUBE_BOX_PROJECTION
                d.probePosition[0]  = unity_SpecCube0_ProbePosition;
                d.boxMin[0].xyz     = unity_SpecCube0_BoxMin - float4(blendDistance,blendDistance,blendDistance,0);
                d.boxMax[0].xyz     = unity_SpecCube0_BoxMax + float4(blendDistance,blendDistance,blendDistance,0);
                #endif

                Unity_GlossyEnvironmentData g = UnityGlossyEnvironmentSetup(data.smoothness, d.worldViewDir, data.normalWorld, data.specularColor);

                ind.specular = UnityGI_IndirectSpecular(d, data.occlusion, g);

                //float bayerDither = BayerDither4x4(i.uv.xy);
                //ind.specular = SpecularBrdfApprox(worldPos, worldNormal, _WorldSpaceCameraPos, 1.0 - smoothness, bayerDither); // this appears to be distorted, idk thought it worked correctly
                //ind.specular = FakeSpecularBrdfApprox(worldPos, eyeVec, worldNormal, 1.0 - data.smoothness, bayerDither);

                /*
                if (i.uv.x > 0.5)
                {
                    ind.specular = ImportanceSampledReflectionProbeSpecular(eyeVec, worldNormal, data, 1024);
                }
                */

                // read the ocean depth and fresnel and decide if we use the ocean or not for tracing
                
                float oceanZDepth = tex2Dlod(oceanGbufferDepth, i.uv);
                float oceanFresnel = tex2Dlod(oceanGbufferFresnel, i.uv);
                
                bool ssrUsedOcean = false;

                // read the ocean stuff and decide if we use the ocean or not for tracing
                if (oceanZDepth > 0.0 && oceanFresnel > 0.01) //TODO: if reversed_z
                {
                    ssrUsedOcean = true;
                }
                

                //bool ssrUsedOcean = false;

                float4 ssr = ReadSSRResult(i.uv.xy, worldNormal, ssrOutput, _CameraGBufferTexture2);

                ssr.a = ssr.a * saturate((smoothness - 0.4) / 0.2); // Smoothly fade out SSR when approaching the cutoff roughness

                ind.specular = lerp(ind.specular, ssr.rgb, ssr.a * !ssrUsedOcean);

                half3 rgb = UNITY_BRDF_PBS (data.diffuseColor, data.specularColor, oneMinusReflectivity, data.smoothness, data.normalWorld, -eyeVec, light, ind).rgb;

                return half4(rgb, 1.0);
            }

            ENDCG
        }

        Pass // Pass 1, tracing pass, trace at half-res or full-res and output hit info
        {
            CGPROGRAM
            #pragma target 3.0

            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile ___ HALF_RESOLUTION_TRACING
            #define REFLECT_SKY

            sampler2D _CameraDepthTexture;
            sampler2D _CameraGBufferTexture1; // alpha = smoothness
            sampler2D _CameraGBufferTexture2; // rgb = normal

            #include "UnityCG.cginc"
            #include "UnityPBSLighting.cginc"
            #include "HiZTracing.cginc"
            #include "ConeUtils.cginc"

            Texture2D SSRScreenColor;
            SamplerState sampler_trilinear_clamp;
            SamplerState sampler_SSRScreenColor;

            float4x4 textureSpaceProjectionMatrix;

            sampler2D oceanGbufferDepth;
            sampler2D oceanGbufferNormalsAndSigma;
            sampler2D oceanGbufferFresnel;

            float2 _VarianceMax;

            float3 SSRPlanetPosition;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float4 uv : TEXCOORD0;
            };

            v2f vert (appdata v)
            {
                v2f o;
				o.vertex = float4(v.vertex.xy * 2.0, 0.0, 1.0);
                o.uv = ComputeScreenPos(o.vertex);

                return o;
            }

            struct fout
			{
                float4 colorAndConfidence: COLOR0;
                float hitDistance: COLOR1;
			};

            void GetTextureSpacePosAndReflectionDir(float3 worldPos, float3 worldReflectionVector,
                                                    out float4 textureSpacePos, out float3 textureSpaceReflectionDirection)
            {
                // Could simplify these and get the camera Pos directly
                float3 cameraSpacePos = mul(UNITY_MATRIX_V, float4(worldPos, 1.0));
                float3 cameraSpacePos2 = mul(UNITY_MATRIX_V, float4(worldPos + worldReflectionVector * 10.0, 1.0));

                
                textureSpacePos = mul(textureSpaceProjectionMatrix, float4(cameraSpacePos, 1.0));
                textureSpacePos /= textureSpacePos.w;

                float4 textureSpacePos2 = mul(textureSpaceProjectionMatrix, float4(cameraSpacePos2, 1.0));
                textureSpacePos2 /= textureSpacePos2.w;
                
                textureSpaceReflectionDirection = normalize(textureSpacePos2 - textureSpacePos);
            }

            float GetConfidence(bool intersectionFound, float2 hitPos, float2 textureSpacePos, float smoothness)
            {
                float confidence = intersectionFound * ApplyEdgeFade(hitPos.xy);

                uint2 pixelsTraveled = abs(hitPos.xy - textureSpacePos.xy) * SSRScreenResolution;
                
                // Prevent self-intersections
                confidence = pixelsTraveled.x < 1 && pixelsTraveled.y < 1 ? 0.0 : confidence;

                return confidence;
            }

            
            
            // TODO: rewrite code to be a bit different and link to scatterer source

            #define MAX_POSITION_FROM_DEPTH_BINARY_SEARCH_ITERATIONS 15
            #define POSITION_FROM_DEPTH_BINARY_SEARCH_FLOAT_EPSILON 1e-11

            float3 GetAccurateFragmentPosition(float2 uv, float zdepth)
            {
                float3 inaccuratePosition = getPreciseWorldPosFromDepth(uv, zdepth);

                float3 worldViewDir = inaccuratePosition - _WorldSpaceCameraPos;
                float inaccurateDistance = length(worldViewDir);
                worldViewDir /= inaccurateDistance;

                int iteration = 0;

                float maxSearchDistance = inaccurateDistance * 2.0;
                float minSearchDistance = 0.0;

                float mid = 0; float depth = -10.0;

                while ((iteration < MAX_POSITION_FROM_DEPTH_BINARY_SEARCH_ITERATIONS) && (abs(depth - zdepth) > POSITION_FROM_DEPTH_BINARY_SEARCH_FLOAT_EPSILON))
                {
                    mid = 0.5 * (maxSearchDistance + minSearchDistance);

                    float3 worldPos = _WorldSpaceCameraPos + worldViewDir * mid;

                    float4 clipPos = mul(UNITY_MATRIX_VP, float4(worldPos, 1.0));
                    depth = clipPos.z / clipPos.w;

            #if defined(UNITY_REVERSED_Z)
                    maxSearchDistance = (depth < zdepth) ? mid : maxSearchDistance;
                    minSearchDistance = (depth > zdepth) ? mid : minSearchDistance;
            #else
                    maxSearchDistance = (depth > zdepth) ? mid : maxSearchDistance;
                    minSearchDistance = (depth < zdepth) ? mid : minSearchDistance;
            #endif

                    iteration++;
                }

                return _WorldSpaceCameraPos + worldViewDir * mid;
            }

            fout frag (v2f i)
            {
                i.uv /= i.uv.w;

#if defined(HALF_RESOLUTION_TRACING)
                i.uv.xy = GetFullResUVFromHalfResUV(i.uv.xy);
#endif

                float zdepth = tex2Dlod(_CameraDepthTexture, i.uv);
                float smoothness = tex2Dlod(_CameraGBufferTexture1, i.uv).a;
                
                float oceanZDepth = tex2Dlod(oceanGbufferDepth, i.uv);
                float oceanFresnel = tex2Dlod(oceanGbufferFresnel, i.uv);

                float4 oceanNormalsAndSigma = tex2Dlod(oceanGbufferNormalsAndSigma, i.uv);

                float3 oceanWorldNormals = 0.0;

                // Unpack world normals from the gbuffer
                oceanWorldNormals.xy = oceanNormalsAndSigma.xy * 2.0 - 1.0.xx;

                // Reconstruct the z component of the world normals
                oceanWorldNormals.z = sqrt(1.0 - saturate(dot(oceanWorldNormals.xy, oceanWorldNormals.xy)));
    
                // Use the sign which we stored in the 2-bit alpha
                oceanWorldNormals.z = oceanNormalsAndSigma.w > 0.0 ? oceanWorldNormals.z : -oceanWorldNormals.z;

                float oceanSigmaSq = oceanNormalsAndSigma.z * _VarianceMax.x;

                //float oceanSmoothness = sqrt(oceanSigmaSq) * 4.5 / 6.0;
                // the above didn't really work lel, might have been lower than 0.4
                //float oceanSmoothness = 0.95;

                //float oceanSmoothness = 1.0 - saturate(tan(sqrt(oceanSigmaSq)));

                //float oceanSmoothness = 1.0 - saturate(sqrt(sqrt(oceanSigmaSq) * 4.5 / 6.0));  // looks good tbh
                float oceanSmoothness = 1.0 - saturate(sqrt(sqrt(oceanSigmaSq) * 3.0 / 6.0));
                //float oceanSmoothness = 1.0 - saturate(sqrt(0.7 * oceanSigmaSq));

                //float oceanSmoothness = 1.0 - saturate(sqrt(0.5 * oceanSigmaSq));
                //float oceanSmoothness = 1.0 - saturate(sqrt(sqrt(oceanSigmaSq) * 0.1));

                //float oceanSmoothness = 0.95;

                bool useOcean = false;

                // read the ocean stuff and decide if we use the ocean or not for tracing
                if (oceanZDepth > 0.0 && oceanFresnel > 0.01) //TODO: if reversed_z
                {
                    useOcean = true;
                    zdepth = oceanZDepth;
                    smoothness = oceanSmoothness;
                }
                

#if defined(UNITY_REVERSED_Z)
                if (zdepth == 0.0 || smoothness < 0.4)
#else
                if (zdepth == 1.0 || smoothness < 0.4)
#endif
                {
                    fout output;
                    UNITY_INITIALIZE_OUTPUT(fout, output);
                    return output;
                }

                float3 worldNormal = tex2Dlod(_CameraGBufferTexture2, i.uv).rgb * 2.0 - 1.0.xxx;



                //float3 worldPos = getPreciseWorldPosFromDepth(i.uv.xy, zdepth);

                float3 worldPos = GetAccurateFragmentPosition(i.uv.xy, zdepth);

                float3 viewVector = normalize(worldPos - _WorldSpaceCameraPos);


                
                if (useOcean)
                {
                    worldNormal = oceanWorldNormals;
                }

                float3 reflectionVector = reflect(viewVector, worldNormal);

                // Stop ocean reflection vectors from going undrwater
                if (useOcean)
                {
                    // get normal at reflection position, we need the current planet position
                    float3 planetNormalAtPosition = normalize(worldPos - SSRPlanetPosition);

                    // if the component along the normal invert it
                    float zComponent = dot(reflectionVector, planetNormalAtPosition);

                    if (zComponent < 0.0)
                    {
                        reflectionVector -= 2 * zComponent * planetNormalAtPosition;
                        reflectionVector = normalize(reflectionVector);
                    }
                }

                float4 textureSpacePos;
                float3 textureSpaceReflectionDirection;
                GetTextureSpacePosAndReflectionDir(worldPos, reflectionVector, textureSpacePos, textureSpaceReflectionDirection);

                uint iterations;
                float3 hitPos;
                bool intersectionFound = FindHierarchicalRayIntersection(textureSpacePos.xyz, textureSpaceReflectionDirection, hitPos, iterations);

                float confidence = GetConfidence(intersectionFound, hitPos.xy, textureSpacePos.xy, smoothness);

                float dotVN = saturate(dot(-viewVector, worldNormal));
                float hitDistance = distance(hitPos.xy, textureSpacePos.xy);

                float2 ddx, ddy;
                float ssrMipLevel = GetConeMipLevelAndAnisotropicDerivatives(hitDistance, textureSpaceReflectionDirection, smoothness, dotVN, ddx, ddy);

                float3 color;

                [branch]
                if (confidence > 0.0)
                {
                    color = SSRScreenColor.SampleGrad(sampler_SSRScreenColor, hitPos, ddx, ddy);
                }
                else // use the reflection probe color anyway because it helps when we use it for blurring the final result
                {
                    UnityGIInput d = (UnityGIInput)0;
                    d.worldPos = worldPos;
                    d.worldViewDir = -viewVector;
                    d.probeHDR[0] = unity_SpecCube0_HDR;
                    d.boxMin[0].w = 1;
                    Unity_GlossyEnvironmentData g = UnityGlossyEnvironmentSetup(smoothness, d.worldViewDir, worldNormal, 1.0.xxx);

                    color = UnityGI_IndirectSpecular(d, 1.0, g);

                    hitDistance = 1.0;
                }

                fout output;
                output.colorAndConfidence = float4(color, confidence);
                output.hitDistance = hitDistance;

                return output;
            }

            ENDCG
        }

        Pass  // Pass 2 reproject previous frame color (including shading + transparencies) using motion vectors and depth
        {
            CGPROGRAM

            #pragma vertex vert

            #include "UnityCG.cginc"

            #pragma target 3.0
            #pragma fragment frag

            #include "UnityCG.cginc"

            sampler2D _CameraMotionVectorsTexture;
            sampler2D _CameraDepthTexture;
            
            sampler2D lastFrameColor;
            sampler2D currentFrameColor;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert (appdata v)
            {
                v2f o;
				o.vertex = float4(v.vertex.xy * 2.0, 0.0, 1.0);
                o.uv = ComputeScreenPos(o.vertex);

                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                i.uv /= i.uv.w;

                float2 motion = tex2Dlod(_CameraMotionVectorsTexture, float4(i.uv.xy, 0.0, 0.0));
                
                float2 uv = i.uv.xy - motion;

                
                float zdepth = tex2Dlod(_CameraDepthTexture, i.uv);

                /*
#if defined(UNITY_REVERSED_Z)
                if (zdepth == 0.0)
#else
                if (zdepth == 1.0)
#endif
                {
                    // Sky and clouds don't reproject well because of frequent occlusions/disocclusions
                    // by other objects. At this point they are already fully rendered, unlike other transparencies,
                    // no need to reproject them and the game doesn't have a lot more particles/transparencies
                    return tex2Dlod(currentFrameColor, float4(i.uv.xy, 0.0, 0.0));
                }
                */

                // At the moment just doing a "dumb" reprojection without any kind of disocclusion
                // checks or neighborhood clipping and didn't notice any issues, will adjust as needed
                // using motion and the current frame (lacking reflections and transparencies)
                return tex2Dlod(lastFrameColor, float4(uv, 0.0, 0.0));
            }

            ENDCG
        }
    }
}