//////////////////////////////////////////////////////////////////////
// PSSM shadow mapping
// (c) oP group 2010  Version 1.1
//////////////////////////////////////////////////////////////////////
//#define BONES // activate GPU bones (reduces the frame rate by 5%)
#ifdef BONES
#include <bones>
#endif
#include <pos>

//const bool AUTORELOAD;

float4x4 matViewProj;
float4x4 matView;
float4x4 matTex[4]; // set up from the pssm script

#define PCFSAMPLES_NEAR	5	// higher values for smoother shadows (slower)
#define PCFSAMPLES_FAR	3

float pssm_splitdist_var[5];
float pssm_numsplits_var = 3;
float pssm_fbias_flt = 0.0005f;
float pssm_res_var = 1024;
float pssm_transparency_var = 0.7;
float d3d_alpharef_var;

texture entSkin1;
texture mtlSkin1;
texture mtlSkin2;
texture mtlSkin3;
texture mtlSkin4;

sampler sBaseTex = sampler_state { Texture = <entSkin1>; MipFilter = linear; };

sampler sDepth1 = sampler_state {
	texture = <mtlSkin1>;
	MinFilter = point; MagFilter = point; MipFilter = none;
	AddressU = Border; AddressV = Border;
	BorderColor = 0xFFFFFFFF;
};
sampler sDepth2 = sampler_state {
	texture = <mtlSkin2>;
	MinFilter = point; MagFilter = point; MipFilter = none;
	AddressU = Border; AddressV = Border;
	BorderColor = 0xFFFFFFFF;
};
sampler sDepth3 = sampler_state {
	texture = <mtlSkin3>;
	MinFilter = point; MagFilter = point; MipFilter = none;
	AddressU = Border; AddressV = Border;
	BorderColor = 0xFFFFFFFF;
};
sampler sDepth4 = sampler_state {
	texture = <mtlSkin4>;
	MinFilter = point; MagFilter = point; MipFilter = none;
	AddressU = Border; AddressV = Border;
	BorderColor = 0xFFFFFFFF;
};
//////////////////////////////////////////////////////////////////

// PCF soft-shadowing
float DoPCF(sampler2D sMap,float4 vShadowTexCoord,int iSqrtSamples,float fBias)
{
	float fShadowTerm = 0.0f;  
	float fRadius = (iSqrtSamples - 1.0f) / 2;

	for (float y = -fRadius; y <= fRadius; y++)
	{
		for (float x = -fRadius; x <= fRadius; x++)
		{
			float2 vOffset = float2(x,y)/pssm_res_var;
			float fDepth = tex2D(sMap, vShadowTexCoord.xy + vOffset).x;
			float fSample = (vShadowTexCoord.z < fDepth + fBias);

// Edge tap smoothing 	
			float xWeight = 1, yWeight = 1;
			if (x == -fRadius) 
				xWeight = 1 - frac(vShadowTexCoord.x * pssm_res_var);
			else if (x == fRadius)
				xWeight = frac(vShadowTexCoord.x * pssm_res_var);
				
			if (y == -fRadius)
				yWeight = 1 - frac(vShadowTexCoord.y * pssm_res_var);
			else if (y == fRadius)
				yWeight = frac(vShadowTexCoord.y * pssm_res_var);
	
			fShadowTerm += fSample * xWeight * yWeight;
		}											
	}		
	
	return fShadowTerm / (iSqrtSamples * iSqrtSamples);
}

// Calculates the shadow occlusion using bilinear PCF
float DoFastPCF(sampler2D sMap,float4 vShadowTexCoord,float fBias)
 //float fLightDepth, float2 vTexCoord)
{
    float fShadowTerm = 0.0f;

    // transform to texel space
    float2 vShadowMapCoord = pssm_res_var * vShadowTexCoord.xy;
    
    // Determine the lerp amounts           
    float2 vLerps = frac(vShadowMapCoord);

    // read in bilerp stamp, doing the shadow checks
    float fSamples[4];
    
    fSamples[0] = (tex2Dlod(sMap,float4(vShadowTexCoord.xy,0,0)).x + fBias < vShadowTexCoord.z) ? 0.0f: 1.0f;  
    fSamples[1] = (tex2Dlod(sMap,float4(vShadowTexCoord.xy + float2(1.0/pssm_res_var,0),0,0)).x + fBias < vShadowTexCoord.z) ? 0.0f: 1.0f;  
    fSamples[2] = (tex2Dlod(sMap,float4(vShadowTexCoord.xy + float2(0,1.0/pssm_res_var),0,0)).x + fBias < vShadowTexCoord.z) ? 0.0f: 1.0f;  
    fSamples[3] = (tex2Dlod(sMap,float4(vShadowTexCoord.xy + float2(1.0/pssm_res_var,1.0/pssm_res_var),0,0)).x + fBias < vShadowTexCoord.z) ? 0.0f: 1.0f;  
    
    // lerp between the shadow values to calculate our light amount
    fShadowTerm = lerp( lerp( fSamples[0], fSamples[1], vLerps.x ),
                              lerp( fSamples[2], fSamples[3], vLerps.x ),
                              vLerps.y );                              
                                
    return fShadowTerm;                                
}

