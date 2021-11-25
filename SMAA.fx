/**
 * Copyright (C) 2013 Jorge Jimenez (jorge@iryoku.com)
 * Copyright (C) 2013 Jose I. Echevarria (joseignacioechevarria@gmail.com)
 * Copyright (C) 2013 Belen Masia (bmasia@unizar.es)
 * Copyright (C) 2013 Fernando Navarro (fernandn@microsoft.com)
 * Copyright (C) 2013 Diego Gutierrez (diegog@unizar.es)
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 * of the Software, and to permit persons to whom the Software is furnished to
 * do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software. As clarification, there
 * is no requirement that the copyright notice and permission be included in
 * binary distributions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
#define SMAA_THRESHOLD 0.1
#define SMAA_MAX_SEARCH_STEPS 16
#define SMAA_MAX_SEARCH_STEPS_DIAG 8
#define SMAA_CORNER_ROUNDING 25
#define SMAA_AREATEX_MAX_DISTANCE 16
#define SMAA_AREATEX_MAX_DISTANCE_DIAG 20
#define SMAA_AREATEX_PIXEL_SIZE (1.0 / float2(160.0, 560.0))
#define SMAA_AREATEX_SUBTEX_SIZE (1.0 / 7.0)
#define SMAA_SEARCHTEX_SIZE float2(66.0, 33.0)
#define SMAA_SEARCHTEX_PACKED_SIZE float2(64.0, 16.0)
#define SMAA_CORNER_ROUNDING_NORM (float(SMAA_CORNER_ROUNDING) / 100.0)
 
float2 ViewportSize : VIEWPORTPIXELSIZE;
static float2 ViewportOffset  = (float2(0.5,0.5) / ViewportSize);
static float2 ViewportOffset2 = (float2(1.0,1.0) / ViewportSize);

texture ScnMap : RENDERCOLORTARGET <
	float2 ViewPortRatio = {1.0,1.0};
	bool AntiAlias = false;
	string Format = "X8R8G8B8";
>;
sampler ScnSamp = sampler_state {
	texture = <ScnMap>;
	MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = NONE;
	AddressU = CLAMP; AddressV = CLAMP;
};
texture2D DepthBuffer : RENDERDEPTHSTENCILTARGET<
	float2 ViewportRatio = {1.0,1.0};
	string Format = "D24S8";
>;
texture SMAAEdgeMap : RENDERCOLORTARGET <
	float2 ViewPortRatio = {1.0, 1.0};
	bool AntiAlias = false;
	string Format = "A8L8";
>;
texture SMAABlendMap : RENDERCOLORTARGET <
	float2 ViewPortRatio = {1.0, 1.0};
	bool AntiAlias = false;
	string Format = "A8R8G8B8";
>;
sampler SMAAEdgeMapSamp = sampler_state {
	texture = <SMAAEdgeMap>;
	MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = NONE;
	AddressU  = CLAMP;  AddressV = CLAMP;
};
sampler SMAABlendMapSamp = sampler_state {
	texture = <SMAABlendMap>;
	MinFilter = POINT; MagFilter = POINT; MipFilter = NONE;
	AddressU  = CLAMP;  AddressV = CLAMP;
};
texture SMAAAreaMap<string ResourceName = "Textures/smaa_area.dds";>;
sampler SMAAAreaMapSamp = sampler_state
{
	texture = <SMAAAreaMap>;
	MinFilter = POINT; MagFilter = POINT; MipFilter = NONE;
	AddressU  = CLAMP; AddressV = CLAMP;
};

texture SMAASearchMap<string ResourceName = "Textures/smaa_search.dds";>;
sampler SMAASearchMapSamp = sampler_state
{
	texture = <SMAASearchMap>;
	MinFilter = POINT; MagFilter = POINT; MipFilter = NONE;
	AddressU  = CLAMP; AddressV = CLAMP;
};

float madd(float v, float t1, float t2)
{
	return v * t1 + t2;
}

float2 madd(float2 v, float2 t1, float2 t2)
{
	return v * t1 + t2;
}

float3 madd(float3 v, float3 t1, float3 t2)
{
	return v * t1 + t2;
}

float4 madd(float4 v, float4 t1, float4 t2)
{
	return v * t1 + t2;
}

float3 srgb2linear(float3 rgb)
{
	rgb = max(6.10352e-5, rgb);
	return rgb < 0.04045f ? rgb * (1.0 / 12.92) : pow(rgb * (1.0 / 1.055) + 0.0521327, 2.4);
}

float4 srgb2linear(float4 c)
{
	return float4(srgb2linear(c.rgb), c.a);
}

float3 linear2srgb(float3 srgb)
{
	srgb = max(6.10352e-5, srgb);
	return min(srgb * 12.92, pow(max(srgb, 0.00313067), 1.0/2.4) * 1.055 - 0.055);
}

float4 linear2srgb(float4 c)
{
	return float4(linear2srgb(c.rgb), c.a);
}

float luminance(float3 rgb)
{
	const float3 lumfact = float3(0.2126f, 0.7152f, 0.0722f);
	return dot(rgb, lumfact);
}

float SMAASearchLength(sampler searchTex, float2 e, float offset) 
{
	float2 scale = SMAA_SEARCHTEX_SIZE * float2(0.5, -1.0);
	scale += float2(-1.0,  1.0);
	scale *= 1.0 / SMAA_SEARCHTEX_PACKED_SIZE;

	float2 bias = SMAA_SEARCHTEX_SIZE * float2(offset, 1.0);
	bias  += float2( 0.5, -0.5);
	bias *= 1.0 / SMAA_SEARCHTEX_PACKED_SIZE;

	return tex2Dlod(searchTex, float4(madd(scale, e, bias), 0, 0)).r;
}

float SMAASearchXLeft(sampler edgesTex, sampler searchTex, float2 texcoord, float end) 
{
	float2 e = float2(0.0, 1.0);

	for (int i = 0; i < SMAA_MAX_SEARCH_STEPS; i++)
	{
		e = tex2Dlod(edgesTex, float4(texcoord, 0, 0)).rg;
		texcoord -= ViewportOffset2 * float2(2.0, 0.0);
		if (!(texcoord.x > end && e.g > 0.8281 && e.r == 0.0)) break;
	}

	float offset = madd(-(255.0 / 127.0), SMAASearchLength(searchTex, e, 0.0), 3.25);
	return madd(ViewportOffset2.x, offset, texcoord.x);
}

float SMAASearchXRight(sampler edgesTex, sampler searchTex, float2 texcoord, float end) 
{
	float2 e = float2(0.0, 1.0);

	for (int i = 0; i < SMAA_MAX_SEARCH_STEPS; i++)
	{
		e = tex2Dlod(edgesTex, float4(texcoord, 0, 0)).rg;
		texcoord += ViewportOffset2 * float2(2.0, 0.0);
		if (!(texcoord.x < end &&  e.g > 0.8281 && e.r == 0.0)) break;
	}

	float offset = madd(-(255.0 / 127.0), SMAASearchLength(searchTex, e, 0.5), 3.25);
	return madd(-ViewportOffset2.x, offset, texcoord.x);
}

float SMAASearchYUp(sampler edgesTex, sampler searchTex, float2 texcoord, float end) 
{
	float2 e = float2(1.0, 0.0);

	for (int i = 0; i < SMAA_MAX_SEARCH_STEPS; i++)
	{
		e = tex2Dlod(edgesTex, float4(texcoord, 0, 0)).rg;
		texcoord -= ViewportOffset2 * float2(0.0, 2.0);
		if (!(texcoord.y > end && e.r > 0.8281 && e.g == 0.0)) break;
	}

	float offset = madd(-(255.0 / 127.0), SMAASearchLength(searchTex, e.gr, 0.0), 3.25);
	return madd(ViewportOffset2.y, offset, texcoord.y);
}

float SMAASearchYDown(sampler edgesTex, sampler searchTex, float2 texcoord, float end) 
{
	float2 e = float2(1.0, 0.0);

	for (int i = 0; i < SMAA_MAX_SEARCH_STEPS; i++)
	{
		e = tex2Dlod(edgesTex, float4(texcoord, 0, 0)).rg;
		texcoord += ViewportOffset2 * float2(0.0, 2.0);
		if (!(texcoord.y < end && e.r > 0.8281 && e.g == 0.0)) break;
	}

	float offset = madd(-(255.0 / 127.0), SMAASearchLength(searchTex, e.gr, 0.5), 3.25);
	return madd(-ViewportOffset2.y, offset, texcoord.y);
}

float2 SMAAArea(sampler areaTex, float2 dist, float e1, float e2, float offset) 
{
	float2 texcoord = madd(float2(SMAA_AREATEX_MAX_DISTANCE, SMAA_AREATEX_MAX_DISTANCE), round(4.0 * float2(e1, e2)), dist);
	texcoord = madd(SMAA_AREATEX_PIXEL_SIZE, texcoord, 0.5 * SMAA_AREATEX_PIXEL_SIZE);
	texcoord.y = madd(SMAA_AREATEX_SUBTEX_SIZE, offset, texcoord.y);
	return tex2Dlod(areaTex, float4(texcoord, 0, 0)).ra;
}

void SMAAMovc(bool2 cond, inout float2 variable, float2 value) 
{
	[flatten] if (cond.x) variable.x = value.x;
	[flatten] if (cond.y) variable.y = value.y;
}

void SMAAMovc(bool4 cond, inout float4 variable, float4 value) 
{
	SMAAMovc(cond.xy, variable.xy, value.xy);
	SMAAMovc(cond.zw, variable.zw, value.zw);
}

#if SMAA_MAX_SEARCH_STEPS_DIAG

float2 SMAAAreaDiag(sampler areaTex, float2 dist, float2 e, float offset) 
{
	float2 texcoord = madd(float2(SMAA_AREATEX_MAX_DISTANCE_DIAG, SMAA_AREATEX_MAX_DISTANCE_DIAG), e, dist);
	texcoord = madd(SMAA_AREATEX_PIXEL_SIZE, texcoord, 0.5 * SMAA_AREATEX_PIXEL_SIZE);
	texcoord.x += 0.5;
	texcoord.y += SMAA_AREATEX_SUBTEX_SIZE * offset;
	return tex2Dlod(areaTex, float4(texcoord, 0, 0)).ra;
}

float2 SMAADecodeDiagBilinearAccess(float2 e) 
{
	e.r = e.r * abs(5.0 * e.r - 5.0 * 0.75);
	return round(e);
}

float4 SMAADecodeDiagBilinearAccess(float4 e) 
{
	e.rb = e.rb * abs(5.0 * e.rb - 5.0 * 0.75);
	return round(e);
}

float2 SMAASearchDiag1(sampler edgesTex, float2 texcoord, float2 dir, out float2 e) 
{
	float4 coord = float4(texcoord, -1.0, 1.0);
	float3 t = float3(ViewportOffset2.xy, 1.0);

	for (int i = 0; i < SMAA_MAX_SEARCH_STEPS_DIAG; i++)
	{
		if (!(coord.z < float(SMAA_MAX_SEARCH_STEPS_DIAG - 1) && coord.w > 0.9)) break;
		coord.xyz = madd(t, float3(dir, 1.0), coord.xyz);
		e = tex2Dlod(edgesTex, float4(coord.xy, 0, 0)).rg;
		coord.w = dot(e, float2(0.5, 0.5));
	}

	return coord.zw;
}

float2 SMAASearchDiag2(sampler edgesTex, float2 texcoord, float2 dir, out float2 e) 
{
	float4 coord = float4(texcoord, -1.0, 1.0);
	coord.x += 0.25 * ViewportOffset2.x;
	float3 t = float3(ViewportOffset2.xy, 1.0);

	for (int i = 0; i < SMAA_MAX_SEARCH_STEPS_DIAG; i++)
	{
		if (!(coord.z < float(SMAA_MAX_SEARCH_STEPS_DIAG - 1) && coord.w > 0.9)) break;
		coord.xyz = madd(t, float3(dir, 1.0), coord.xyz);
		e = tex2Dlod(edgesTex, float4(coord.xy, 0, 0)).rg;
		e = SMAADecodeDiagBilinearAccess(e);
		coord.w = dot(e, float2(0.5, 0.5));
	}

	return coord.zw;
}

float2 SMAACalculateDiagWeights(sampler edgesTex, sampler areaTex, float2 texcoord, float2 e, float4 subsampleIndices) 
{
	float2 weights = float2(0.0, 0.0);

	float4 d;
	float2 end;
	if (e.r > 0.0) 
	{
		d.xz = SMAASearchDiag1(edgesTex, texcoord, float2(-1.0,  1.0), end);
		d.x += float(end.y > 0.9);
	}
	else
	{
		d.xz = float2(0.0, 0.0);
	}

	d.yw = SMAASearchDiag1(edgesTex, texcoord, float2(1.0, -1.0), end);

	[branch]
	if (d.x + d.y > 2.0) 
	{
		float4 coords = madd(float4(-d.x + 0.25, d.x, d.y, -d.y - 0.25), ViewportOffset2.xyxy, texcoord.xyxy);
		
		float4 c;
		c.xy = tex2Dlod(edgesTex, float4(coords.xy + float2(-ViewportOffset2.x,  0), 0, 0)).rg;
		c.zw = tex2Dlod(edgesTex, float4(coords.zw + float2( ViewportOffset2.x,  0), 0, 0)).rg;
		c.yxwz = SMAADecodeDiagBilinearAccess(c.xyzw);
		
		float2 cc = madd(float2(2.0, 2.0), c.xz, c.yw);
		SMAAMovc(bool2(step(0.9, d.zw)), cc, float2(0.0, 0.0));
		
		weights += SMAAAreaDiag(areaTex, d.xy, cc, subsampleIndices.z);
	}

	d.xz = SMAASearchDiag2(edgesTex, texcoord, float2(-1.0, -1.0), end);
	if (tex2Dlod(edgesTex, float4(texcoord + float2(1, 0) * ViewportOffset2, 0, 0)).r > 0.0) 
	{
		d.yw = SMAASearchDiag2(edgesTex, texcoord, float2(1.0, 1.0), end);
		d.y += float(end.y > 0.9);
	}
	else
	{
		d.yw = float2(0.0, 0.0);
	}

	[branch]
	if (d.x + d.y > 2.0)
	{
		float4 coords = madd(float4(-d.x, -d.x, d.y, d.y), ViewportOffset2.xyxy, texcoord.xyxy);
		float4 c;
		c.x  = tex2Dlod(edgesTex, float4(coords.xy + float2(-1,  0) * ViewportOffset2, 0, 0)).g;
		c.y  = tex2Dlod(edgesTex, float4(coords.xy + float2( 0, -1) * ViewportOffset2, 0, 0)).r;
		c.zw = tex2Dlod(edgesTex, float4(coords.zw + float2( 1,  0) * ViewportOffset2, 0, 0)).gr;
		
		float2 cc = madd(float2(2.0, 2.0), c.xz, c.yw);
		SMAAMovc(bool2(step(0.9, d.zw)), cc, float2(0.0, 0.0));

		weights += SMAAAreaDiag(areaTex, d.xy, cc, subsampleIndices.w).gr;
	}

	return weights;
}
#endif

void SMAADetectHorizontalCornerPattern(sampler edgesTex, inout float2 weights, float4 texcoord, float2 d) 
{
#if SMAA_CORNER_ROUNDING
	float2 leftRight = step(d.xy, d.yx);
	float2 rounding = (1.0 - SMAA_CORNER_ROUNDING_NORM) * leftRight;

	rounding /= leftRight.x + leftRight.y;

	float2 factor = float2(1.0, 1.0);
	factor.x -= rounding.x * tex2Dlod(edgesTex, float4(texcoord.xy + float2(0,  1) * ViewportOffset2, 0, 0)).r;
	factor.x -= rounding.y * tex2Dlod(edgesTex, float4(texcoord.zw + float2(1,  1) * ViewportOffset2, 0, 0)).r;
	factor.y -= rounding.x * tex2Dlod(edgesTex, float4(texcoord.xy + float2(0, -2) * ViewportOffset2, 0, 0)).r;
	factor.y -= rounding.y * tex2Dlod(edgesTex, float4(texcoord.zw + float2(1, -2) * ViewportOffset2, 0, 0)).r;

	weights *= saturate(factor);
#endif
}

void SMAADetectVerticalCornerPattern(sampler edgesTex, inout float2 weights, float4 texcoord, float2 d) 
{
#if SMAA_CORNER_ROUNDING
	float2 leftRight = step(d.xy, d.yx);
	float2 rounding = (1.0 - SMAA_CORNER_ROUNDING_NORM) * leftRight;

	rounding /= leftRight.x + leftRight.y;

	float2 factor = float2(1.0, 1.0);
	factor.x -= rounding.x * tex2Dlod(edgesTex, float4(texcoord.xy + float2( 1, 0) * ViewportOffset2, 0, 0)).g;
	factor.x -= rounding.y * tex2Dlod(edgesTex, float4(texcoord.zw + float2( 1, 1) * ViewportOffset2, 0, 0)).g;
	factor.y -= rounding.x * tex2Dlod(edgesTex, float4(texcoord.xy + float2(-2, 0) * ViewportOffset2, 0, 0)).g;
	factor.y -= rounding.y * tex2Dlod(edgesTex, float4(texcoord.zw + float2(-2, 1) * ViewportOffset2, 0, 0)).g;

	weights *= saturate(factor);
#endif
}

float4 SMAAEdgeDetectionVS(
	in float4 Position : POSITION,
	in float4 Texcoord : TEXCOORD,
	out float4 oTexcoord0 : TEXCOORD0,
	out float4 oTexcoord1 : TEXCOORD1,
	out float4 oTexcoord2 : TEXCOORD2,
	out float4 oTexcoord3 : TEXCOORD3) : POSITION
{
	oTexcoord0 = Texcoord.xyxy + ViewportOffset.xyxy;
	oTexcoord1 = oTexcoord0 + ViewportOffset2.xyxy * float4(-1.0, 0.0, 0.0, -1.0);
	oTexcoord2 = oTexcoord0 + ViewportOffset2.xyxy * float4( 1.0, 0.0, 0.0,  1.0);
	oTexcoord3 = oTexcoord0 + ViewportOffset2.xyxy * float4(-2.0, 0.0, 0.0, -2.0);
	return Position;
}

float4 SMAALumaEdgeDetectionPS(
	in float4 coord0 : TEXCOORD0,
	in float4 coord1 : TEXCOORD1,
	in float4 coord2 : TEXCOORD2,
	in float4 coord3 : TEXCOORD3,
	uniform sampler source) : COLOR
{
	float4 offset[3] = { coord1, coord2, coord3 };
	float2 threshold = float2(SMAA_THRESHOLD, SMAA_THRESHOLD);

	float Lcenter   = luminance(tex2Dlod(source, float4(coord0.xy, 0, 0)).rgb);
	float Lleft     = luminance(tex2Dlod(source, float4(offset[0].xy, 0, 0)).rgb);
	float Ltop      = luminance(tex2Dlod(source, float4(offset[0].zw, 0, 0)).rgb);
	float Lright    = luminance(tex2Dlod(source, float4(offset[1].xy, 0, 0)).rgb);
	float Lbottom   = luminance(tex2Dlod(source, float4(offset[1].zw, 0, 0)).rgb);
	float Lleftleft = luminance(tex2Dlod(source, float4(offset[2].xy, 0, 0)).rgb);
	float Ltoptop   = luminance(tex2Dlod(source, float4(offset[2].zw, 0, 0)).rgb);

	float4 delta = abs(Lcenter - float4(Lleft, Ltop, Lright, Lbottom));
	float2 edges = step(threshold, delta.xy);
	clip(dot(edges, 1) - 1e-5);

	float2 maxDelta = max(delta.xy, delta.zw);
	maxDelta = max(maxDelta.xx, maxDelta.yy);
	maxDelta = max(maxDelta.xy, abs(float2(Lleft, Ltop) - float2(Lleftleft, Ltoptop)));

	return float4(edges * step(maxDelta * 0.5, delta.xy), 0.0, 0.0);
}

float4 SMAABlendingWeightCalculationVS(
	in float4 Position : POSITION,
	in float4 Texcoord : TEXCOORD,
	out float4 oTexcoord0 : TEXCOORD0,
	out float4 oTexcoord1 : TEXCOORD1,
	out float4 oTexcoord2 : TEXCOORD2,
	out float4 oTexcoord3 : TEXCOORD3) : POSITION
{   
	float2 coord = Texcoord.xy + ViewportOffset;
	oTexcoord0 = coord.xyxy * float4(1.0, 1.0, ViewportSize);
	oTexcoord1 = coord.xyxy + ViewportOffset2.xyxy * float4(-0.25, -0.125,  1.25, -0.125);
	oTexcoord2 = coord.xyxy + ViewportOffset2.xyxy * float4(-0.125, -0.25, -0.125,  1.25);
	oTexcoord3 = float4(oTexcoord1.xz, oTexcoord2.yw) + ViewportOffset2.xxyy * float4(-2.0, 2.0, -2.0, 2.0) * float(SMAA_MAX_SEARCH_STEPS);
	return Position;
}

float4 SMAABlendingWeightCalculationPS(
	in float4 coord0 : TEXCOORD0,
	in float4 coord1 : TEXCOORD1,
	in float4 coord2 : TEXCOORD2,
	in float4 coord3 : TEXCOORD3,
	uniform float4 subsampleIndices) : COLOR
{
	float4 weights = 0;
	float4 offset[3] = { coord1, coord2, coord3 };
	float2 edge = tex2Dlod(SMAAEdgeMapSamp, float4(coord0.xy, 0, 0)).rg;

	clip(dot(edge, 1) - 1e-5);

	[branch]
	if (edge.g > 0.0)
	{
#if SMAA_MAX_SEARCH_STEPS_DIAG
		weights.rg = SMAACalculateDiagWeights(SMAAEdgeMapSamp, SMAAAreaMapSamp, coord0.xy, edge, subsampleIndices);

		[branch]
		if (dot(weights.rg, 1.0) == 0.0) 
		{
#endif
		
		float3 coords;
		coords.x = SMAASearchXLeft(SMAAEdgeMapSamp, SMAASearchMapSamp, offset[0].xy, offset[2].x);
		coords.y = offset[1].y;
		coords.z = SMAASearchXRight(SMAAEdgeMapSamp, SMAASearchMapSamp, offset[0].zw, offset[2].y);
		
		float2 d = coords.xz;
		d = abs(round(madd(ViewportSize.xx, d, -coord0.zz)));
		
		float e1 = tex2Dlod(SMAAEdgeMapSamp, float4(coords.xy, 0, 0)).r;
		float e2 = tex2Dlod(SMAAEdgeMapSamp, float4(coords.zy + float2(ViewportOffset2.x, 0), 0, 0)).r;
		
		weights.rg = SMAAArea(SMAAAreaMapSamp, sqrt(d), e1, e2, subsampleIndices.y);
		
		coords.y = coord0.y;
		SMAADetectHorizontalCornerPattern(SMAAEdgeMapSamp, weights.rg, coords.xyzy, d);
		
#if SMAA_MAX_SEARCH_STEPS_DIAG
		} 
		else
		{
			edge.r = 0.0;
		}
#endif
	}

	[branch]
	if (edge.r > 0.0)
	{
		float3 coords;
		coords.y = SMAASearchYUp(SMAAEdgeMapSamp, SMAASearchMapSamp, offset[1].xy, offset[2].z);
		coords.x = offset[0].x;
		coords.z = SMAASearchYDown(SMAAEdgeMapSamp, SMAASearchMapSamp, offset[1].zw, offset[2].w);
		
		float2 d = coords.yz;
		d = abs(round(madd(ViewportSize.yy, d, -coord0.ww)));

		float e1 = tex2Dlod(SMAAEdgeMapSamp, float4(coords.xy, 0, 0)).g;
		float e2 = tex2Dlod(SMAAEdgeMapSamp, float4(coords.xz + float2(0, ViewportOffset2.y), 0, 0)).g;
		
		weights.ba = SMAAArea(SMAAAreaMapSamp, sqrt(d), e1, e2, subsampleIndices.x);
		
		coords.x = coord0.x;
		SMAADetectVerticalCornerPattern(SMAAEdgeMapSamp, weights.ba, coords.xyxz, d);
	}

	return weights;
}

float4 SMAANeighborhoodBlendingVS(
	in float4 Position : POSITION,
	in float4 Texcoord : TEXCOORD,
	out float4 oTexcoord0 : TEXCOORD0,
	out float4 oTexcoord1 : TEXCOORD1) : POSITION
{
	float2 coord = Texcoord.xy + ViewportOffset;
	oTexcoord0 = coord.xyxy;
	oTexcoord1 = coord.xyxy + ViewportOffset2.xyxy * float4(1.0, 0.0, 0.0, 1.0);
	return Position;
}

float4 SMAANeighborhoodBlendingPS(
	in float2 coord0 : TEXCOORD0,
	in float4 coord1 : TEXCOORD1,
	uniform sampler source) : COLOR
{
	float4 a;
	a.x = tex2Dlod(SMAABlendMapSamp, float4(coord1.xy, 0, 0)).a;
	a.y = tex2Dlod(SMAABlendMapSamp, float4(coord1.zw, 0, 0)).g;
	a.wz = tex2Dlod(SMAABlendMapSamp, float4(coord0, 0, 0)).xz;

	[branch]
	if (dot(a, 1) < 1e-5) 
	{
		float4 color = tex2Dlod(source, float4(coord0, 0, 0));
		return float4(color.rgb, 1);
	}
	else 
	{
		bool h = max(a.x, a.z) > max(a.y, a.w);

		float4 blendingOffset = float4(0.0, a.y, 0.0, a.w);
		float2 blendingWeight = a.yw;
		SMAAMovc(bool4(h, h, h, h), blendingOffset, float4(a.x, 0.0, a.z, 0.0));
		SMAAMovc(bool2(h, h), blendingWeight, a.xz);
		blendingWeight /= dot(blendingWeight, 1);

		float4 color = 0;
		color += blendingWeight.x * tex2Dlod(source, float4(coord0 + ViewportOffset2 * blendingOffset.xy, 0, 0));
		color += blendingWeight.y * tex2Dlod(source, float4(coord0 - ViewportOffset2 * blendingOffset.zw, 0, 0));

		return float4(color.rgb, 1);
	}
}

float Script : STANDARDSGLOBAL <
	string ScriptOutput = "color";
	string ScriptClass  = "scene";
	string ScriptOrder  = "postprocess";
> = 0.8;

const float4 ClearColor  = float4(0,0,0,0);
const float ClearDepth  = 1.0;

technique SMAA <
	string Script = 
	"RenderColorTarget0=ScnMap;"
	"RenderDepthStencilTarget=DepthBuffer;"
	"ClearSetColor=ClearColor;"
	"ClearSetDepth=ClearDepth;"
	"Clear=Color;"
	"Clear=Depth;"
	"ScriptExternal=Color;"

	"RenderColorTarget=SMAAEdgeMap;"
	"Clear=Color;"
	"Pass=SMAAEdgeDetection;"

	"RenderColorTarget=SMAABlendMap;"
	"Clear=Color;"
	"Pass=SMAABlendingWeightCalculation;"

	"RenderColorTarget=;"
	"RenderDepthStencilTarget=;"
	"Clear=Color;"
	"Pass=SMAANeighborhoodBlending;"
;> {
	pass SMAAEdgeDetection < string Script= "Draw=Buffer;"; > {
		AlphaBlendEnable = false; AlphaTestEnable = false;
		ZEnable = false; ZWriteEnable = false;
		VertexShader = compile vs_3_0 SMAAEdgeDetectionVS();
		PixelShader  = compile ps_3_0 SMAALumaEdgeDetectionPS(ScnSamp);
	}
	pass SMAABlendingWeightCalculation < string Script= "Draw=Buffer;"; > {
		AlphaBlendEnable = false; AlphaTestEnable = false;
		ZEnable = false; ZWriteEnable = false;
		VertexShader = compile vs_3_0 SMAABlendingWeightCalculationVS();
		PixelShader  = compile ps_3_0 SMAABlendingWeightCalculationPS(float4(0, 0, 0, 0));
	}
	pass SMAANeighborhoodBlending < string Script= "Draw=Buffer;"; > {
		AlphaBlendEnable = false; AlphaTestEnable = false;
		ZEnable = false; ZWriteEnable = false;
		VertexShader = compile vs_3_0 SMAANeighborhoodBlendingVS();
		PixelShader  = compile ps_3_0 SMAANeighborhoodBlendingPS(ScnSamp);
	}
}