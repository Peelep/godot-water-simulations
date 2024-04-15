class_name WaterSpectrum extends Node

const LOCAL_WORK_GROUPS_X: int = 8
const LOCAL_WORK_GROUPS_Y: int = 8

var x_groups: int = 0
var y_groups: int = 0

var texture_size: int = 0

var fft: FFT = null
var rd: RenderingDevice = null

# Final textures used in the ocean shader.
var displacement: RID = RID()
var derivatives: RID = RID()
var turbulence: RID = RID()

# Shaders & pipelines
var pre_compute_spectrum_pipeline: RID = RID()
var pre_compute_spectrum_shader: RID = RID()

var pre_compute_conjugate_spectrum_pipeline: RID = RID()
var pre_compute_conjugate_spectrum_shader: RID = RID()

var realtime_spectrum_pipeline: RID = RID()
var realtime_spectrum_shader: RID = RID()

var merge_textures_pipeline: RID = RID()
var merge_textures_shader: RID = RID()

# Variables used in shaders
var noise_texture: RID = RID()
var pre_computed_data: RID = RID()
var initial_spectrum: RID = RID() # H0
var texture_buffer: RID = RID() # H0K & ifft buffer
var DxDz: RID = RID()
var DyDxz: RID = RID()
var DyxDyz: RID = RID()
var DxxDzz: RID = RID()
var lambda: float = 1.0

func setup_spectrum(
		rendering_device: RenderingDevice,
		size: int,
		fft_node: FFT,
		gaussian_noise: RID,
		pre_compute_spectrum_shader_filepath: String,
		pre_compute_conjugate_spectrum_filepath: String,
		realtime_spectrum_shader_filepath: String,
		merge_textures_shader_filepath: String
		) -> void:

	rd = rendering_device

	pre_compute_spectrum_shader = \
			rd.shader_create_from_spirv(load(pre_compute_spectrum_shader_filepath).get_spirv())
	pre_compute_spectrum_pipeline = rd.compute_pipeline_create(pre_compute_spectrum_shader)

	pre_compute_conjugate_spectrum_shader = \
			rd.shader_create_from_spirv(load(pre_compute_conjugate_spectrum_filepath).get_spirv())
	pre_compute_conjugate_spectrum_pipeline = rd.compute_pipeline_create(pre_compute_conjugate_spectrum_shader)

	realtime_spectrum_shader = \
			rd.shader_create_from_spirv(load(realtime_spectrum_shader_filepath).get_spirv())
	realtime_spectrum_pipeline = rd.compute_pipeline_create(realtime_spectrum_shader)

	merge_textures_shader = \
			rd.shader_create_from_spirv(load(merge_textures_shader_filepath).get_spirv())
	merge_textures_pipeline = rd.compute_pipeline_create(merge_textures_shader)

	texture_size = size
	noise_texture = gaussian_noise
	fft = fft_node
	@warning_ignore("integer_division") x_groups = texture_size / LOCAL_WORK_GROUPS_X
	@warning_ignore("integer_division") y_groups = texture_size / LOCAL_WORK_GROUPS_Y

	displacement = create_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
	derivatives = create_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
	turbulence = create_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
	initial_spectrum = create_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
	pre_computed_data = create_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)

	texture_buffer = create_texture()
	DxDz = create_texture()
	DyDxz = create_texture()
	DyxDyz = create_texture()
	DxxDzz = create_texture()


