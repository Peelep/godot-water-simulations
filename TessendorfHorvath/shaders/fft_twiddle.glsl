#[compute]
#version 450

/*
    This compute shader pre computes twiddle factors used in Cooley-Tukey FFT
    algorithm. The code is converted from hlsl to glsl by me using gasgiants
    implementation as a reference, which is available under the MIT license.
*/

layout(local_size_x = 1, local_size_y = 8, local_size_z = 1) in;


layout(rgba32f, set = 0, binding = 0) restrict uniform image2D twiddle_data;
layout(set = 0, binding = 1) restrict buffer Params {
    int size;
} params;


const float PI = 3.14159265;


vec2 ComplexExp(vec2 a)
{
	return vec2(cos(a.y), sin(a.y)) * exp(a.x);
}


void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    uint b = params.size >> (id.x + 1);
    vec2 mult = 2 * PI * vec2(0, 1) / params.size;
    uint i = uint(mod((2 * b * (id.y / b) + mod(id.y, b)), params.size));
    vec2 twiddle = ComplexExp(-mult * ((id.y / b) * b));
    imageStore(twiddle_data, id.xy, vec4(twiddle.x, twiddle.y, i, i + b));
    imageStore(twiddle_data, ivec2(id.x, id.y + params.size / 2), vec4(-twiddle.x, -twiddle.y, i, i + b));
}
