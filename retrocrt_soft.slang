#version 450

// retrocrt_soft.slang - Pass 0
// Port of the user's WebGL CRT pipeline for RetroArch Slang.
// Visual target: soft CRT / pixel-art look with scanlines, mild blur and contrast.

layout(push_constant) uniform Push
{
    float blurAmount;
    float scanlineStrength;
    float scanlineFrequency;
    float contrast;
    float brightness;
    float horizontalSoftness;
    float horizontalStretch;
} params;

#pragma parameter blurAmount "CRT blur" 7.0 0.0 12.0 0.25
#pragma parameter scanlineStrength "Scanline strength" 0.65 0.0 1.0 0.01
#pragma parameter scanlineFrequency "Scanline frequency" 120.0 1.0 300.0 1.0
#pragma parameter contrast "CRT contrast" 1.20 0.50 1.60 0.01
#pragma parameter brightness "CRT brightness" 1.00 0.50 1.50 0.01
#pragma parameter horizontalSoftness "Horizontal softness" 1.0 0.0 1.0 0.01
#pragma parameter horizontalStretch "Beam horizontal spread" 3.0 0.0 6.0 0.25

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

const float PI = 3.14159265358979323846;

vec3 sampleBlur(vec2 uv)
{
    vec2 texel = global.SourceSize.zw;

    // Exact 5x5 weights from the supplied WebGL shader.
    const float weights[25] = float[25](
        0.003, 0.013, 0.022, 0.013, 0.003,
        0.013, 0.059, 0.097, 0.059, 0.013,
        0.022, 0.097, 0.159, 0.097, 0.022,
        0.013, 0.059, 0.097, 0.059, 0.013,
        0.003, 0.013, 0.022, 0.013, 0.003
    );

    float phase = abs(sin(uv.y * params.scanlineFrequency * PI));
    float xStretch = 1.0 + params.horizontalSoftness * phase * params.horizontalStretch * 0.20;

    vec3 color = vec3(0.0);
    float sum = 0.0;
    int k = 0;

    for (int y = -2; y <= 2; ++y)
    {
        for (int x = -2; x <= 2; ++x)
        {
            float weight = weights[k++];
            vec2 offset = vec2(
                float(x) * texel.x * params.blurAmount * xStretch,
                float(y) * texel.y * params.blurAmount
            );

            color += texture(Source, uv + offset).rgb * weight;
            sum += weight;
        }
    }

    return color / max(sum, 1e-6);
}

vec3 applyScanlines(vec3 color, vec2 uv)
{
    float scan = sin(uv.y * params.scanlineFrequency * PI);
    float effect = 1.0 - (params.scanlineStrength * params.scanlineStrength) * scan;
    return color * effect;
}

void main()
{
    vec2 uv = vTexCoord;

    vec3 color = sampleBlur(uv);
    color = applyScanlines(color, uv);

    // Same contrast model as the original WebGL code:
    // mix(0.5, color, contrast).
    color = mix(vec3(0.5), color, params.contrast);
    color *= params.brightness;

    FragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
