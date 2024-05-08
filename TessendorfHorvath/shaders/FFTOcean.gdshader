shader_type spatial;
render_mode world_vertex_coords;

uniform vec3 water_color: source_color;

uniform float w1_lengthscale = 1.0;
uniform sampler2D w1_displacement;
uniform sampler2D w1_derivatives;
uniform sampler2D w1_turbulence;

uniform float w2_lengthscale = 1.0;
uniform sampler2D w2_displacement;
uniform sampler2D w2_derivatives;
uniform sampler2D w2_turbulence;

uniform float w3_lengthscale = 1.0;
uniform sampler2D w3_displacement;
uniform sampler2D w3_derivatives;
uniform sampler2D w3_turbulence;


void vertex() {
	vec2 pos = VERTEX.xz;

	vec4 displacement = vec4(0.0);
	displacement += texture(w1_displacement, pos / w1_lengthscale);
	displacement += texture(w2_displacement, pos / w2_lengthscale);
	displacement += texture(w3_displacement, pos / w3_lengthscale);

	vec4 derivatives = vec4(0.0);
	derivatives += texture(w1_derivatives, pos / w1_lengthscale);
	derivatives += texture(w2_derivatives, pos / w2_lengthscale);
	derivatives += texture(w3_derivatives, pos / w3_lengthscale);

	vec2 slope = vec2(derivatives.x / (1.0 + derivatives.z), derivatives.y / (1.0 + derivatives.w));
	vec3 normal = normalize(vec3(-slope.x, 1.0, -slope.y));

	VERTEX.xyz += displacement.xyz;
	//VERTEX.y += displacement.y;
	NORMAL = normal;
}



float schlick_fresnel(vec3 view_dir, vec3 normal, float R0) {
	// R0 is the reflection coefficient at normal incidence.
	float cos_theta = clamp(dot(view_dir, normal), 0.0, 1.0);
	return R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);
}


void fragment() {

	float fresnel = schlick_fresnel(VIEW, NORMAL, 0.02) * 0.1;

	ALBEDO = (fresnel + water_color) * 0.5;
	METALLIC = 0.0;
	ROUGHNESS = 0.01;
	RIM = 0.2;
}
