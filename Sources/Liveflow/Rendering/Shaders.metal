#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoords;
};

struct LayerUniforms {
    float4 rect;     // x, y, width, height in normalized [0, 1] on canvas
    float4 cropRect; // u, v, width, height in normalized [0, 1] on source texture
    float opacity;   // 0.0 - 1.0
    float flipY;     // 1.0 = normal, -1.0 = flipped
    float2 padding;
};

vertex VertexOut vertex_main(
    uint vertexID [[vertex_id]],
    constant LayerUniforms &uniforms [[buffer(0)]]
) {
    // 6 vertices for 2 triangles forming a quad
    const float2 positions[6] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(0.0, 1.0),
        float2(1.0, 0.0),
        float2(1.0, 1.0)
    };

    float2 localPos = positions[vertexID];
    float normX = uniforms.rect.x + localPos.x * uniforms.rect.z;
    float normY = uniforms.rect.y + localPos.y * uniforms.rect.w;

    // Convert normalized [0, 1] to Metal NDC [-1, 1] with (0,0) at top-left
    float clipX = normX * 2.0 - 1.0;
    float clipY = 1.0 - normY * 2.0;

    VertexOut out;
    out.position = float4(clipX, clipY, 0.0, 1.0);

    float2 baseUV = (uniforms.flipY > 0.0) ? float2(localPos.x, localPos.y) : float2(localPos.x, 1.0 - localPos.y);
    out.texCoords = uniforms.cropRect.xy + baseUV * uniforms.cropRect.zw;
    return out;
}

fragment float4 fragment_rgba(
    VertexOut in [[stage_in]],
    texture2d<float> colorTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]],
    constant LayerUniforms &uniforms [[buffer(0)]]
) {
    float4 color = colorTexture.sample(textureSampler, in.texCoords);
    return float4(color.rgb, color.a * uniforms.opacity);
}

fragment float4 fragment_nv12(
    VertexOut in [[stage_in]],
    texture2d<float> yTexture [[texture(0)]],
    texture2d<float> uvTexture [[texture(1)]],
    sampler textureSampler [[sampler(0)]],
    constant LayerUniforms &uniforms [[buffer(0)]]
) {
    float y = yTexture.sample(textureSampler, in.texCoords).r;
    float2 uv = uvTexture.sample(textureSampler, in.texCoords).rg - float2(0.5, 0.5);

    // BT.709 color conversion
    float r = y + 1.5748 * uv.y;
    float g = y - 0.1873 * uv.x - 0.4681 * uv.y;
    float b = y + 1.8556 * uv.x;

    return float4(clamp(float3(r, g, b), 0.0, 1.0), uniforms.opacity);
}