float4 vecTime;

void renderShadows_VS(
  in float4 inPos: POSITION,
  in float2 inTex: TEXCOORD0,
#ifdef BONES
	in int4 inBoneIndices: BLENDINDICES,
	in float4 inBoneWeights: BLENDWEIGHT,
#endif	
  out float4 outPos: POSITION,
  out float4 TexCoord[4]: TEXCOORD,
  out float2 outTex: TEXCOORD4,
  out float fDistance: TEXCOORD5
  )
{
// calculate world position
#ifdef BONES
  float4 PosWorld = DoPos(DoBones(inPos,inBoneIndices,inBoneWeights));
#else  		
  float4 PosWorld = DoPos(inPos);
#endif  
  outPos = mul(PosWorld,matViewProj);
// store view space position
  fDistance = mul(PosWorld, matView).z;
  outTex = inTex;
// coordinates for shadow maps
  for(int i=0;i<pssm_numsplits_var;i++)
    TexCoord[i] = mul(PosWorld,matTex[i]);
}


float4 renderShadows_PS(
  float4 TexCoord[4] : TEXCOORD,
  float2 inTex: TEXCOORD4,
  float fDistance: TEXCOORD5
  ) : COLOR
{
// clip away shadows from transparent surfaces	
  float fShadow;
#ifdef FAST
  if(fDistance < pssm_splitdist_var[1] || pssm_numsplits_var < 2)
 	  fShadow = DoFastPCF(sDepth1,TexCoord[0],pssm_fbias_flt);
  else if(fDistance < pssm_splitdist_var[2] || pssm_numsplits_var < 3)
 	  fShadow = DoFastPCF(sDepth2,TexCoord[1],2*pssm_fbias_flt);
  else if(fDistance < pssm_splitdist_var[3] || pssm_numsplits_var < 4)
 	  fShadow = DoFastPCF(sDepth3,TexCoord[2],4*pssm_fbias_flt);
  else
 	  fShadow = DoFastPCF(sDepth4,TexCoord[3],8*pssm_fbias_flt);
#else
  if(fDistance < pssm_splitdist_var[1] || pssm_numsplits_var < 2)
 	  fShadow = DoPCF(sDepth1,TexCoord[0],PCFSAMPLES_NEAR,pssm_fbias_flt);
  else if(fDistance < pssm_splitdist_var[2] || pssm_numsplits_var < 3)
 	  fShadow = DoPCF(sDepth2,TexCoord[1],PCFSAMPLES_FAR,2*pssm_fbias_flt);
  else if(fDistance < pssm_splitdist_var[3] || pssm_numsplits_var < 4)
 	  fShadow = DoPCF(sDepth3,TexCoord[2],PCFSAMPLES_FAR,4*pssm_fbias_flt);
  else
 	  fShadow = DoPCF(sDepth4,TexCoord[3],PCFSAMPLES_FAR,8*pssm_fbias_flt);
#endif

	float alpha = tex2Dlod(sBaseTex,float4(inTex.xy,0.0f,0.0f)).a * pssm_transparency_var;
	clip(alpha-d3d_alpharef_var/255.f); // for alpha transparent textures
	return float4(0,0,0,clamp(1-2.5*fShadow,0,alpha));
}

technique renderShadows
{
  pass p0
  {
		ZWriteEnable = True;
		AlphaBlendEnable = False;

		VertexShader = compile vs_3_0 renderShadows_VS();
		PixelShader = compile ps_3_0 renderShadows_PS();
  }
}

