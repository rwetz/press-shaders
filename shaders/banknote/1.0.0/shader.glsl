// Banknote Engraving: the photo as an intaglio print. Engraved lines that
// thicken with the dark and bend with the forms, guilloche waves over smooth
// skies, cross-hatched shadows, paper grain, and one hue kept as an accent ink.
//
// Recreates Figma's "Banknote Engraving" effect, with the same controls in
// the same order. The tone curve (ink covers ~12% of the paper in highlights,
// ~85% in shadows) was fitted to Figma's own renders; see bench/. Shadows have
// since been capped below 78% so they stay line-built, with the midtones
// raised to keep the mean tone. Controls are in shader.json.

uniform vec3 uInk, uPaper, uAccent;
uniform float uPreserve, uHue, uTol, uFeather, uMinSat, uAccStr, uKeepSh, uPreviewMask;
uniform int uAccMode, uPlace;
uniform float uSpacing, uWeight, uAngle, uFlow, uCross, uGStr, uUpper, uGScale, uGCurves;
uniform float uExposure, uContrast, uDetail, uGrain, uWash, uTint, uEdge, uEdgeDetail;
uniform float uWater, uFacade, uFoliage, uOpen, uContour, uSimplify;

float lum(vec3 c){ return dot(c, vec3(.299,.587,.114)); }
vec3 rgb2hsv(vec3 c){
  vec4 K = vec4(0.,-1./3.,2./3.,-1.);
  vec4 p = mix(vec4(c.bg,K.wz), vec4(c.gb,K.xy), step(c.b,c.g));
  vec4 q = mix(vec4(p.xyw,c.r), vec4(c.r,p.yzx), step(p.x,c.r));
  float d = q.x - min(q.w,q.y); float e = 1e-10;
  return vec3(abs(q.z + (q.w-q.y)/(6.*d+e)), d/(q.x+e), q.x);
}
vec3 hsv2rgb(vec3 c){ vec3 p = abs(fract(c.xxx + vec3(1.,2./3.,1./3.))*6.-3.); return c.z*mix(vec3(1.), clamp(p-1.,0.,1.), c.y); }
float hash(vec2 p){ p = fract(p*vec2(123.34,456.21)); p += dot(p, p+45.32); return fract(p.x*p.y); }
float vnoise(vec2 p){
  vec2 i = floor(p), f = fract(p); f = f*f*(3.-2.*f);
  return mix(mix(hash(i), hash(i+vec2(1,0)), f.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), f.x), f.y);
}
// Ink coverage of a family of parallel lines along v (one line per unit), each covering w of
// its period. Box-filtered over the pixel's footprint, so tone stays exact even when lines
// are finer than a pixel.
float inkUpTo(float a, float w){ return floor(a)*w + clamp(fract(a) - .5 + w*.5, 0., w); }
float linesF(float v, float w, float f){
  f = max(f, 1e-4);
  return (inkUpTo(v + .5*f, w) - inkUpTo(v - .5*f, w))/f;
}
float lines(float v, float w){ return linesF(v, w, fwidth(v)); }
// The same family with alternate lines thinned: odd lines take r of the even ones' width, so
// as r falls the pitch opens toward double while the total ink stays w. Built from two
// families at twice the pitch (each covering its share of that pitch), so it is box-filtered
// too, and the two never overlap.
float lines2(float v, float w, float r){
  float we = w/(1. + r);
  return lines(v*.5, we) + lines(v*.5 + .5, w - we);
}
// Breaks along each line of a family (v across it, s along it, both in pitches): dashes
// covering d of their length, staggered from line to line by the golden ratio and drifting
// with smooth noise. The phase is continuous in v, not keyed to a line's index: where lines
// bend across an edge the index changes, and the breaks would line up there into a seam.
// Filtered by the footprint along the line only: the stagger changes fast across lines,
// but a dash is never seen across them.
float dashes(float v, float s, float d, vec2 p){
  return linesF(s/3. + v*.618 + vnoise(p)*1.5, d, fwidth(s/3.));
}
mat2 rot(float a){ float c = cos(a), s = sin(a); return mat2(c,-s,s,c); }
// Luminance of the photo blurred over about r units (thousandths of the short side), from
// its mip chain: 8 taps on a ring around a centre tap, each at the level for r/2.
float ringLum(vec2 uv, float r){
  vec2 k = r*min(uRes.x, uRes.y)/1000./uRes;   // r units in uv
  float lod = max(log2(r*.5*uTexMin/1000.), 0.);
  float s = lum(textureLod(uImg, uv, lod).rgb)*2.;
  for (int i = 0; i < 8; i++) {
    float a = float(i)*.7854;
    s += lum(textureLod(uImg, uv + vec2(cos(a), sin(a))*k, lod).rgb);
  }
  return s/10.;
}
// uFollow at uv with a cubic B-spline over its coarse grid, so the lines' direction changes
// smoothly instead of kinking at every grid cell.
vec4 bspline(float t){ float t2 = t*t, t3 = t2*t, u = 1.-t; return vec4(u*u*u, 3.*t3-6.*t2+4., -3.*t3+3.*t2+3.*t+1., t3)/6.; }
// The photo's luminance simplified over about r units, keeping its edges: a bilateral filter
// over two rings of taps from the mip chain, each weighted by how near its luminance is to
// the centre's (itself read lightly blurred, so noise doesn't pick the weights). Grain,
// compression blocks and busy reflections even out into masses; an edge, whose far side
// differs by much more than s, stays sharp.
float cleanLum(vec2 uv, float r, float s){
  vec2 k = r*min(uRes.x, uRes.y)/1000./uRes;
  float c = lum(textureLod(uImg, uv, max(log2(r*.3*uTexMin/1000.), 0.)).rgb);
  float lod = max(log2(r*.4*uTexMin/1000.), 0.);
  float sum = c, wsum = 1.;
  for (int i = 0; i < 16; i++) {
    float a = float(i)*.7854 + (i < 8 ? .3927 : 0.);
    float L = lum(textureLod(uImg, uv + vec2(cos(a), sin(a))*k*(i < 8 ? .5 : 1.), lod).rgb);
    float w = exp(-(L - c)*(L - c)/(2.*s*s));
    sum += w*L;
    wsum += w;
  }
  return sum/wsum;
}
// Gradient of the forms blur (uBlur.g) per unit, by central differences 2 units apart;
// k is one unit in uv.
vec2 formGrad(vec2 p, vec2 k){
  return vec2(texture(uBlur, p + vec2(2.*k.x, 0)).g - texture(uBlur, p - vec2(2.*k.x, 0)).g,
              texture(uBlur, p + vec2(0, 2.*k.y)).g - texture(uBlur, p - vec2(0, 2.*k.y)).g)*.25;
}
vec2 follow(vec2 uv){
  ivec2 n = textureSize(uFollow, 0);
  vec2 p = uv*vec2(n) - .5, f = fract(p);
  ivec2 i = ivec2(floor(p)) - 1;
  vec4 wx = bspline(f.x), wy = bspline(f.y);
  vec2 s = vec2(0);
  for (int y = 0; y < 4; y++) for (int x = 0; x < 4; x++)
    s += wx[x]*wy[y]*texelFetch(uFollow, clamp(i + ivec2(x, y), ivec2(0), n - 1), 0).rg;
  return s;
}

