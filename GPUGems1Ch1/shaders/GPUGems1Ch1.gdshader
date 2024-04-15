// This shader aims to implement the sum of sine concepts introduced in chapter 1
// of GPUGems 1. With the exception of schlick fresnel the fragment shader is from
// the Godot example shaders.
shader_type spatial;

uniform bool use_steep_sine = false;
uniform bool use_gerstner = false;

uniform float wave_params[100];

const int wave_count = 100;
const int params_per_wave = 6;

const int DIR_X_OFFSET = 0;
const int DIR_Z_OFFSET = 1;
const int AMPLITUDE_OFFSET = 2;
const int FREQUENCY_OFFSET = 3;
const int PHASE_SPEED_OFFSET = 4;
const int STEEPNESS_OFFSET = 5;




float dot_xz(vec3 world_pos, float dir_x, float dir_z) {
	return world_pos.x * dir_x + world_pos.z * dir_z;
}




float calculate_sine_height(int wave_index, vec3 world_pos) {

	int wave_offset = wave_index * params_per_wave;

	float dir_x = wave_params[wave_offset+DIR_X_OFFSET];
	float dir_z = wave_params[wave_offset+DIR_Z_OFFSET];
	float amplitude = wave_params[wave_offset+AMPLITUDE_OFFSET];
	float frequency = wave_params[wave_offset+FREQUENCY_OFFSET];
	float phase_speed = wave_params[wave_offset+PHASE_SPEED_OFFSET];

	float wave_xz = dot_xz(world_pos, dir_x, dir_z);

	float height = amplitude * sin(wave_xz * frequency + TIME * phase_speed);

	return height;
}

float calculate_steep_sine_height(int wave_index, vec3 world_pos) {

	int wave_offset = wave_index * params_per_wave;

	float dir_x = wave_params[wave_offset+DIR_X_OFFSET];
	float dir_z = wave_params[wave_offset+DIR_Z_OFFSET];
	float amplitude = wave_params[wave_offset+AMPLITUDE_OFFSET];
	float frequency = wave_params[wave_offset+FREQUENCY_OFFSET];
	float phase_speed = wave_params[wave_offset+PHASE_SPEED_OFFSET];
	float steepness = wave_params[wave_offset+STEEPNESS_OFFSET];

	float wave_xz = dot_xz(world_pos, dir_x, dir_z);

	float height = 2.0 * amplitude * pow((sin(wave_xz * frequency + TIME * phase_speed) + 1.0)/2.0, steepness);

	return height;
}

vec3 calculate_gerstner_height(int wave_index, vec3 world_pos) {

	int wave_offset = wave_index * params_per_wave;

	float dir_x = wave_params[wave_offset+DIR_X_OFFSET];
	float dir_z = wave_params[wave_offset+DIR_Z_OFFSET];
	float amplitude = wave_params[wave_offset+AMPLITUDE_OFFSET];
	float frequency = wave_params[wave_offset+FREQUENCY_OFFSET];
	float phase_speed = wave_params[wave_offset+PHASE_SPEED_OFFSET];
	float steepness = wave_params[wave_offset+STEEPNESS_OFFSET];

	float wave_xz = dot_xz(world_pos, dir_x, dir_z);

	vec3 gerstner = vec3(0.0);
	gerstner.x = steepness * amplitude * dir_x * cos(wave_xz * frequency + TIME * phase_speed);
	gerstner.z = steepness * amplitude * dir_z * cos(wave_xz * frequency + TIME * phase_speed);
	gerstner.y = amplitude * sin(wave_xz * frequency + TIME * phase_speed);

	return gerstner;
}



vec3 calculate_sine_normal(int wave_index, vec3 world_pos) {

	int wave_offset = wave_index * params_per_wave;

	float dir_x = wave_params[wave_offset+DIR_X_OFFSET];
	float dir_z = wave_params[wave_offset+DIR_Z_OFFSET];
	float amplitude = wave_params[wave_offset+AMPLITUDE_OFFSET];
	float frequency = wave_params[wave_offset+FREQUENCY_OFFSET];
	float phase_speed = wave_params[wave_offset+PHASE_SPEED_OFFSET];

	float wave_xz = dot_xz(world_pos, dir_x, dir_z);

	float dxz = frequency * amplitude * cos(wave_xz * frequency + TIME * phase_speed);
	float dx = dir_x * dxz;
	float dy = dir_z * dxz;

	return vec3(dx, dy, 0.0);
}

