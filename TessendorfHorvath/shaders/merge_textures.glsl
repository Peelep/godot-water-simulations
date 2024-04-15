#[compute]
#version 450


/*
    This compute shader merges partial derivatives into textures that the final
    ocean shader can sample. The code is converted from hlsl to glsl by me using
    gasgiants implementation as a reference, which is available under the MIT license.
*/

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) restrict uniform image2D displacement;
layout(rgba32f, set = 0, binding = 1) restrict uniform image2D derivatives;
layout(rgba32f, set = 0, binding = 2) restrict uniform image2D turbulence;

layout(rg32f, set = 0, binding = 3) restrict uniform image2D DxDz;
layout(rg32f, set = 0, binding = 4) restrict uniform image2D DyDxz;
layout(rg32f, set = 0, binding = 5) restrict uniform image2D DyxDyz;
layout(rg32f, set = 0, binding = 6) restrict uniform image2D DxxDzz;

layout(set = 0, binding = 7) restrict buffer Params {
    float lambda;
    float delta_time;
} params;

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);

    vec2 v2_DxDz = imageLoad(DxDz, id.xy).xy;
    vec2 v2_DyDxz = imageLoad(DyDxz, id.xy).xy;
    vec2 v2_DyxDyz = imageLoad(DyxDyz, id.xy).xy;
    vec2 v2_DxxDzz = imageLoad(DxxDzz, id.xy).xy;

    imageStore(displacement, id.xy, vec4(params.lambda * v2_DxDz.x, v2_DyDxz.x, params.lambda * v2_DxDz.y, 1.0));
    imageStore(derivatives, id.xy, vec4(v2_DyxDyz, v2_DxxDzz * params.lambda));

    float jacobian = (1 + params.lambda * v2_DxxDzz.x) * (1 + params.lambda * v2_DxxDzz.y) - params.lambda * params.lambda * v2_DyDxz.y * v2_DyDxz.y;
    float turbulence_value = min(jacobian, imageLoad(turbulence, id.xy).r + params.delta_time * 0.5 / max(jacobian, 0.5));
    imageStore(turbulence, id.xy, vec4(turbulence_value, turbulence_value, turbulence_value, turbulence_value));
}
