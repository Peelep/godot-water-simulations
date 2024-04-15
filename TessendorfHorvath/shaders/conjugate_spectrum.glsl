#[compute]
#version 450

/*
    This compute shader calculates the conjugate spectrum of the initial spectrum.
    The code is converted from hlsl to glsl by me using gasgiants implementation
    as a reference, which is available under the MIT license.
*/

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) restrict uniform image2D H0;
layout(rg32f, set = 0, binding = 1) restrict uniform image2D H0K;
layout(set = 0, binding = 2) restrict buffer Params {
    int size;
} params;

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    vec2 h0k = imageLoad(H0K, id.xy).rg;
    vec2 h0_minus_k = imageLoad(H0K, ivec2(mod(params.size - id.x, params.size), mod(params.size - id.y, params.size))).xy;
    imageStore(H0, id.xy, vec4(h0k.x, h0k.y, h0_minus_k.x, -h0_minus_k.y));
}