vec3 calculate_steep_sine_normal(int wave_index, vec3 world_pos) {

	int wave_offset = wave_index * params_per_wave;

	float dir_x = wave_params[wave_offset+DIR_X_OFFSET];
	float dir_z = wave_params[wave_offset+DIR_Z_OFFSET];
	float amplitude = wave_params[wave_offset+AMPLITUDE_OFFSET];
	float frequency = wave_params[wave_offset+FREQUENCY_OFFSET];
	float phase_speed = wave_params[wave_offset+PHASE_SPEED_OFFSET];
	float steepness = wave_params[wave_offset+STEEPNESS_OFFSET];

	float wave_xz = dot_xz(world_pos, dir_x, dir_z);

	float sin_part = sin(wave_xz * frequency + TIME * phase_speed);
	float cos_part = cos(wave_xz * frequency + TIME * phase_speed);
	float dxz = steepness * frequency * amplitude * pow((sin_part + 1.0)/2.0, steepness) * cos_part;
	float dx = dir_x * dxz;
	float dy = dir_z * dxz;

	return vec3(dx, dy, 0.0);
}

vec3 calculate_gerstner_normal(int wave_index, vec3 world_pos) {

	int wave_offset = wave_index * params_per_wave;

	float dir_x = wave_params[wave_offset+DIR_X_OFFSET];
	float dir_z = wave_params[wave_offset+DIR_Z_OFFSET];
	float amplitude = wave_params[wave_offset+AMPLITUDE_OFFSET];
	float frequency = wave_params[wave_offset+FREQUENCY_OFFSET];
	float phase_speed = wave_params[wave_offset+PHASE_SPEED_OFFSET];
	float steepness = wave_params[wave_offset+STEEPNESS_OFFSET];

	float wave_xz = dot_xz(world_pos, dir_x, dir_z);

	vec3 gerstner_normal = vec3(0.0);
	gerstner_normal.x = frequency * amplitude * dir_x * cos(wave_xz * frequency + TIME * phase_speed);
	gerstner_normal.z = frequency * amplitude * dir_z * cos(wave_xz * frequency + TIME * phase_speed);
	gerstner_normal.y = steepness * frequency * amplitude * sin(wave_xz * frequency + TIME * phase_speed);

	return gerstner_normal;
}


// Fragment shader uses this to color the wave tips.
varying float vertex_height;

void vertex() {
	vec3 pos = VERTEX.xyz;

	vec3 vertex = vec3(0.0);
	vec3 normal = vec3(0.0);

	for (int i = 0; i < wave_count; i += 1) {

		if (use_gerstner) {
			vertex += calculate_gerstner_height(i, pos) + pos;
			normal += calculate_gerstner_normal(i, pos) + pos;
		}
		else if (use_steep_sine) {
			vertex.y += calculate_steep_sine_height(i, pos);
			normal += calculate_steep_sine_normal(i, pos);
		}
		else { // calculate normal sine wave
			vertex.y += calculate_sine_height(i, pos);
			normal += calculate_sine_normal(i, pos);
		}
	}

	if (use_gerstner) {
		VERTEX = vertex;
		NORMAL = normalize(vec3(-normal.x, 1.0 - normal.y, -normal.z));
	}
	else {
		VERTEX.y = vertex.y;
		NORMAL = normalize(vec3(-normal.x, 1.0, -normal.y));
	}
	vertex_height = vertex.y;
}

// Uniforms for fragment and light shaders.
uniform vec3 sun_dir = vec3(0.0);
uniform vec3 water_color : source_color = vec3(0.1, 0.3, 0.5);
uniform vec3 fresnel_color : source_color = vec3(1.0);
uniform float fresnel_shininess = 5.0;
uniform vec3 specular_color : source_color = vec3(1.0);
uniform float specular_shininess = 1.0;

varying vec3 spec_fresnel_dir;

float schlick_fresnel(vec3 view_dir, vec3 normal, float R0) {
	// R0 is the reflection coefficient at normal incidence.
	float cos_theta = clamp(dot(view_dir, normal), 0.0, 1.0);
	return R0 + (1.0 - R0) * pow(1.0 - cos_theta, fresnel_shininess);
}


void fragment() {

	vec3 view_dir = normalize(VIEW - VERTEX);
	vec3 fresnel = fresnel_color * schlick_fresnel(view_dir, NORMAL, 0.02);

	ALBEDO = (fresnel + water_color) * 0.5;
	if (!use_gerstner) {
		METALLIC = 0.0;
		ROUGHNESS = 0.01;
		RIM = 0.2;
	}
}
