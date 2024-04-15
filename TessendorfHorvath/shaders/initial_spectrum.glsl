#[compute]
#version 450

/*
    This compute shader calculates the initial spectrum. The code is converted
    from hlsl to glsl by me using gasgiants implementation as a reference, which
    is available under the MIT license.
*/


layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rg32f, set = 0, binding = 0) restrict uniform image2D noise_texture;
layout(rg32f, set = 0, binding = 1) restrict uniform image2D H0K;
layout(rgba32f, set = 0, binding = 2) restrict uniform image2D wave_data; // wave vector x, 1 / magnitude, wave vector z, frequency
layout(set = 0, binding = 3) restrict buffer SpectrumParams1 {
    float scale;
    float angle;
    float spread_blend;
    float swell;
    float alpha;
    float peak_omega;
    float gamma;
    float short_waves_fade;
} spec_params_1;
layout(set = 0, binding = 4) restrict buffer SpectrumParams2 {
    float scale;
    float angle;
    float spread_blend;
    float swell;
    float alpha;
    float peak_omega;
    float gamma;
    float short_waves_fade;
} spec_params_2;
layout(set = 0, binding = 5) restrict buffer Params {
    float size;
    float length_scale;
    float cutoff_high;
    float cutoff_low;
    float gravity_acceleration;
    float depth;
} params;


const float PI = 3.14159265;


float frequency(float k_length, float gravity, float depth) {
    return sqrt(gravity * k_length * tanh(min(k_length * depth, 20.0)));
}

float frequency_derivative(float k_length, float gravity, float depth) {
    float th = tanh(min(k_length * depth, 20.0));
    float ch = cosh(k_length * depth);
    return gravity * (depth * k_length / ch / ch + th) / frequency(k_length, gravity, depth) / 2.0;
}

float normalisation_factor(float s) {
    float s2 = s * s;
    float s3 = s2 * s;
    float s4 = s3 * s;
    if (s < 5) {
        return -0.000564 * s4 + 0.00776 * s3 - 0.044 * s2 + 0.192 * s + 0.163;
    }
    else {
        return -4.80e-08 * s4 + 1.07e-05 * s3 - 9.53e-04 * s2 + 5.90e-02 * s + 3.93e-01;
    }
}

float cosine_2s(float theta, float s) {
    return normalisation_factor(s) * pow(abs(cos(0.5 * theta)), 2.0 * s);
}

float spread_power(float omega, float peak_omega) {
    if (omega > peak_omega) {
        return 9.77 * pow(abs(omega / peak_omega), -2.5);
    }
    else {
        return 6.97 * pow(abs(omega / peak_omega), 5.0);
    }
}

float direction_spectrum(float theta, float omega, float angle, float spread_blend, float swell, float peak_omega) {
    float s = spread_power(omega, peak_omega) + 16.0 * tanh(min(omega / peak_omega, 20.0)) * swell * swell;
    return mix(2.0 / PI * cos(theta) * cos(theta), cosine_2s(theta - angle, s), spread_blend);
}

float tma_correction(float omega, float gravity, float depth) {
    float omega_h = omega * sqrt(depth / gravity);
    if (omega_h <= 1.0)
  		  return 0.5 * omega_h * omega_h;
  	if (omega_h < 2.0)
  		  return 1.0 - 0.5 * (2.0 - omega_h) * (2.0 - omega_h);
  	return 1.0;
}

float jonswap(float omega, float gravity, float depth, float scale, float alpha, float peak_omega, float gamma) {
    float sigma;
    if (omega <= peak_omega) {
        sigma = 0.07;
    }
    else {
        sigma = 0.09;
    }

    float r = exp(-(omega - peak_omega) * (omega - peak_omega) / 2.0 / sigma / sigma / peak_omega / peak_omega);
    float one_over_omega_pow5 = pow((1.0 / omega), 5);
    float peak_omega_over_omega_pow4 = pow((peak_omega / omega), 4);

    return scale * tma_correction(omega, gravity, depth) * alpha * gravity * gravity * one_over_omega_pow5 * exp(-1.25 * peak_omega_over_omega_pow4) * pow(abs(gamma), r);
}

float short_wave_fade(float k_length, float short_waves_fade) {
    return exp(-short_waves_fade * short_waves_fade * k_length * k_length);
}


void main() {

    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    float delta_k = 2 * (PI / params.length_scale);
    int image_origin_x_offset = id.x - int(params.size) / 2;
    int image_origin_z_offset = id.y - int(params.size) / 2;
    vec2 k = vec2(image_origin_x_offset, image_origin_z_offset) * delta_k;
    float k_length = length(k);

    if (k_length <= params.cutoff_high && k_length >= params.cutoff_low) {
        float k_angle = atan(k.x, k.y);
        float omega = frequency(k_length, params.gravity_acceleration, params.depth);
        imageStore(wave_data, id.xy, vec4(k.x, 1.0 / k_length, k.y, omega));

        float spec_1_jonswap = jonswap(omega, params.gravity_acceleration, params.depth, spec_params_1.scale, spec_params_1.alpha, spec_params_1.peak_omega, spec_params_1.gamma);
        float spec_1_dir_spec = direction_spectrum(k_angle, omega, spec_params_1.angle, spec_params_1.spread_blend, spec_params_1.swell, spec_params_1.peak_omega);
        float spec_1_short_wave_fade = short_wave_fade(k_length, spec_params_1.short_waves_fade);
        float spectrum = spec_1_jonswap * spec_1_dir_spec * spec_1_short_wave_fade;

        if (spec_params_2.scale > 0.0) {
            float spec_2_jonswap = jonswap(omega, params.gravity_acceleration, params.depth, spec_params_2.scale, spec_params_2.alpha, spec_params_2.peak_omega, spec_params_2.gamma);
            float spec_2_dir_spec = direction_spectrum(k_angle, omega, spec_params_2.angle, spec_params_2.spread_blend, spec_params_2.swell, spec_params_2.peak_omega);
            float spec_2_short_wave_fade = short_wave_fade(k_length, spec_params_2.short_waves_fade);
            spectrum += spec_2_jonswap * spec_2_dir_spec * spec_2_short_wave_fade;
        }

        float derived_omega_k = frequency_derivative(k_length, params.gravity_acceleration, params.depth);
        vec2 noise = imageLoad(noise_texture, id.xy).xy;
        imageStore(H0K, id.xy, vec4((1/sqrt(2.0)) * noise * sqrt(2.0 * spectrum * abs(derived_omega_k) / k_length * delta_k * delta_k), 0.0, 0.0));
    }
    else {

        imageStore(H0K, id.xy, vec4(0.0, 0.0, 0.0, 0.0));
        imageStore(wave_data, id.xy, vec4(k.x, 1.0, k.y, 0.0));
    }
}