void main(){
  vec2 uv = vUv;
  vec3 src = texture(uImg, uv).rgb;

  // Pattern space: 1 unit = 1/1000 of the short side, so preview and export match.
  float unit = min(uRes.x, uRes.y)/1000.;
  vec2 size = uRes/unit;
  vec2 q = vec2(uv.x, 1.-uv.y)*size;

  // The host's analysis: luminance at four blur scales, and smooth measures of edge slope
  // and texture. All of it varies slowly, so lines never jump between neighbouring pixels.
  vec4 B = texture(uBlur, uv);    // r texture, g forms, b shapes, a broad relief
  vec4 F = texture(uField, uv);   // r slope of the relief per unit (x20), g texture (x2)
  float Lm = B.g;
  // Smooth areas (sky, water, cloud) differ little between blur levels.
  float smoothR = 1. - smoothstep(.02, .07, F.g*.5);

  // Tone: exposure, local-contrast boost so detail survives the line screen, then contrast.
  // The boost is measured between two blurs, never from single pixels, so it lifts small
  // things without amplifying the photo's noise into line-width flicker.
  // The tone is read from the simplified photo, so marks follow masses, not grain; the
  // outlines below still read the original.
  float L = uSimplify > 0. ? cleanLum(uv, 1. + 6.*uSimplify, .05 + .05*uSimplify) : lum(src);
  L += uDetail*(B.r - Lm);
  L *= exp2(uExposure);
  L = clamp((L-.5)*uContrast + .5, 0., 1.);
  float t = 1.-L;
  // Share of the paper the ink covers. A hairline remains in the highlights and the shadows
  // never fill in solid, so it runs ~8% to under 78% (capped below). It stays low through the light
  // tones, so skies and sunlit walls read as paper with fine lines, as in an engraving.
  float cover = clamp(.065 + uWeight*.815*pow(t, 1.25), 0., 1.);

  // Noise is scaled to the line pitch, never finer, so it can't alias into speckle.
  vec2 qp = q/uSpacing;
  float n = vnoise(qp*.35)*.5 + vnoise(qp*.8)*.3 + vnoise(qp*1.9)*.2;
  vec3 paper = uPaper*(1. - uGrain*.07*(n-.35));
  // Paper tint: the photo's own colour, as a pale wash at the paper's lightness (a peach
  // sky, warm stone), so the print keeps the scene's colour without losing tone. Taken broad
  // (about 1/40 of the short side), so it washes regions, not single leaves. It is strongest
  // in the sky and the lit areas, where the paper shows, and faint in the midtones and
  // shadows, where it would only colour the gaps between lines (blue glass, dark foliage).
  vec3 pc = textureLod(uImg, uv, max(log2(uTexMin/40.), 0.)).rgb;
  vec3 hue = pc/max(lum(pc), .04);
  float formL = clamp((B.g*exp2(uExposure) - .5)*uContrast + .5, 0., 1.);
  float bare = max(smoothR*smoothstep(.45, .65, B.b), smoothstep(.45, .8, formL));
  paper *= mix(vec3(1.), clamp(hue, 0., 2.), uTint*mix(.12, .5, bare));

  // Hue accent. The mask reads a lightly blurred photo, so it follows things (a sail, an
  // umbrella), not pixels, and its edges fade instead of speckling.
  vec3 hsv = rgb2hsv(texture(uColor, uv).rgb);
  float hd = abs(mod(hsv.x*360. - uHue + 540., 360.) - 180.);
  float m = (1.-smoothstep(uTol, uTol+uFeather+.001, hd))
          * smoothstep(uMinSat-.08, uMinSat+.08, hsv.y)
          * smoothstep(.06, .15, hsv.z) * uPreserve;
  if (uPreviewMask > .5) { o = vec4(vec3(m),1.); return; }
  // Printed ink: the pixel's hue as a strong, mid-value ink. Original colour: the ink that,
  // at this coverage over this paper, averages back to the photo's colour.
  float c = max(cover, .2);
  vec3 acc = uAccMode==0 ? hsv2rgb(vec3(hsv.x, clamp(hsv.y*1.3,.6,.95), clamp(hsv.z*.8,.3,.6)))
           : uAccMode==1 ? clamp((src*exp2(uExposure) - paper*(1.-c))/c, 0., 1.)
           : uAccent;
  float am = m*uAccStr*(1. - uKeepSh*.6*smoothstep(.75, 1., t));
  vec3 inkCol = mix(uInk, acc, am);
  // A lighter accent ink gets wider lines, so the accent keeps the tone of the photo.
  if (uAccMode != 1) {
    float pl = lum(paper), il = lum(uInk), al = lum(inkCol);
    cover = mix(cover, clamp(cover*(pl-il)/max(pl-al,.05), 0., 1.), am);
  }

  // Wear: phase noise and broken ink turn lines into the short, irregular strokes of a worn
  // intaglio print. Textured areas take it fully; smooth ones (sky, water) keep a trace,
  // where it would only read as noise.
  float wear = uGrain*mix(.3, 1., 1.-smoothR);
  float jitter = ((n-.5)*.3 + (vnoise(qp*vec2(.6,1.2)+3.)-.5)*.25)*wear;

  // Engraving: two families of lines, the second crossing the first at 60 degrees. Each
  // is lifted by the broad relief, so it bends along its contours like sections through the
  // forms, and displaced by the host's follow field, so it turns toward the local edge
  // direction: down a rock face, along a ridge. The lift's slope is capped below 1: past
  // that, lines would fold back on themselves and tear open at edges. Where the relief is
  // steep the lift is scaled down instead, and the cap keeps a margin for the blur of the
  // slope. The lift also stops at 40 units: a larger one varies so much across the image
  // that its own changes add slope the cap can't see.
  float lift = uFlow*min(uSpacing*10., 40.);
  float slope = F.r/20.*1.6;
  lift /= sqrt(1. + (lift*slope/.45)*(lift*slope/.45));
  float flow = lift*(B.a - .5);
  float flowSlope = lift*slope;   // at most .45
  float a2 = uAngle + 1.0472, sp2 = uSpacing*1.1;
  vec2 r1 = rot(uAngle)*q, r2 = rot(a2)*q;
  vec2 fd = uFlow*follow(uv);
  // How much turning narrows each family's spacing budget: the follow field's slope
  // against the family's base normal (pattern space runs y down, the screen y up).
  vec2 g1 = vec2(dFdx(fd.x), -dFdy(fd.x))*unit, g2 = vec2(dFdx(fd.y), -dFdy(fd.y))*unit;
  float turn1 = max(-dot(g1, vec2(-sin(uAngle), cos(uAngle))), 0.);
  float turn2 = max(-dot(g2, vec2(-sin(a2), cos(a2))), 0.);
  // Fine relief: the lines also ripple with the texture-scale relief (waves on water,
  // folds in rock), by under a pitch, and only as far as the slope the lift and the
  // turning leave free. Its slope comes from the smoothed field, with the same margin.
  float fineAmp = uFlow*uSpacing*.6;
  float fineGrad = F.b/20.*1.6;
  fineAmp = min(fineAmp, max(.6 - flowSlope - max(turn1, turn2), 0.)/max(fineGrad, 1e-4));
  float fine = fineAmp*(B.g - B.b);
  flowSlope += fineAmp*fineGrad;

  // Guilloche: over smooth areas both families ripple into deep, even arcs, and the two
  // cross in a regular net of lens-shaped cells, as on a banknote's sky. Their phase drifts
  // a little, so the net rolls in broad bands without breaking into moiré. Only light smooth areas (sky,
  // haze) take it; dark smooth ones (sea, forest in shadow) keep engraved lines. In the upper
  // placement it covers the sky and fades out slowly through the haze toward the horizon.
  float mask = uPlace==0 ? smoothR*(1.-smoothstep(uUpper-.15, uUpper+.25, 1.-uv.y))*smoothstep(.45, .65, B.b)
             : uPlace==1 ? smoothR*smoothstep(.45, .65, B.b) : 1.;
  // Subject: the engraver changes the kind of mark with what is drawn. From the host's
  // analysis, each pixel gets a weight for three subjects, all smooth so the marks blend
  // instead of switching. Structure comes from the orientation tensor of the shapes:
  // coherence (one clear direction, and enough contrast to trust it) and how much of the
  // gradient runs across, i.e. how upright the edges are.
  vec3 J = texture(uOrient, uv).xyz;
  float jt = J.x + J.z;
  float strong = smoothstep(.002, .02, jt);
  float coh = length(vec2(J.x - J.z, 2.*J.y))/(jt + 1e-6)*strong;
  float upright = J.x/(jt + 1e-6);
  float tex = F.g*.5;
  // Water: little structure at the scale of shapes (buildings, even plain ones, have edges
  // there), darker than the sky, away from the guilloche's net and below the top of the frame.
  float wWater = uWater*(1. - smoothstep(.1, .5, strong))*smoothstep(.25, .45, t)*(1. - mask)*smoothstep(.2, .4, 1.-uv.y);
  // Facades, columns, statues: clear upright edges in a textured area, not in the sky.
  float wFacade = uFacade*smoothstep(.3, .6, coh)*smoothstep(.65, .85, upright)*(1. - smoothR)*(1. - mask)*(1. - wWater);
  // Foliage: busy texture with no clear direction, in the mid and dark tones, and green.
  // The hue gate keeps window grids and rubble out of it.
  float green = 1. - smoothstep(35., 65., abs(hsv.x*360. - 105.));
  float wFoliage = uFoliage*smoothstep(.015, .04, tex)*(1. - smoothstep(.25, .55, coh))
                 *green*smoothstep(.1, .3, hsv.y)*smoothstep(.15, .3, t)*(1. - wWater);

  float lam = uGScale*.065;
  const float drift = .9;
  // A wave's slope across its lines comes from its drift and, where the lines are tilted
  // or turned off their base direction, from its own crests, which then point partly
  // across them. It gets only the slope the flow and the turning leave free, so together
  // they stay below the fold.
  float amp = mask*uGStr*uGCurves*.05;
  float tilt1 = flowSlope + abs(dot(g1, vec2(cos(uAngle), sin(uAngle))));
  float tilt2 = flowSlope + abs(dot(g2, vec2(cos(a2), sin(a2))));
  float ws1 = drift/(lam*30.) + .6/uSpacing*flowSlope + tilt1/lam;
  float ws2 = drift/(lam*30.) + .6/sp2*flowSlope + tilt2/lam;
  float amp1 = min(amp, max(.75 - flowSlope - turn1, 0.)/ws1);
  float amp2 = min(amp, max(.75 - flowSlope - turn2, 0.)/ws2);
  // Where the amplitude itself changes (the guilloche fading in at its mask's edge) that
  // change is slope too; take it out of the budget as well.
  float da1 = length(vec2(dFdx(amp1), dFdy(amp1)))*unit, da2 = length(vec2(dFdx(amp2), dFdy(amp2)))*unit;
  amp1 = min(amp1, max(.75 - flowSlope - turn1 - da1, 0.)/ws1);
  amp2 = min(amp2, max(.75 - flowSlope - turn2 - da2, 0.)/ws2);
  float wave1 = amp1*sin(r1.x/lam + drift*sin(r1.y/(lam*30.) + r1.x/(lam*45.)) + flow/uSpacing*.6);
  float wave2 = amp2*sin(r2.x/lam + drift*sin(r2.y/(lam*30.) + r2.x/(lam*45.) + 1.7) + flow/sp2*.6);
  float V1 = r1.y + flow + fine + fd.x + wave1;
  float V2 = r2.y + flow + fine + fd.y + wave2;

  // Shadows take extra ink with the cross-hatch, as much as a separate 60-degree set laid
  // over the lines used to add: the tone curve and defaults were fitted with it.
  float thr = 1. - uCross*.6;
  float deep = clamp((t-thr)/max(1.-thr, .01), 0., 1.)*uWeight*.8*step(.001, uCross);
  cover = 1. - (1. - cover)*(1. - deep);
  // Shadows stay built from lines: past ~78% the gaps between crossing lines close up and
  // a dark mass prints as a solid block, so the cover eases into that ceiling instead.
  cover = min(cover, .78 - .1*exp(-max(cover - .68, 0.)*10.));
  // The ink is shared between the families so the two together cover exactly `cover`:
  // the second takes a share of the width an even split would give it, from the midtones
  // down and wherever the guilloche nets the sky, and the first covers what remains. Away
  // from the net the crossing lines stay the finer of the two, so one family leads.
  // Ink wash: in the deep shadows only, part of the tone prints as a faint flat tint of the
  // ink under the lines, so the darkest masses hold together. The lines carry the rest:
  // wash and lines together still cover exactly `cover`. Everywhere else the tone is all
  // line, as in an engraving: sunlit walls are paper, midtones open hatching.
  float lit = 1. - smoothstep(.2, .55, t);
  float wash = uWash*cover*smoothstep(.55, .9, t);
  float lineCover = 1. - (1. - cover)/(1. - wash);
  // In the shadows the crossing family takes an even share, so the dark reads as a true
  // cross-hatch with open diamonds instead of one family's lines swelling shut.
  // Under the guilloche the two families weigh the same from half strength up, so its net
  // reads as two crossing sets of lines, not one leading.
  float net = mask*smoothstep(0., .5, uGStr);
  float share = max(uCross*smoothstep(.05, .35, t), net);
  float even = max(net, uCross*smoothstep(.45, .8, t));
  float w2 = share*mix(.6, 1., even)*(1. - sqrt(1. - lineCover));
  float w1 = 1. - (1. - lineCover)/(1. - w2);
  // Open highlights: in the light tones alternate lines thin away, so the spacing opens
  // as well as the width, and the lines break into dashes, then short flicks, toward the
  // paper. Each dashed line is widened by what its breaks take out, so the tone holds.
  // By the midtones (where cover nears 1/2) both are gone. The guilloche's net stays whole.
  // The pattern is chosen from the tone of the forms, not the pixel, so it changes by
  // region; thin bright halos beside dark edges don't strip their lines away.
  float tf = 1. - clamp((B.g*exp2(uExposure) - .5)*uContrast + .5, 0., 1.);
  float open = uOpen*(1. - smoothstep(.15, .55, tf))*(1. - mask);
  // Under the guilloche alternate lines drop out instead: the net prints as two sparser
  // families of firm lines, so its cells read even where the sky is light.
  float alt = (1. - .85*open)*(1. - .9*net);
  float duty = 1. - .5*uOpen*(1. - smoothstep(.08, .45, tf))*(1. - mask);
  float v1 = V1/uSpacing + jitter, v2 = V2/sp2 + jitter;
  float i1 = lines2(v1, min(w1/duty, 1.), alt)*dashes(v1, r1.x/uSpacing, duty, qp*.15);
  float i2 = lines2(v2, min(w2/duty, 1.), alt)*dashes(v2, r2.x/sp2, duty, qp*.15 + 5.);
  float ink = 1. - (1. - i1)*(1. - i2);

  // Each subject's own mark covers the same `lineCover`, so blending marks keeps the tone.
  // Water: one family of level lines that swell with the tone, rippling with the fine relief
  // (its own slope budget, as nothing else bends them) on a slow swell.
  float wAmp = min(uSpacing*1.2, .6/max(fineGrad, 1e-4));
  float Vw = q.y + wAmp*(B.g - B.b) + uSpacing*.35*sin(q.x/(uSpacing*9.) + 1.3*sin(q.y/(uSpacing*14.)));
  ink = mix(ink, lines(Vw/uSpacing + jitter*.5, lineCover), wWater);
  // Facades: fine upright hairlines, crossed by the main family only in the shadows.
  float wb = uCross*smoothstep(.5, .85, t)*(1. - sqrt(1. - lineCover));
  float wa = 1. - (1. - lineCover)/(1. - wb);
  float iFacade = 1. - (1. - lines(q.x/(uSpacing*.8) + jitter*.5, wa))*(1. - lines(V1/uSpacing + jitter, wb));
  ink = mix(ink, iFacade, wFacade);
  // Foliage: stipple, one dot per cell of a staggered grid, its area the cover. Dots stay
  // inside their cells (the jitter only uses the room the dot leaves), and where cells are
  // finer than a couple of pixels the dots give way to their average.
  float cs = uSpacing*1.15;
  vec2 g = q/cs;
  g.x += .5*mod(floor(g.y), 2.);
  vec2 id = floor(g);
  float cov = min(lineCover, .78);
  float rad = sqrt(cov/3.1416);
  vec2 off = (vec2(hash(id), hash(id + 17.3)) - .5)*max(.5 - rad, 0.)*1.2;
  float px = max(fwidth(q.x)/cs, 1e-4);
  float dots = clamp((rad - length(fract(g) - .5 - off))/px + .5, 0., 1.);
  dots = mix(dots, cov, smoothstep(.25, .5, px));
  ink = mix(ink, dots, wFoliage);

  // Outlines: where the photo is darker than its surroundings at a fine scale (a window, a
  // roofline, a mast, the shadow side of an edge), the engraver draws it as a solid line.
  // A difference of two blurs finds it; the response is ramped, so the lines have soft,
  // anti-aliased sides and small differences (noise, haze) draw nothing.
  float er = mix(2.2, 1.1, uEdgeDetail);
  float dog = ringLum(uv, er*2.5) - ringLum(uv, er);
  float edge = smoothstep(.02, .07, dog*exp2(uExposure)*uContrast)*uEdge;
  // Stonework: in the light tones the engraver keeps the surface's own small marks (stone
  // joints, tiles, shutters) as fine strokes. The same comparison at a finer scale, with a
  // lower threshold, drawn thinner (at most half ink), only where the area is lit.
  float fdog = ringLum(uv, er*1.2) - ringLum(uv, er*.45);
  edge = max(edge, smoothstep(.016, .055, fdog*exp2(uExposure)*uContrast)*.55*uEdge*lit);
  // Laid over the lines as ink over ink, not as the darker of the two: where the lines are
  // resolved (0 or 1 per pixel) that is the same thing, but where they are finer than a pixel
  // (a small preview) the darker-of would hide outlines in the lines' average and print the
  // preview lighter than the export.
  ink = 1. - (1. - ink)*(1. - edge);

  // Contours: the engraver draws the edges of shapes (a roofline, a hull, a column, a
  // silhouette against the sky) as one continuous line, on the lit side as well as the dark.
  // The edge sits on the ridge of the shapes blur's gradient: a parabola through the
  // gradient's size at three points across the edge gives the distance to that ridge, so
  // the line is thin and exact though the blur is soft, and only maxima draw (non-maximum
  // suppression). Stronger edges draw wider and darker, so silhouettes come out firm.
  vec2 ku = vec2(unit)/uRes;
  vec2 g0 = formGrad(uv, ku);
  float m0 = length(g0);
  vec2 gn = g0/max(m0, 1e-6);
  const float ce = 1.8;
  float mp = length(formGrad(uv + gn*ku*ce, ku)), mm = length(formGrad(uv - gn*ku*ce, ku));
  float ca = (mp - mm)/(2.*ce), cb = (mp - 2.*m0 + mm)/(ce*ce);
  float cd = cb < 0. ? abs(ca/cb) : 1e3;
  float cs0 = smoothstep(.012, .03, m0*exp2(uExposure)*uContrast);
  float csF = smoothstep(.03, .08, m0*exp2(uExposure)*uContrast);
  // Against the sky (the guilloche's mask reaches the edge) the silhouette is firmer still.
  float sil = smoothstep(.05, .35, mask)*cs0;
  float chw = .3 + .35*csF + .3*sil;
  float contour = clamp((chw - cd)*unit + .5, 0., 1.)*cs0*mix(.75, 1., max(csF, sil))*uContour*(1. - .7*wFoliage);
  ink = 1. - (1. - ink)*(1. - contour);

  // Broken ink, in the midtones only: breaks would erase the highlight hairlines and punch
  // white holes in the shadows.
  float mid = smoothstep(.15, .4, t)*(1. - smoothstep(.7, .9, t));
  ink *= 1. - wear*mid*.35*smoothstep(.6, .95, vnoise(qp*vec2(.5,1.1) + 11.));

  vec3 inked = inkCol*mix(vec3(1.), paper, .1);
  // The wash layers ink like ink does: each channel multiplies, so the midtones turn a
  // clear blue (or whatever the ink is) instead of greying. Its density is solved so the
  // tint is exactly as light as `wash` asks.
  vec3 ratio = max(inked, 1e-3)/max(paper, 1e-3);
  float lr = clamp(lum(inked)/max(lum(paper), 1e-3), 1e-3, .999);
  float dens = log(1. - wash*(1. - lr))/log(lr);
  vec3 tint = paper*pow(ratio, vec3(dens));
  vec3 col = mix(tint, inked, clamp(ink,0.,1.));
  o = vec4(col, 1.);
}
