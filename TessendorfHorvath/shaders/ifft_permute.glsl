#[compute]
#version 450

/*
    This compute shader permutes Cooley-Tukey FFT algorithm results. The code
    is converted from hlsl to glsl by me using gasgiants implementation as a
    reference, which is available under the MIT license.
*/


layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;


layout(rg32f, set = 0, binding = 1) restrict uniform image2D buffer_0;


void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    imageStore(buffer_0, id.xy, vec4(imageLoad(buffer_0, id.xy).rg * mod((id.x + id.y), 2), 0.0, 0.0));
}
