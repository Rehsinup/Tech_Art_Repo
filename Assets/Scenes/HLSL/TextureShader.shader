Shader "MyShader/TextureShader"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1,1,1,1)
        [Toggle(ENABLE_EMSSIVE)] _EnableEmissive("Enable Emissive", Float) = 0
        [HDR] _EmissiveColor("Emissive Color", Color) = (0,0,0,1)
        _BaseTex("Base Texture", 2D) = "white" {}
        _Offset("Offset", Vector) = (0,0,0,0)
        _GlossPower("Gloss Power", Float) = 400
        _FresnelPower("Fresnel Power", Float) = 5
        _ClipThreshold("Alpha Clip Threshold", Range(0,1)) = 0.5
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
            Tags
            {
                "LightMode" = "UniversalForward"
            }

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_local ENABLE_EMSSIVE _

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct appdata
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS: NORMAL;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float4 positionSS : TEXCOORD3;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 viewWS : TEXCOORD2;
            };

            sampler2D _BaseTex;

            CBUFFER_START(UnityPerMaterial)
                float4 _EmissiveColor;
                float4 _BaseColor;
                float4 _BaseTex_ST;
                float2 _Offset;
                float _ClipThreshold;
                float _GlossPower;
                float _FresnelPower;
            CBUFFER_END

            v2f vert(appdata v)
            {
                v2f o;
                float wave = (sin(_Time.y) + 1.0f) * 0.5f;
                float3 wavePosition = v.positionOS.xyz /* * wave */;
                o.positionCS = TransformObjectToHClip(float4(wavePosition, v.positionOS.w));
                o.positionSS = ComputeScreenPos(v.positionOS);
                o.uv = TRANSFORM_TEX(v.uv + _Offset, _BaseTex);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                //mul() = multiplie une matrice et un vecteur 
                float3 positionWS = TransformObjectToWorld(v.positionOS).xyz;
                o.viewWS = GetWorldSpaceNormalizeViewDir(positionWS);
                return o; 
            }

            float4 frag(v2f i) : SV_TARGET
            {
                float4 textureSample = tex2D(_BaseTex, i.uv);
                float4 finalColor = textureSample * _BaseColor;

                Light mainLight = GetMainLight();
                float3 diffuse = mainLight.color * max(0, dot(i.normalWS, mainLight.direction));
                float3 ambient = SampleSH(i.normalWS);

                float4 diffuseLighting = float4(diffuse + ambient, 1.0);

                float3 halfVector = normalize(mainLight.direction + i.viewWS);
                float specular = max(0, dot(i.normalWS, halfVector));
                specular = pow(specular, _GlossPower);
                float3 specularColor = mainLight.color * specular;

                float fresnel = 1.0f - max(0, dot(i.normalWS, i.viewWS));
                fresnel = pow(fresnel, _FresnelPower);
                float3 fresnelColor =  fresnel * diffuse;

                float4 specularLighting = float4(specularColor + fresnelColor, 1.0);

                float2 screenUVs = i.positionSS.xy / i.positionSS.w * _ScreenParams.xy;

                float ditherThresholds[16] = {
                      16.0 / 17.0, 8.0 / 17.0, 14.0 / 17.0, 6.0 / 17.0,
                      4.0 / 17.0, 12.0 / 17.0, 2.0 / 17.0, 10.0 / 17.0,
                      13.0 / 17.0, 5.0 / 17.0, 15.0 / 17.0, 7.0 / 17.0,
                      1.0 / 17.0, 9.0 / 17.0, 3.0 / 17.0, 11.0 / 17.0
                };

                uint index = (uint(screenUVs.x) % 4) * 4 + uint(screenUVs.y) % 4;
                float Threshold = ditherThresholds[index];

                clip(finalColor.a - Threshold);

                //clip (finalColor.a < _ClipThreshold) même chose que en dessous juste écris différement en une ligne
                if (finalColor.a < _ClipThreshold)
                   discard;

#if ENABLE_EMSSIVE

                   return finalColor * diffuseLighting + specularLighting + _EmissiveColor;
#else
                   return finalColor * diffuseLighting + specularLighting;
#endif
                
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

        Pass
        {
            Name "DepthOnlyPass"
            
            Tags
            {
                "LightMode" = "DepthOnly"
            }

            ZWrite On
            ColorMask 0

            HLSLPROGRAM

            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"

            ENDHLSL
        }
    }
}
