#version 450

// retrocrt_tone.slang - Pass 2
// Automatic local tone preservation against RetroArch's Original input.
// This is intentionally shader-friendly: unlike the WebGL version, it does
// not attempt a full-frame histogram reduction. It locally preserves the
// source black point, midpoint and contrast while retaining the CRT texture.

layout(push_constant) uniform Push
{
    float autoTone;
    float toneStrength;
    float contrastPreserve;
    float blackProtect;
    float whiteProtect;
} params;

#pragma parameter autoTone "Automatic tone match" 1.0 0.0 1.0 1.0
#pragma parameter toneStrength "Tone match strength" 0.85 0.0 1.0 0.01
#pragma parameter contrastPreserve "Contrast preservation" 0.85 0.0 1.0 0.01
#pragma parameter blackProtect "Black protection" 0.80 0.0 1.0 0.01
#pragma parameter whiteProtect "Highlight protection" 0.80 0.0 1.0 0.01

layout(std140, set = 0, binding = 0) uniform UBO
{
    mat4 MVP;
    vec4 SourceSize;
    vec4 OriginalSize;
    vec4 OutputSize;
} global;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

void main()
{
    gl_Position = global.MVP * Position;
    vTexCoord = TexCoord;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;
layout(set = 0, binding = 1) uniform sampler2D Original;

float luma(vec3 c)
{
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 localMean(sampler2D tex, vec2 uv, vec2 t)
{
    vec3 s = vec3(0.0);

    for (int y = -1; y <= 1; ++y)
    {
        for (int x = -1; x <= 1; ++x)
        {
            s += texture(tex, uv + vec2(float(x) * t.x, float(y) * t.y)).rgb;
        }
    }

    return s / 9.0;
}

float localSpread(sampler2D tex, vec2 uv, vec2 t, float mean)
{
    float s = 0.0;

    for (int y = -1; y <= 1; ++y)
    {
        for (int x = -1; x <= 1; ++x)
        {
            float v = luma(texture(tex, uv + vec2(float(x) * t.x, float(y) * t.y)).rgb);
            s += abs(v - mean);
        }
    }

    return s / 9.0;
}

void main()
{
    vec2 uv = vTexCoord;
    vec2 t = global.SourceSize.zw;

    vec3 current = texture(Source, uv).rgb;
    vec3 original = texture(Original, uv).rgb;

    float currentLum = luma(current);
    float originalLum = luma(original);

    float currentMean = luma(localMean(Source, uv, t));
    float originalMean = luma(localMean(Original, uv, t));

    float currentSpread = max(localSpread(Source, uv, t, currentMean), 0.01);
    float originalSpread = localSpread(Original, uv, t, originalMean);

    // Restore local midpoint and local contrast relative to the original frame.
    float contrastRatio = clamp(originalSpread / currentSpread, 0.60, 1.60);

    float delta = currentLum - currentMean;
    float targetLum = originalMean + delta * mix(1.0, contrastRatio, params.contrastPreserve);

    // Additional direct luminance anchoring makes black/white handling more robust.
    targetLum = mix(targetLum, originalLum, 0.35 * params.toneStrength);

    // Protect blacks from accidental lifting and highlights from excessive clipping.
    float shadowMask = 1.0 - smoothstep(0.0, 0.12, originalLum) * params.blackProtect;
    float highlightMask = smoothstep(0.82, 1.0, originalLum) * params.whiteProtect;

    targetLum = mix(originalLum, targetLum, shadowMask);
    targetLum = mix(targetLum, originalLum, highlightMask * 0.50);

    float matchedLum = mix(currentLum, targetLum, params.autoTone * params.toneStrength);

    // Preserve chromaticity while changing luminance.
    float scale = matchedLum / max(currentLum, 0.0005);
    vec3 outColor = current * scale;

    // Keep numerical overshoot under control.
    outColor = clamp(outColor, 0.0, 1.0);

    FragColor = vec4(outColor, 1.0);
}
