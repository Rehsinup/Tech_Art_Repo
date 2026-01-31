Shader "Examples/BaseShader"
{
    Properties
    {
        _BaseColor("Base color", Color) = (1,1,1,1)
        _BaseTex("Base Texture", 2D) = "white" {}
        _MettalicTex("Metallic Texture", 2D) = "white" {}
        _SmoothnessTex("Smoothness Texture", 2D) = "white" {}
        _MetallicStrength("Metallic Strength", Float) = 0.5
        _SmoothnessStrength("Smoothness", Float) = 0.5
        _NormalTex("Normal Texture", 2D) = "white" {}
        _NormalStrength("Normal Strength", Float) = 0.5
        [Toggle(USE_EMISSION_ON)] _EmissionOn("USE_EMISSION_ON", Float) = 0
        [HDR] _EmissionColor("Emission Color", Color) = (0,0,0,1)
        _EmissionTex("Emission Texture", 2D) = "white" {}
        _AOtex("Ambient Occlusion Texture", 2D) = "white" {}
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Tags{
                "LightMode" = "UniversalForward"
            }

        HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_local USE_EMISSION_ON __

            #pragma multi_compile_local _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_local _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_local_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_local_fragment _ _REFLECTIN_PROBE_BLENDING
            #pragma multi_compile_local_fragment _ _REFLECTION_PROBE_BOX_P0ROJECTION
            #pragma multi_compile_local_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_local_fragment _ _SCREEN_SPACE_OCCLUSION

            #pragma multi_compile_local _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile_local _ SHADOWS_SHADOWMASK
            #pragma multi_compile_local _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile_local _ LIGHTMAP_ON
            #pragma multi_compile_local _ DYNAMICLIGHTMAP_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceData.hlsl"

            struct appdata
            {
                float4 positionOS : Position;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 staticLightMapUV : TEXCOORD1;   
                float2 dynamicLightMapUV : TEXCOORD2;   
            };

            struct v2f
            {
                float4 positionCS : SV_Position;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float4 tangentWS : TEXCOORD3;
                float3 viewDirWS : TEXCOORD4;
                float4 shadowCoord : TEXCOORD5;
                DECLARE_LIGHTMAP_OR_SH(staticLightMapUV, vertexSH, 6);
                float2 dynamicLightmapUV : TEXCOORD7;


            };

            sampler2D _BaseTex;
            sampler2D _MettalicTex;
            sampler2D _SmoothnessTex;
            sampler2D _NormalTex;
            sampler2D _EmissionTex;
            sampler2D _AOtex;


            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseTex_ST;
                float _MetallicStrength;
                float _SmoothnessStrength;
                float _NormalStrength;
                float4 _EmissionColor;
            CBUFFER_END

            v2f vert(appdata v)
            {
                v2f o;
                
                VertexPositionInputs vertexInput = GetVertexPositionInputs(v.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normalOS, v.tangentOS);

                o.positionWS = vertexInput.positionWS;
                o.positionCS = vertexInput.positionCS;

                o.uv = TRANSFORM_TEX(v.uv, _BaseTex);

                o.normalWS = normalInput.normalWS;

                float sign = v.tangentOS.w;
                o.tangentWS = float4(normalInput.tangentWS.xyz, sign);

                o.viewDirWS = GetWorldSpaceNormalizeViewDir(vertexInput.positionWS);

                OUTPUT_LIGHTMAP_UV(v.staticLightMapUV, unity_LightmapST, o.staticLightMapUV);
#ifdef DYNAMICLIGHTMAP_ON

                o.dynamicLightmapUV= v.dynamicLightMapUV.xy * unityDynamicLightmapST.xy +unityDynamicLightmapST.zw;

#endif
                OUTPUT_SH(o.normalWS.xyz, o.vertexSH);
                return o;
            }

            SurfaceData createSurfaceData(v2f i)
            {
                SurfaceData surfaceData = (SurfaceData)0;

                float4 albedoSample = tex2D(_BaseTex, i.uv);
                surfaceData.albedo = albedoSample.rgb * _BaseColor.rgb;
                surfaceData.alpha = albedoSample.a * _BaseColor.a;
                
                float4 metallicSample = tex2D(_BaseTex, i.uv);
                surfaceData.metallic = metallicSample.r * _MetallicStrength;

                
                float4 smoothnessSample = tex2D(_BaseTex, i.uv);
                surfaceData.smoothness = smoothnessSample.r * _SmoothnessStrength;

                
                float3 normalSample = tex2D(_BaseTex, i.uv).rgb;
                normalSample.rg *= _NormalStrength;
                surfaceData.normalTS = normalSample;

#if USE_EMISSION_ON
                float3 emissiveSample = tex2D(_EmissionTex, i.uv);
                surfaceData.emission = emissiveSample * _EmissionColor;
#endif

                float4 aoSample = tex2D(_AOtex, i.uv);
                surfaceData.occlusion = aoSample.r;

                return surfaceData; 
            }

            InputData createInputData(v2f i, float3 normalTS)
            {
                InputData inputData = (InputData)0;
                inputData.positionWS = i.positionWS;

                float3 bitangent = i.tangentWS.w * cross(i.normalWS, i.tangentWS.xyz);
                inputData.tangentToWorld = float3x3(i.tangentWS.xyz, bitangent, i.normalWS);
                inputData.normalWS = TransformTangentToWorld(normalTS, inputData.tangentToWorld);
                
                inputData.viewDirectionWS = SafeNormalize(i.viewDirWS);

                inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
#ifdef DYNAMICLIGHTMAP_ON
                inputData.bakedGO = SAMPLE_GI(i.staticLightMapUV, i.dynamicLightmapUV, i.vertexSH, inputData.normalWS);
#else
                inputData.bakedGI = SAMPLE_GI(i.staticLightMapUV, i.vertexSH, inputData.normalWS);
#endif
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.positionCS);
                inputData.shadowMask = SAMPLE_SHADOWMASK(i.staticLightMapUV);


                return inputData;   
            }

            float4 frag(v2f i) : SV_TARGET
            {
                SurfaceData surfaceData = createSurfaceData(i);
                InputData inputData = createInputData(i, surfaceData.normalTS);

                return UniversalFragmentPBR(inputData, surfaceData);
            }
        ENDHLSL
        }

        Pass
        {
              Name "ShadowCaster"
             
             Tags
             {
                 "LightMode" = "ShadowCaster"
             }

             ZWrite On
             ZTest LEqual

             HLSLPROGRAM

             #pragma vertex ShadowPassVertex
             #pragma fragment ShadowPassFragment
             #pragma multi_compile_instancing

             #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
             #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"

             ENDHLSL
        }
    }
}