func calculate_initial_spectrum(
			wave_params: WaveParameters,
			length_scale: float,
			cutoff_low: float,
			cutoff_high: float
			) -> void:

	lambda = wave_params.lambda

	var noise_uniform: RDUniform = RDUniform.new()
	noise_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	noise_uniform.binding = 0
	noise_uniform.add_id(noise_texture)

	var h0k_uniform: RDUniform = RDUniform.new()
	h0k_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	h0k_uniform.binding = 1
	h0k_uniform.add_id(texture_buffer)

	var pre_computed_data_uniform: RDUniform = RDUniform.new()
	pre_computed_data_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	pre_computed_data_uniform.binding = 2
	pre_computed_data_uniform.add_id(pre_computed_data)

	var wave_param_bytes_1: PackedByteArray = PackedFloat32Array([
		wave_params.local.scale,
		wave_params.local.angle,
		wave_params.local.spread_blend,
		wave_params.local.swell,
		wave_params.local.jonswap_alpha,
		wave_params.local.jonswap_peak_omega,
		wave_params.local.jonswap_gamma,
		wave_params.local.short_waves_fade
	]).to_byte_array()
	var wave_param_1_buffer_rid: RID = rd.storage_buffer_create(wave_param_bytes_1.size(), wave_param_bytes_1)
	var wave_param_1_uniform: RDUniform = RDUniform.new()
	wave_param_1_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	wave_param_1_uniform.binding = 3
	wave_param_1_uniform.add_id(wave_param_1_buffer_rid)

	var wave_param_bytes_2: PackedByteArray = PackedFloat32Array([
		wave_params.swell.scale,
		wave_params.swell.angle,
		wave_params.swell.spread_blend,
		wave_params.swell.swell,
		wave_params.swell.jonswap_alpha,
		wave_params.swell.jonswap_peak_omega,
		wave_params.swell.jonswap_gamma,
		wave_params.swell.short_waves_fade
	]).to_byte_array()
	var wave_param_2_buffer_rid: RID = rd.storage_buffer_create(wave_param_bytes_2.size(), wave_param_bytes_2)
	var wave_param_2_uniform: RDUniform = RDUniform.new()
	wave_param_2_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	wave_param_2_uniform.binding = 4
	wave_param_2_uniform.add_id(wave_param_2_buffer_rid)

	var params_bytes: PackedByteArray = PackedFloat32Array([
		float(texture_size),
		length_scale,
		cutoff_high,
		cutoff_low,
		wave_params.gravity,
		wave_params.depth
	]).to_byte_array()
	var params_buffer_rid: RID = rd.storage_buffer_create(params_bytes.size(), params_bytes)
	var params_uniform: RDUniform = RDUniform.new()
	params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	params_uniform.binding = 5
	params_uniform.add_id(params_buffer_rid)

	var initial_spectrum_uniform_set: RID = rd.uniform_set_create([
		noise_uniform,
		h0k_uniform,
		pre_computed_data_uniform,
		wave_param_1_uniform,
		wave_param_2_uniform,
		params_uniform
	], pre_compute_spectrum_shader, 0)

	var initial_spectrum_compute_list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(initial_spectrum_compute_list, pre_compute_spectrum_pipeline)
	rd.compute_list_bind_uniform_set(initial_spectrum_compute_list, initial_spectrum_uniform_set, 0)
	rd.compute_list_dispatch(initial_spectrum_compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()

	rd.barrier(RenderingDevice.BARRIER_MASK_COMPUTE)

	var h0_uniform: RDUniform = RDUniform.new()
	h0_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	h0_uniform.binding = 0
	h0_uniform.add_id(initial_spectrum)

	var h0k_buffer_uniform: RDUniform = RDUniform.new()
	h0k_buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	h0k_buffer_uniform.binding = 1
	h0k_buffer_uniform.add_id(texture_buffer)

	var size_as_bytes: PackedByteArray = PackedInt32Array([texture_size]).to_byte_array()
	var size_buffer_rid: RID = rd.storage_buffer_create(size_as_bytes.size(), size_as_bytes)
	var size_uniform: RDUniform = RDUniform.new()
	size_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	size_uniform.binding = 2
	size_uniform.add_id(size_buffer_rid)

	var conjugate_spectrum_uniform_set: RID = rd.uniform_set_create([
		h0_uniform, h0k_buffer_uniform, size_uniform
	], pre_compute_conjugate_spectrum_shader, 0)

	var conjugate_spectrum_compute_list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(conjugate_spectrum_compute_list, pre_compute_conjugate_spectrum_pipeline)
	rd.compute_list_bind_uniform_set(conjugate_spectrum_compute_list, conjugate_spectrum_uniform_set, 0)
	rd.compute_list_dispatch(conjugate_spectrum_compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()

	rd.barrier(RenderingDevice.BARRIER_MASK_COMPUTE)

	rd.free_rid(initial_spectrum_uniform_set)
	rd.free_rid(conjugate_spectrum_uniform_set)


func calculate_realtime_spectrum(delta: float) -> void:

	# -------------------- REALTIME SPECTRUM --------------------

	var iDxDz_uniform: RDUniform = RDUniform.new()
	iDxDz_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	iDxDz_uniform.binding = 0
	iDxDz_uniform.add_id(DxDz)

	var iDyDxz_uniform: RDUniform = RDUniform.new()
	iDyDxz_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	iDyDxz_uniform.binding = 1
	iDyDxz_uniform.add_id(DyDxz)

	var iDyxDyz_uniform: RDUniform = RDUniform.new()
	iDyxDyz_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	iDyxDyz_uniform.binding = 2
	iDyxDyz_uniform.add_id(DyxDyz)

	var iDxxDzz_uniform: RDUniform = RDUniform.new()
	iDxxDzz_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	iDxxDzz_uniform.binding = 3
	iDxxDzz_uniform.add_id(DxxDzz)

	var H0_uniform: RDUniform = RDUniform.new()
	H0_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	H0_uniform.binding = 4
	H0_uniform.add_id(initial_spectrum)

	var pre_computed_wavedata_uniform: RDUniform = RDUniform.new()
	pre_computed_wavedata_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	pre_computed_wavedata_uniform.binding = 5
	pre_computed_wavedata_uniform.add_id(pre_computed_data)

	var time_as_bytes: PackedByteArray = PackedFloat32Array([Time.get_ticks_msec()/1000.0]).to_byte_array()
	var time_buffer_rid: RID = rd.storage_buffer_create(time_as_bytes.size(), time_as_bytes)
	var time_uniform: RDUniform = RDUniform.new()
	time_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	time_uniform.binding = 6
	time_uniform.add_id(time_buffer_rid)

	var realtime_spectrum_uniform_set: RID = rd.uniform_set_create([
		iDxDz_uniform,
		iDyDxz_uniform,
		iDyxDyz_uniform,
		iDxxDzz_uniform,
		H0_uniform,
		pre_computed_wavedata_uniform,
		time_uniform
	], realtime_spectrum_shader, 0)

	var realtime_spectrum_compute_list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(realtime_spectrum_compute_list, realtime_spectrum_pipeline)
	rd.compute_list_bind_uniform_set(realtime_spectrum_compute_list, realtime_spectrum_uniform_set, 0)
	rd.compute_list_dispatch(realtime_spectrum_compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()

	rd.barrier(RenderingDevice.BARRIER_MASK_COMPUTE)


	# -------------------------- IFFT ---------------------------


	fft.ifft(DxDz,   texture_buffer)
	fft.ifft(DyDxz,  texture_buffer)
	fft.ifft(DyxDyz, texture_buffer)
	fft.ifft(DxxDzz, texture_buffer)


	# ---------------------- MERGE TEXTURES ---------------------


	var displacement_uniform: RDUniform = RDUniform.new()
	displacement_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	displacement_uniform.binding = 0
	displacement_uniform.add_id(displacement)

	var derivatives_uniform: RDUniform = RDUniform.new()
	derivatives_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	derivatives_uniform.binding = 1
	derivatives_uniform.add_id(derivatives)

	var turbulence_uniform: RDUniform = RDUniform.new()
	turbulence_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	turbulence_uniform.binding = 2
	turbulence_uniform.add_id(turbulence)

	var mDxDz_uniform: RDUniform = RDUniform.new()
	mDxDz_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	mDxDz_uniform.binding = 3
	mDxDz_uniform.add_id(DxDz)

	var mDyDxz_uniform: RDUniform = RDUniform.new()
	mDyDxz_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	mDyDxz_uniform.binding = 4
	mDyDxz_uniform.add_id(DyDxz)

	var mDyxDyz_uniform: RDUniform = RDUniform.new()
	mDyxDyz_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	mDyxDyz_uniform.binding = 5
	mDyxDyz_uniform.add_id(DyxDyz)

	var mDxxDzz_uniform: RDUniform = RDUniform.new()
	mDxxDzz_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	mDxxDzz_uniform.binding = 6
	mDxxDzz_uniform.add_id(DxxDzz)

	var params_bytes: PackedByteArray = PackedFloat32Array([lambda, delta]).to_byte_array()
	var params_buffer_rid: RID = rd.storage_buffer_create(params_bytes.size(), params_bytes)
	var params_uniform: RDUniform = RDUniform.new()
	params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	params_uniform.binding = 7
	params_uniform.add_id(params_buffer_rid)

	var merge_uniform_set: RID = rd.uniform_set_create([
		displacement_uniform,
		derivatives_uniform,
		turbulence_uniform,
		mDxDz_uniform,
		mDyDxz_uniform,
		mDyxDyz_uniform,
		mDxxDzz_uniform,
		params_uniform
	], merge_textures_shader, 0)

	var merge_textures_compute_list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(merge_textures_compute_list, merge_textures_pipeline)
	rd.compute_list_bind_uniform_set(merge_textures_compute_list, merge_uniform_set, 0)
	rd.compute_list_dispatch(merge_textures_compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()

	rd.barrier(RenderingDevice.BARRIER_MASK_COMPUTE)

	rd.free_rid(realtime_spectrum_uniform_set)
	rd.free_rid(merge_uniform_set)
	rd.free_rid(time_buffer_rid)
	rd.free_rid(params_buffer_rid)


func create_texture(
			format: RenderingDevice.DataFormat = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT,
			data: PackedByteArray = []
			) -> RID:

	var texture_format: RDTextureFormat = RDTextureFormat.new()
	texture_format.format = format
	texture_format.width = texture_size
	texture_format.height = texture_size
	texture_format.usage_bits = (
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT +
			RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT +
			RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT +
			RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	)
	if data.is_empty():
		return rd.texture_create(texture_format, RDTextureView.new())
	else:
		return rd.texture_create(texture_format, RDTextureView.new(), [data])



func cleanup_gpu() -> void:
	rd.free_rid(pre_compute_spectrum_shader)
	rd.free_rid(pre_compute_conjugate_spectrum_shader)
	rd.free_rid(realtime_spectrum_shader)
	rd.free_rid(merge_textures_shader)
	rd.free_rid(noise_texture)
	rd.free_rid(pre_computed_data)
	rd.free_rid(initial_spectrum)
	rd.free_rid(texture_buffer)
	rd.free_rid(DxDz)
	rd.free_rid(DyDxz)
	rd.free_rid(DyxDyz)
	rd.free_rid(DxxDzz)
	rd.free_rid(displacement)
	rd.free_rid(derivatives)
	rd.free_rid(turbulence)
