#[compute]
#version 450

/*
    This compute shader calculates the realtime spectrum. The code is converted
    from hlsl to glsl by me using gasgiants implementation as a reference, which
    is available under the MIT license.
*/

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rg32f, set = 0, binding = 0) restrict uniform image2D DxDz;
layout(rg32f, set = 0, binding = 1) restrict uniform image2D DyDxz;
layout(rg32f, set = 0, binding = 2) restrict uniform image2D DyxDyz;
layout(rg32f, set = 0, binding = 3) restrict uniform image2D DxxDzz;
layout(rgba32f, set = 0, binding = 4) restrict uniform image2D H0;
layout(rgba32f, set = 0, binding = 5) restrict uniform image2D WaveData; // wave vector x, 1 / magnitude, wave vector z, frequency
layout(set = 0, binding = 6) restrict buffer Params {
    float time;
} params;


vec2 ComplexMult(vec2 a, vec2 b)
{
  	return vec2(a.r * b.r - a.g * b.g, a.r * b.g + a.g * b.r);
}


void main() {

    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    vec4 wave = imageLoad(WaveData, id.xy);
    float phase = wave.w * params.time;
    vec2 exponent = vec2(cos(phase), sin(phase));
    vec2 h = ComplexMult(imageLoad(H0, id.xy).xy, exponent) + ComplexMult(imageLoad(H0, id.xy).zw, vec2(exponent.x, -exponent.y));
    vec2 ih = vec2(-h.y, h.x);

    vec2 displacement_x = ih * wave.x * wave.y;
    vec2 displacement_y = h;
  	vec2 displacement_z = ih * wave.z * wave.y;

  	vec2 displacement_x_dx = -h * wave.x * wave.x * wave.y;
  	vec2 displacement_y_dx = ih * wave.x;
  	vec2 displacement_z_dx = -h * wave.x * wave.z * wave.y;

  	vec2 displacement_y_dz = ih * wave.z;
  	vec2 displacement_z_dz = -h * wave.z * wave.z * wave.y;

    imageStore(DxDz,   id.xy, vec4(displacement_x.x    - displacement_z.y,    displacement_x.y    + displacement_z.x,    0.0, 0.0));
    imageStore(DyDxz,  id.xy, vec4(displacement_y.x    - displacement_z_dx.y, displacement_y.y    + displacement_z_dx.x, 0.0, 0.0));
    imageStore(DyxDyz, id.xy, vec4(displacement_y_dx.x - displacement_y_dz.y, displacement_y_dx.y + displacement_y_dz.x, 0.0, 0.0));
    imageStore(DxxDzz, id.xy, vec4(displacement_x_dx.x - displacement_z_dz.y, displacement_x_dx.y + displacement_z_dz.x, 0.0, 0.0));
}
