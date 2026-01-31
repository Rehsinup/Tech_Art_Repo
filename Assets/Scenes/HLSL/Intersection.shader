Shader "MyShader/Intersection"
{
    Properties
    {
        _BaseColor("Base color", Color) = (1,1,1,1)
        _IntersectionColor("Intersection Color", Color) = (1,0,0,1)
        _IntersectionPower("Intersection Power", Range(0.1,100)) = 1
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            struct appdata
            {
                float4 positionOS : Position;
            };

            struct v2f
            {
                float4 positionCS : SV_Position;
                float4 positionSS : TEXCOORD0;
            };

            sampler2D _BaseTex;

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _IntersectionColor;
                float _IntersectionPower;
            CBUFFER_END

            v2f vert(appdata v)
            {
                v2f o;
                o.positionCS = TransformObjectToHClip(v.positionOS);
                o.positionSS = ComputeScreenPos(o.positionCS);
                return o;
            }

            float4 frag(v2f i) : SV_TARGET
            {
                float2 screensUVs = i.positionSS.xy / i.positionSS.w;
                float rawDepth = SampleSceneDepth(screensUVs).r;
                float sceneEyeDepth= LinearEyeDepth(rawDepth, _ZBufferParams);

                float intersectAmount = sceneEyeDepth - i.positionSS.w;
                intersectAmount = saturate(1.0f - intersectAmount);
                intersectAmount = pow(intersectAmount, _IntersectionPower);



                return lerp(_BaseColor, _IntersectionColor, intersectAmount);
            }
        ENDHLSL
        }
    }
}
