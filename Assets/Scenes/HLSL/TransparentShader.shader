Shader "Unlit/TransparentShader"
{
    Properties
    {
    _BaseColor("Base Color", Color) = (1,1,1,1)

    [Enum(UnityEngine.Rendering.BlendMode)]
    _SrcBlend("Src Blend Factor", Int) = 1
    [Enum(UnityEngine.Rendering.BlendMode)]
    _DstBlend("Dst Blend Factor", Int) = 1

    }
    SubShader
    {
        Tags {   "RenderType"="Transparent" 
                 "Queue" = "Transparent"
                 "RenderPipeline" = "UniversalPipeline"
             }
     

        Pass
        {

            Blend [_SrcBlend] [_DstBlend]

            Tags
            {
                "LightMode" = "UniversalForward"
            }

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct appdata
            {
                float4 positionOS : POSITION;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;

                CBUFFER_END

                v2f vert(appdata v)
                {
                    v2f o;
                    o.positionCS = TransformObjectToHClip(v.positionOS);
                    return o;
                }

                float4 frag(v2f i) : SV_TARGET
                {
                    return _BaseColor;
                }

                ENDHLSL
        }
    }
}