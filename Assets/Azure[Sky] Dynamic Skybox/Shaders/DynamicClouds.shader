﻿Shader "Azure[Sky]/Dynamic Clouds"
{
	SubShader
	{
		Tags { "Queue"="Background" "RenderType"="Background" "PreviewType"="Skybox" "IgnoreProjector"="True" }
	    Cull Back     // Render side
		Fog{Mode Off} // Don't use fog
    	ZWrite Off    // Don't draw to depth buffer

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 3.0
			
			// Constants
			#define PI 3.1415926535
			#define Pi316 0.0596831
			#define Pi14 0.07957747
			#define MieG float3(0.4375f, 1.5625f, 1.5f)
			
			// Inputs
			uniform sampler2D   _Azure_SunTexture, _Azure_MoonTexture, _Azure_StarFieldTexture, _Azure_DynamicCloudNoiseTexture;
			uniform samplerCUBE _Azure_StarNoiseTexture;
			
			uniform int       _Azure_StylizedTransmittanceMode;
			uniform float3    _Azure_SunDirection, _Azure_MoonDirection;
			uniform float3    _Azure_Br, _Azure_Bm;
			uniform float     _Azure_ScatteringIntensity, _Azure_SkyLuminance, _Azure_Exposure;
			uniform float3    _Azure_RayleighColor, _Azure_MieColor, _Azure_TransmittanceColor;
			uniform float     _Azure_SunTextureSize, _Azure_SunTextureIntensity, _Azure_MoonTextureSize, _Azure_MoonTextureIntensity;
			uniform float3    _Azure_SunTextureColor, _Azure_MoonTextureColor, _Azure_StarFieldColorBalance;
			uniform float     _Azure_RegularStarsScintillation, _Azure_RegularStarsIntensity, _Azure_MilkyWayIntensity;
			uniform float     _Azure_DynamicCloudAltitude, _Azure_DynamicCloudDirection, _Azure_DynamicCloudSpeed, _Azure_DynamicCloudDensity, _Azure_ThunderLightning, _Azure_ThunderMultiplier;
			uniform float3    _Azure_DynamicCloudColor1, _Azure_DynamicCloudColor2;
			
			uniform float4x4  _Azure_SunMatrix, _Azure_MoonMatrix, _Azure_UpDirectionMatrix, _Azure_StarFieldMatrix, _Azure_NoiseRotationMatrix;

			struct appdata
			{
				float4 vertex : POSITION;
			};

			struct v2f
			{
				float4 Position : SV_POSITION;
				float3 WorldPos : TEXCOORD0;
				float3 SunPos   : TEXCOORD1;
				float3 MoonPos  : TEXCOORD2;
				float3 StarPos  : TEXCOORD3;
				float3 NoiseRot : TEXCOORD4;
				float3 CloudPos : TEXCOORD5;
				float4 CloudUV  : TEXCOORD6;
			};
			
			v2f vert (appdata v)
			{
				v2f Output;
				UNITY_INITIALIZE_OUTPUT(v2f, Output);

				Output.Position = UnityObjectToClipPos(v.vertex);
				Output.WorldPos = normalize(mul((float3x3)unity_WorldToObject, v.vertex.xyz));
				Output.WorldPos = normalize(mul((float3x3)_Azure_UpDirectionMatrix, Output.WorldPos));
				
				// Dynamic clouds position
				Output.CloudPos = normalize(mul((float3x3)unity_WorldToObject, v.vertex.xyz));
				Output.CloudPos = normalize(mul((float3x3)_Azure_UpDirectionMatrix, Output.CloudPos));
				
				// Dynamic clouds direction
				float s = sin (_Azure_DynamicCloudDirection);
                float c = cos (_Azure_DynamicCloudDirection);
                float2x2 rotationMatrix = float2x2( c, -s, s, c);
				Output.CloudPos.y  *= _Azure_DynamicCloudAltitude;
				//float3 viewDir = normalize(Output.WorldPos + float3(0.0, 1.0, 0.0));
				//Output.CloudPos.y *= dot(float3(0.0, viewDir.y + 50.0, 0), float3(0.0, -0.15, 0.0)) * -1.0;
				Output.CloudPos.xz  = mul(Output.CloudPos.xz, rotationMatrix );

				// Dynamic clouds uv
				float cloudSpeed = _Azure_DynamicCloudSpeed * _Time;
				Output.CloudPos = normalize(Output.CloudPos);
				
				// Outputs
				Output.CloudUV.xy = Output.CloudPos.xz * 0.25 - 0.005 + float2(cloudSpeed / 20, cloudSpeed);
				Output.CloudUV.zw = Output.CloudPos.xz * 0.35 -0.0065 + float2(cloudSpeed / 20, cloudSpeed);
				Output.SunPos = mul((float3x3)_Azure_SunMatrix, v.vertex.xyz) * _Azure_SunTextureSize;
				Output.StarPos  = mul((float3x3)_Azure_StarFieldMatrix, Output.WorldPos);
				Output.NoiseRot = mul((float3x3)_Azure_NoiseRotationMatrix, v.vertex.xyz);
				Output.MoonPos = mul((float3x3)_Azure_MoonMatrix, v.vertex.xyz) * 0.75 * _Azure_MoonTextureSize;
				Output.MoonPos.x *= -1.0;
				
				return Output;
			}
			
			bool iSphere(in float3 origin, in float3 direction, in float3 position, in float radius, out float3 normalDirection)
			{
				float3 rc = origin - position;
				float c = dot(rc, rc) - (radius * radius);
				float b = dot(direction, rc);
				float d = b * b - c;
				float t = -b - sqrt(abs(d));
				float st = step(0.0, min(t, d));
				normalDirection = normalize(-position + (origin + direction * t));

				if (st > 0.0) { return true; }
				return false;
			}
			
			float4 frag (v2f Input) : SV_Target
			{
			    // Initializations
			    //float3 Esun = float3(1.0, 0.3, 0.15);
			    float3 transmittance = float3(1.0, 1.0, 1.0);
			    
			    // Directions
				float3 viewDir = normalize(Input.WorldPos);
				float  sunCosTheta = dot(viewDir, _Azure_SunDirection);
				float  moonCosTheta = dot(viewDir, _Azure_MoonDirection);
				float  r = length(float3(0.0, 50.0, 0.0));
				float  sunRise = saturate(dot(float3(0.0, 500.0, 0.0), _Azure_SunDirection) / r);
				float  moonRise = saturate(dot(float3(0.0, 500.0, 0.0), _Azure_MoonDirection) / r);
				
				// Optical depth
				float zenith = acos(saturate(dot(float3(0.0, 1.0, 0.0), viewDir)));
				float z = (cos(zenith) + 0.15 * pow(93.885 - ((zenith * 180.0f) / PI), -1.253));
	            float SR = 8400.0 / z;
	            float SM = 1200.0 / z;
	            
	            // Extinction
                float3 fex = exp(-(_Azure_Br*SR  + _Azure_Bm*SM));
                float  sunset = clamp(dot(float3(0.0, 1.0, 0.0), _Azure_SunDirection), 0.0, 0.5);
				if(_Azure_StylizedTransmittanceMode == 0)
				{
				    transmittance = lerp(fex, (1.0 - fex), sunset);
				    _Azure_TransmittanceColor = float3(1.0, 1.0, 1.0);
				}
				float horizonExtinction = saturate((viewDir.y) * 1000.0) * fex.b;
                
                // Sun inScattering
                float  rayPhase = 2.0 + 0.5 * pow(sunCosTheta, 2.0);
                float  miePhase = MieG.x / pow(MieG.y - MieG.z * sunCosTheta, 1.5);
                
                float3 BrTheta  = Pi316 * _Azure_Br * rayPhase * _Azure_RayleighColor;
                float3 BmTheta  = Pi14  * _Azure_Bm * miePhase * _Azure_MieColor * sunRise;
                float3 BrmTheta = (BrTheta + BmTheta) * transmittance / (_Azure_Br + _Azure_Bm);
                
                float3 inScatter = BrmTheta * _Azure_TransmittanceColor * _Azure_ScatteringIntensity * (1.0 - fex);
                inScatter *= sunRise;
                
                // Moon inScattering
                rayPhase = 2.0 + 0.5 * pow(moonCosTheta, 2.0);
                miePhase = MieG.x / pow(MieG.y - MieG.z * moonCosTheta, 1.5);
                
                //BrTheta  = Pi316 * _Azure_Br * rayPhase * _Azure_RayleighColor;
                BmTheta  = Pi14  * _Azure_Bm * miePhase * _Azure_MieColor * moonRise;
                BrmTheta = (BrTheta + BmTheta) / (_Azure_Br + _Azure_Bm);
                
                float3 moonInScatter = BrmTheta * _Azure_TransmittanceColor * _Azure_ScatteringIntensity * 0.1 * (1.0 - fex);
                moonInScatter *= moonRise;
                moonInScatter *= 1.0 - sunRise;
                
                // Default night sky - When there is no moon in the sky
                BrmTheta = BrTheta / (_Azure_Br + _Azure_Bm);
                float3 skyLuminance = BrmTheta * _Azure_TransmittanceColor * _Azure_SkyLuminance * (1.0 - fex);
                
                //Dynamic Clouds Layer1.
				//--------------------------------
				float4 tex1 = tex2D(_Azure_DynamicCloudNoiseTexture, Input.CloudUV.xy );
				float4 tex2 = tex2D(_Azure_DynamicCloudNoiseTexture, Input.CloudUV.zw );
				float3 cloud = float3(0.0, 0.0, 0.0);
				float  cloudAlpha = 1.0;
				float noise1 = 1.0;
				float noise2 = 1.0;
				float mixCloud = 0.0;
				if(_Azure_DynamicCloudDensity<25)
				{
					#ifndef UNITY_COLORSPACE_GAMMA
					_Azure_DynamicCloudColor1 = pow(_Azure_DynamicCloudColor1, 2.2);
					_Azure_DynamicCloudColor2 = pow(_Azure_DynamicCloudColor2, 2.2);
    				#endif

					noise1 = pow(tex1.g + tex2.g, 0.1);
					noise2 = pow(tex2.b * tex1.r, 0.25);

						   cloudAlpha = saturate(pow(noise1 * noise2, _Azure_DynamicCloudDensity));
					float3 cloud1 = lerp(_Azure_DynamicCloudColor1.rgb, float3(0.0, 0.0, 0.0), noise1);
					float3 cloud2 = lerp(_Azure_DynamicCloudColor1.rgb, _Azure_DynamicCloudColor2.rgb, noise2) * 2.5;
						   cloud  = lerp(cloud1, cloud2, noise1 * noise2);
						   
						   float3 cloudLightning = lerp(float3(0.0,0.0,0.0), float3(1.0,1.0,1.0), saturate(pow(cloud, lerp(4.5, 2.25, _Azure_ThunderMultiplier)) * 500.0f));
						   
						   cloud  += cloudLightning * _Azure_ThunderLightning;
						   cloudAlpha = 1.0 - cloudAlpha;
						   mixCloud = saturate(pow(Input.CloudPos.y, 5.0) * pow(noise1 * noise2, _Azure_DynamicCloudDensity));
				}
                
                // Sun texture
                float3 sunTexture = tex2D( _Azure_SunTexture, Input.SunPos + 0.5).rgb * _Azure_SunTextureColor * _Azure_SunTextureIntensity;
					   sunTexture = pow(sunTexture, 2.0);
					   sunTexture *= fex.b * saturate(sunCosTheta);
					   
				// Moon sphere
				float3 rayOrigin = float3(0.0, 0.0, 0.0);//_WorldSpaceCameraPos;
				float3 rayDirection = viewDir;
				float3 moonPosition = _Azure_MoonDirection * 38400.0 * _Azure_MoonTextureSize;
				float3 normalDirection = float3(0.0, 0.0, 0.0);
				float3 moonColor = float3(0.0, 0.0, 0.0);
				float4 moonTexture = saturate(tex2D( _Azure_MoonTexture, Input.MoonPos.xy + 0.5) * moonCosTheta);
				float moonMask = 1.0 - moonTexture.a;
				if(iSphere(rayOrigin, rayDirection, moonPosition, 17370.0, normalDirection))
				{
					float moonSphere = max(dot(normalDirection, _Azure_SunDirection), 0.0) * moonTexture.a * 2.0;
					moonColor = moonTexture.rgb * moonSphere * _Azure_MoonTextureColor * _Azure_MoonTextureIntensity * horizonExtinction;
				}
				
				// Starfield
				float2 stars_uv = float2(-atan2(Input.StarPos.z, Input.StarPos.x), -acos(Input.StarPos.y)) / float2(2.0 * PI, PI);
				float scintillation = texCUBE(_Azure_StarNoiseTexture, Input.NoiseRot).r * 1.5;
				float4 starTexture   = tex2D(_Azure_StarFieldTexture, stars_uv);
				float3 stars     = starTexture.rgb * pow(starTexture.a, 2.0) * _Azure_RegularStarsIntensity * scintillation;
				float3 milkyWay  = (pow(starTexture.rgb, 1.5)) * _Azure_MilkyWayIntensity;
				float3 starfield = (stars + milkyWay) * _Azure_StarFieldColorBalance * horizonExtinction * moonMask;
                
                // Output
				float3 OutputColor = inScatter + moonInScatter + skyLuminance + (sunTexture + moonColor + starfield) * cloudAlpha;
                
                // Tonemapping
                OutputColor = saturate(1.0 - exp(-_Azure_Exposure * OutputColor));
                
                // Color correction
				OutputColor = pow(OutputColor, 2.2);
			    #ifdef UNITY_COLORSPACE_GAMMA
			    OutputColor = pow(OutputColor, 0.4545);
				#else
				OutputColor = OutputColor;
    			#endif
    			
    			//Apply Clouds.
				OutputColor = lerp(OutputColor, cloud, mixCloud);
				
				return float4(OutputColor, 1.0);
			}
			ENDCG
		}
	}
}