// Max Player "Enhance" - a single-pass, GPU-friendly picture booster:
// gentle unsharp masking + contrast + vibrance. Runs in the SCALED hook
// (the frame is already RGB there, and mpv has tone-mapped HDR for us, so
// the pass is safe for SDR and HDR sources alike). Cheap enough for
// real-time playback on phone GPUs - the same role "AI enhance" sliders
// play in gallery players, without the power drain.
//
// Tuning: raise SHARPNESS for a crisper look, CONTRAST/SATURATION closer to
// 1.0 for a subtler one.

//!HOOK SCALED
//!BIND HOOKED
//!DESC Max Player Enhance (sharpen + contrast + vibrance)

#define SHARPNESS  0.35
#define CONTRAST   1.05
#define SATURATION 1.10

vec4 hook()
{
    vec4 c = HOOKED_tex(HOOKED_pos);
    vec3 blur = (HOOKED_texOff(vec2(-1.0,  0.0)).rgb +
                 HOOKED_texOff(vec2( 1.0,  0.0)).rgb +
                 HOOKED_texOff(vec2( 0.0, -1.0)).rgb +
                 HOOKED_texOff(vec2( 0.0,  1.0)).rgb) * 0.25;
    vec3 hi = c.rgb - blur;

    // Contrast-adaptive amount: strong edges get almost no extra boost, so
    // no white halos or ringing on outlines; flat textures get the most.
    float edge = max(abs(hi.r), max(abs(hi.g), abs(hi.b)));
    float k = SHARPNESS / (1.0 + edge * 24.0);
    vec3 col = max(c.rgb + hi * k, vec3(0.0));

    // Slight mid-point contrast...
    col = (col - vec3(0.5)) * CONTRAST + vec3(0.5);
    // ...and a soft vibrance (saturation around luma).
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(luma), col, SATURATION);

    return vec4(max(col, vec3(0.0)), c.a);
}
