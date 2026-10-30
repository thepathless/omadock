#version 440
// Specular glass surface for the dock card: the light a sheet of glass picks
// up at its edges and across its face, painted over the card's fill and under
// the icons.
//
// It is a light layer, not a fill: the fill (and the compositor's blur behind
// it) stays the dock's own background. The shader adds
//   - a broad sheen that falls off from the top edge, the way light lands on
//     the upper face of a thick pane,
//   - a bright inner line along the top edge and a softer one along the
//     bottom, the specular rim a rounded glass edge throws back,
//   - a little extra light in the top corners, where the two edges meet.
//
// The card's rounded rectangle is cut out with a signed distance, so the
// highlights follow the corners instead of stopping at a square edge.
//
// Rebuild after editing:
//   /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 \
//     -o glass.frag.qsb glass.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float strength;   // 0..1, the look's glass amount
    float radius;     // card corner radius, logical px
    vec2 size;        // card size, logical px
};

float roundedBox(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - halfSize + vec2(r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    vec2 halfSize = size * 0.5;
    float d = roundedBox(p - halfSize, halfSize, min(radius, min(size.x, size.y) * 0.5));
    // Coverage of the rounded shape, antialiased by one pixel.
    float cover = clamp(0.5 - d, 0.0, 1.0);
    if (cover <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    float y = clamp(p.y / max(size.y, 1.0), 0.0, 1.0);
    float x = clamp(p.x / max(size.x, 1.0), 0.0, 1.0);

    // Broad sheen: strongest at the top, gone by about a third of the height.
    float sheen = (1.0 - smoothstep(0.0, 0.35, y)) * 0.05 + 0.008;

    // Specular rim inside the edge: a hairline along the top, a fainter one
    // along the bottom, both inside the card's own 0.5 px rim.
    float topLine = 1.0 - smoothstep(0.0, 0.022, y);
    float bottomLine = smoothstep(0.978, 1.0, y);
    float rim = topLine * 0.26 + bottomLine * 0.10;

    // Corner light, where the top edge curves away.
    float corner = (1.0 - smoothstep(0.0, 0.08, min(x, 1.0 - x))) * topLine * 0.05;

    // Fade the whole layer out towards the side edges, so the rim reads as a
    // line rather than a wash over the icons' margin.
    float edgeFade = smoothstep(0.0, 1.5, -d);

    float a = clamp((sheen + rim + corner) * strength * edgeFade, 0.0, 1.0) * cover * qt_Opacity;
    fragColor = vec4(vec3(1.0) * a, a);
}
