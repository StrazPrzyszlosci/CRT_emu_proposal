#version 450

// retrocrt_finish.slang - Pass 1
// Approximates the user's post-processing sequence:
// adaptive horizontal blur, detail enhancement, unsharp mask,
// Gaussian softening and final edge smoothing.

layout(push_constant) uniform Push
{
    float detailStrength;
    float unsharpAmount;
    float unsharpThreshold;
    float gaussianBlend;
    float edgeSmoothAmount;
    float horizontalBlur;
} params;

#pragma parameter detailStrength "Detail enhancement" 0.50 0.0 1.0 0.01
#pragma parameter unsharpAmount "Unsharp amount" 0.80 0.0 1.50 0.01
#pragma parameter unsharpThreshold "Unsharp threshold" 2.0 0.0 16.0 1.0
#pragma parameter gaussianBlend "Gaussian softness" 0.35 0.0 1.0 0.01
#pragma parameter edgeSmoothAmount "Edge smoothing" 0.75 0.0 1.0 0.01
#pragma parameter horizontalBlur "Horizontal blur" 0.70 0.0 1.0 0.01

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

vec3 sampleH(vec2 uv)
{
    vec2 dx = vec2(global.SourceSize.z * 2.0 * params.horizontalBlur, 0.0);

    vec3 a = texture(Source, uv - dx).rgb;
    vec3 b = texture(Source, uv).rgb;
    vec3 c = texture(Source, uv + dx).rgb;

    return (a + 2.0 * b + c) * 0.25;
}

vec3 sample9Gaussian(vec2 uv)
{
    vec2 t = global.SourceSize.zw;

    vec3 sum = vec3(0.0);

    sum += texture(Source, uv + vec2(-t.x, -t.y)).rgb;
    sum += texture(Source, uv + vec2( 0.0, -t.y)).rgb * 2.0;
    sum += texture(Source, uv + vec2( t.x, -t.y)).rgb;

    sum += texture(Source, uv + vec2(-t.x,  0.0)).rgb * 2.0;
    sum += texture(Source, uv).rgb * 4.0;
    sum += texture(Source, uv + vec2( t.x,  0.0)).rgb * 2.0;

    sum += texture(Source, uv + vec2(-t.x, t.y)).rgb;
    sum += texture(Source, uv + vec2( 0.0, t.y)).rgb * 2.0;
    sum += texture(Source, uv + vec2( t.x, t.y)).rgb;

    return sum / 16.0;
}

vec3 detailEnhanced(vec2 uv, vec3 base)
{
    vec2 t = global.SourceSize.zw;

    vec3 top    = texture(Source, uv + vec2(0.0, -t.y)).rgb;
    vec3 bottom = texture(Source, uv + vec2(0.0,  t.y)).rgb;
    vec3 left   = texture(Source, uv + vec2(-t.x, 0.0)).rgb;
    vec3 right  = texture(Source, uv + vec2( t.x, 0.0)).rgb;

    vec3 laplace = 4.0 * base - top - bottom - left - right;

    return base + laplace * (0.20 * params.detailStrength);
}

vec3 edgeSmoothed(vec2 uv)
{
    vec2 t = global.SourceSize.zw;
    vec3 sum = vec3(0.0);

    for (int y = -1; y <= 1; ++y)
    {
        for (int x = -1; x <= 1; ++x)
        {
            sum += texture(Source, uv + vec2(float(x) * t.x, float(y) * t.y)).rgb;
        }
    }

    return sum / 9.0;
}

void main()
{
    vec2 uv = vTexCoord;

    vec3 horizontal = sampleH(uv);
    vec3 detail = detailEnhanced(uv, horizontal);

    // Mild 4-neighbour unsharp approximation.
    vec2 t = global.SourceSize.zw;
    vec3 north = texture(Source, uv + vec2(0.0, -t.y)).rgb;
    vec3 south = texture(Source, uv + vec2(0.0,  t.y)).rgb;
    vec3 west  = texture(Source, uv + vec2(-t.x, 0.0)).rgb;
    vec3 east  = texture(Source, uv + vec2( t.x, 0.0)).rgb;

    vec3 unsharp = detail * 5.0 - north - south - west - east;

    // WebGL applyUnsharpMask only sharpens where |orig - blur| exceeds the
    // threshold (per channel, 0-255 domain), so flat areas stay untouched.
    vec3 soft = (north + south + west + east) * 0.25;
    vec3 gate = step(vec3(params.unsharpThreshold / 255.0), abs(detail - soft));
    vec3 sharpened = mix(detail, unsharp, gate * (0.20 * params.unsharpAmount));

    // User's final Gaussian blur + edge smoothing were both smoothing operations.
    vec3 gaussian = sample9Gaussian(uv);
    vec3 softened = mix(sharpened, gaussian, params.gaussianBlend);

    vec3 smoothed = edgeSmoothed(uv);
    vec3 finalColor = mix(softened, smoothed, params.edgeSmoothAmount);

    FragColor = vec4(clamp(finalColor, 0.0, 1.0), 1.0);
}
