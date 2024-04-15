#[compute]
#version 450

/*
    This compute shader computes the horizontal steps in Cooley-Tukey FFT
    algorithm. The code is converted from hlsl to glsl by me using gasgiants
    implementation as a reference, which is available under the MIT license.
*/

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;


layout(rgba32f, set = 0, binding = 0) restrict uniform image2D twiddle_data;
layout(rg32f, set = 0, binding = 1) restrict uniform image2D buffer_0;
layout(rg32f, set = 0, binding = 2) restrict uniform image2D buffer_1;
layout(set = 0, binding = 3) restrict buffer Params {
  int ping_pong;
  int loop_step;
} params;


vec2 ComplexMult(vec2 a, vec2 b)
{
  return vec2(a.r * b.r - a.g * b.g, a.r * b.g + a.g * b.r);
}

void main()
{
  ivec2 id = ivec2(gl_GlobalInvocationID.xy);
  vec4 data = imageLoad(twiddle_data, ivec2(params.loop_step, id.x));
  ivec2 input_indices = ivec2(int(data.b), int(data.a));
  vec2 twiddle_vec = vec2(data.r, -data.g);

	if (params.ping_pong == 1) {
    vec2 load_x = imageLoad(buffer_0, ivec2(input_indices.x, id.y)).xy;
    vec2 load_y = imageLoad(buffer_0, ivec2(input_indices.y, id.y)).xy;
    vec2 result = load_x + ComplexMult(twiddle_vec, load_y);
    imageStore(buffer_1, id.xy, vec4(result.r, result.g, 0.0, 0.0));
	}
	else {
    vec2 load_x = imageLoad(buffer_1, ivec2(input_indices.x, id.y)).xy;
    vec2 load_y = imageLoad(buffer_1, ivec2(input_indices.y, id.y)).xy;
    vec2 result = load_x + ComplexMult(twiddle_vec, load_y);
    imageStore(buffer_0, id.xy, vec4(result.r, result.g, 0.0, 0.0));
	}
}
