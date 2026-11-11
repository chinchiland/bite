/// The body's shaders, compiled the first time your body is drawn instead of at build time, so
/// Bite builds on any Xcode, with or without its Metal toolchain.
///
/// Lit like a studio shot: a warm key from the front left, a cool fill, two rims from behind and
/// a sky above, tone mapped the way three.js's ACES filmic curve does it, so the app and the web
/// page look alike. Clothes are painted from each vertex's rest height and its place along the
/// arm, so hems stay crisp and level whatever the pose. Colors leave the shader in sRGB and
/// premultiplied, the way the screen composites them, so the edges blend without a halo.
enum BodyShader {
    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct BodyUniforms {
        float4x4 viewProjection;
        float4x4 model;
        float4 camera;
        float4 look;
    };

    struct BodyOut {
        float4 position [[position]];
        float3 world;
        float3 normal;
        float3 color;
        float4 cloth;
    };

    vertex BodyOut bodyVertex(uint vid [[vertex_id]],
                              const device packed_float3 *positions [[buffer(0)]],
                              const device packed_float3 *normals [[buffer(1)]],
                              const device packed_float3 *colors [[buffer(2)]],
                              const device float4 *cloth [[buffer(3)]],
                              constant BodyUniforms &u [[buffer(4)]]) {
        BodyOut out;
        float4 world = u.model * float4(float3(positions[vid]), 1.0);
        out.position = u.viewProjection * world;
        out.world = world.xyz;
        out.normal = (u.model * float4(float3(normals[vid]), 0.0)).xyz;
        out.color = float3(colors[vid]);
        out.cloth = cloth[vid];
        return out;
    }

    static float within(float lo, float hi, float x) {
        float w = max(fwidth(x) * 0.8, 0.0004);
        return smoothstep(lo - w, lo + w, x) * (1.0 - smoothstep(hi - w, hi + w, x));
    }

    static float3 aces(float3 color) {
        const float3x3 input = float3x3(float3(0.59719, 0.07600, 0.02840), float3(0.35458, 0.90834, 0.13383), float3(0.04823, 0.01566, 0.83777));
        const float3x3 output = float3x3(float3(1.60475, -0.10208, -0.00327), float3(-0.53108, 1.10813, -0.07276), float3(-0.07367, -0.00605, 1.07602));
        color = input * (color * (0.92 / 0.6));
        color = (color * (color + 0.0245786) - 0.000090537) / (color * (0.983729 * color + 0.4329510) + 0.238081);
        return saturate(output * color);
    }

    static float3 encode(float3 c) {
        return select(1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, c * 12.92, c <= 0.0031308);
    }

    fragment float4 bodyFragment(BodyOut in [[stage_in]], constant BodyUniforms &u [[buffer(0)]]) {
        float3 albedo = in.color;
        float roughness = 0.55;
        float band = in.cloth.x, along = in.cloth.y, arm = in.cloth.z, head = in.cloth.w;
        float cloth = 0.0, rough = 0.0;
        float3 fabric = float3(0.0);
        if (u.look.x < 0.5) {
            cloth = max(within(0.405, 0.548, band), u.look.y * within(0.664, 0.748, band)) * (1.0 - smoothstep(0.28, 0.42, arm));
            fabric = float3(0.022, 0.025, 0.031) * cloth;
            rough = 0.93 * cloth;
        } else if (u.look.x < 1.5) {
            float wa = max(fwidth(along) * 0.8, 0.0006);
            float torso = within(0.535, 0.835, band) * (1.0 - smoothstep(0.35, 0.6, arm)) * (1.0 - smoothstep(0.45, 0.65, head));
            float sleeve = step(-0.75, along) * (1.0 - smoothstep(0.43 - wa, 0.43 + wa, along));
            float tee = max(torso, sleeve);
            float jeans = within(0.04, 0.552, band) * (1.0 - smoothstep(0.35, 0.6, arm)) * (1.0 - tee);
            float shoe = 1.0 - smoothstep(0.032, 0.036, band);
            fabric = tee * float3(0.52, 0.5, 0.47) + jeans * float3(0.03, 0.055, 0.12) + shoe * float3(0.74, 0.73, 0.7);
            cloth = saturate(tee + jeans + shoe);
            rough = tee * 0.96 + jeans * 0.84 + shoe * 0.6;
        }
        if (cloth > 0.0001) {
            albedo = mix(albedo, fabric / cloth, cloth);
            roughness = mix(roughness, rough / cloth, cloth);
        }

        float3 n = normalize(in.normal), v = normalize(u.camera.xyz - in.world);
        if (dot(n, v) < 0.0) n = -n;
        float3 color = albedo * mix(float3(0.10, 0.08, 0.07), float3(1.0, 0.93, 0.87), n.y * 0.5 + 0.5) * 0.36;
        const float3 directions[4] = { normalize(float3(-6, 8, 7)), normalize(float3(8, 1, 6)), normalize(float3(4, 6, -8)), normalize(float3(-7, 4, -6)) };
        const float3 lights[4] = { float3(1.0, 0.94, 0.88) * 2.0, float3(0.81, 0.86, 1.0) * 0.32, float3(1.0, 0.82, 0.63) * 1.5, float3(0.66, 0.77, 1.0) * 0.85 };
        float shininess = max(2.0 / max(pow(roughness, 4.0), 0.0005) - 2.0, 1.0);
        for (int i = 0; i < 4; i++) {
            float3 l = directions[i], h = normalize(l + v);
            float lambert = max(dot(n, l), 0.0);
            float specular = 0.04 * pow(max(dot(n, h), 0.0), shininess) * (shininess + 8.0) / 25.13;
            color += lights[i] * lambert * (albedo + specular);
        }
        color += float3(0.0070, 0.0024, 0.0015);
        color = encode(aces(color));
        return float4(color * u.look.z, u.look.z);
    }

    struct ShadowOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex ShadowOut shadowVertex(uint vid [[vertex_id]], constant BodyUniforms &u [[buffer(4)]], constant float4 &place [[buffer(5)]]) {
        const float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
        float2 c = corners[vid];
        ShadowOut out;
        out.position = u.viewProjection * (u.model * float4(c.x * place.x, place.z, c.y * place.y, 1.0));
        out.uv = c;
        return out;
    }

    fragment float4 shadowFragment(ShadowOut in [[stage_in]], constant BodyUniforms &u [[buffer(0)]]) {
        float a = (1.0 - smoothstep(0.0, 1.0, length(in.uv))) * 0.55 * u.look.z;
        return float4(0.0, 0.0, 0.0, a);
    }
    """#
}
