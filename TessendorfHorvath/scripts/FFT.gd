class_name FFT extends Node

const LOCAL_WORK_GROUPS_X: int = 8
const LOCAL_WORK_GROUPS_Y: int = 8

var x_groups: int = 0
var y_groups: int = 0

var texture_size: int = 0
var texture_log_size: int = 0


var rd: RenderingDevice = null

var fft_v_pipeline: RID  = RID()
var fft_v_shader: RID = RID()

var fft_h_pipeline: RID = RID()
var fft_h_shader: RID = RID()

var fft_permute_pipeline: RID = RID()
var fft_permute_shader: RID = RID()

var twiddle_shader: RID = RID()
var twiddle_texture: RID = RID()


func setup_fft(
		rendering_device: RenderingDevice,
		size: int,
		fft_v_shader_filepath: String,
		fft_h_shader_filepath: String,
		fft_permute_filepath: String,
		twiddle_shader_filepath: String
		) -> void:

	rd = rendering_device

	fft_v_shader = rd.shader_create_from_spirv(load(fft_v_shader_filepath).get_spirv())
	fft_v_pipeline = rd.compute_pipeline_create(fft_v_shader)

	fft_h_shader = rd.shader_create_from_spirv(load(fft_h_shader_filepath).get_spirv())
	fft_h_pipeline = rd.compute_pipeline_create(fft_h_shader)

	fft_permute_shader = rd.shader_create_from_spirv(load(fft_permute_filepath).get_spirv())
	fft_permute_pipeline = rd.compute_pipeline_create(fft_permute_shader)

	twiddle_shader = rd.shader_create_from_spirv(load(twiddle_shader_filepath).get_spirv())

	texture_size = size
	texture_log_size = int(log(texture_size) / log(2))
	@warning_ignore("integer_division") x_groups = texture_size / LOCAL_WORK_GROUPS_X
	@warning_ignore("integer_division") y_groups = texture_size / LOCAL_WORK_GROUPS_Y
	pre_compute_twiddle_factors()


func pre_compute_twiddle_factors() -> void:

	var texture_format: RDTextureFormat = RDTextureFormat.new()
	texture_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	texture_format.width = texture_log_size
	texture_format.height = texture_size
	texture_format.usage_bits = (
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT +
			RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT +
			RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
			)
	twiddle_texture = rd.texture_create(texture_format, RDTextureView.new())


	var texture_uniform: RDUniform = RDUniform.new()
	texture_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	texture_uniform.binding = 0
	texture_uniform.add_id(twiddle_texture)

	var params_bytes: PackedByteArray = PackedInt32Array([texture_size]).to_byte_array()
	var params_buffer_rid: RID = rd.storage_buffer_create(params_bytes.size(), params_bytes)
	var size_uniform: RDUniform = RDUniform.new()
	size_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	size_uniform.binding = 1
	size_uniform.add_id(params_buffer_rid)

	var uniform_set: RID = rd.uniform_set_create([texture_uniform, size_uniform], twiddle_shader, 0)

	var compute_pipeline: RID = rd.compute_pipeline_create(twiddle_shader)
	var compute_list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, compute_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	@warning_ignore("integer_division")
	rd.compute_list_dispatch(compute_list, texture_log_size, (texture_size / 2) / LOCAL_WORK_GROUPS_Y, 1)
	rd.compute_list_end()

	rd.barrier(RenderingDevice.BARRIER_MASK_COMPUTE)

	rd.free_rid(compute_pipeline)
	rd.free_rid(uniform_set)
	rd.free_rid(params_buffer_rid)


func ifft(input: RID, buffer: RID) -> void:

	# This values is used like a bool. It's an int because I don't want to deal with byte offsets.
	var ping_pong: int = 0
	var used_rd_resources: Array[RID] = []

	# -------------------- HORIZONTAL STEP --------------------

	for step: int in range(0, texture_log_size): #9
		# Invert the "bool"
		if ping_pong == 0:
			ping_pong = 1
		else:
			ping_pong = 0

		var compute_h_list: int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_h_list, fft_h_pipeline)

		var twiddle_texture_uniform: RDUniform = RDUniform.new()
		twiddle_texture_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		twiddle_texture_uniform.binding = 0
		twiddle_texture_uniform.add_id(twiddle_texture)

		var input_texture_uniform: RDUniform = RDUniform.new()
		input_texture_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		input_texture_uniform.binding = 1
		input_texture_uniform.add_id(input)

		var buffer_texture_uniform: RDUniform = RDUniform.new()
		buffer_texture_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		buffer_texture_uniform.binding = 2
		buffer_texture_uniform.add_id(buffer)

		var params_bytes: PackedByteArray = PackedInt32Array([ping_pong, step]).to_byte_array()
		var params_buffer_rid: RID = rd.storage_buffer_create(params_bytes.size(), params_bytes)
		var params_uniform: RDUniform = RDUniform.new()
		params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		params_uniform.binding = 3
		params_uniform.add_id(params_buffer_rid)

		var uniform_set: RID = rd.uniform_set_create(
				[
					twiddle_texture_uniform,
					input_texture_uniform,
					buffer_texture_uniform,
					params_uniform
				],
				fft_h_shader, 0
		)
		rd.compute_list_bind_uniform_set(compute_h_list, uniform_set, 0)
		rd.compute_list_dispatch(compute_h_list, x_groups, y_groups, 1)
		rd.compute_list_end()

		rd.barrier(RenderingDevice.BARRIER_MASK_COMPUTE)

		used_rd_resources.append(uniform_set)
		used_rd_resources.append(params_buffer_rid)

	# -------------------- VERTICAL STEP --------------------

	for step: int in range(0, texture_log_size):
		# Invert the "bool"
		if ping_pong == 0:
			ping_pong = 1
		else:
			ping_pong = 0

		var fft_v_compute_list: int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(fft_v_compute_list, fft_v_pipeline)

		var twiddle_texture_uniform: RDUniform = RDUniform.new()
		twiddle_texture_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		twiddle_texture_uniform.binding = 0
		twiddle_texture_uniform.add_id(twiddle_texture)

		var input_texture_uniform: RDUniform = RDUniform.new()
		input_texture_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		input_texture_uniform.binding = 1
		input_texture_uniform.add_id(input)

		var buffer_texture_uniform: RDUniform = RDUniform.new()
		buffer_texture_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		buffer_texture_uniform.binding = 2
		buffer_texture_uniform.add_id(buffer)

		var params_bytes: PackedByteArray = PackedInt32Array([ping_pong, step]).to_byte_array()
		var params_buffer_rid: RID = rd.storage_buffer_create(params_bytes.size(), params_bytes)
		var params_uniform: RDUniform = RDUniform.new()
		params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		params_uniform.binding = 3
		params_uniform.add_id(params_buffer_rid)

		var uniform_set: RID = rd.uniform_set_create(
				[
					twiddle_texture_uniform,
					input_texture_uniform,
					buffer_texture_uniform,
					params_uniform
				],
				fft_h_shader, 0
		)
		rd.compute_list_bind_uniform_set(fft_v_compute_list, uniform_set, 0)
		rd.compute_list_dispatch(fft_v_compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()

		rd.barrier(RenderingDevice.BARRIER_MASK_COMPUTE)

		used_rd_resources.append(uniform_set)
		used_rd_resources.append(params_buffer_rid)


	# If ping_pong equals one, then the output is in the buffer. Meaning
	# data from the buffer needs to be moved into the input as that is used
	# as an output by this function.
	if ping_pong == 1:
		rd.texture_update(input, 0, rd.texture_get_data(buffer, 0))

	# -------------------- PERMUTE --------------------

	var permute_compute_list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(permute_compute_list, fft_permute_pipeline)

	var texture_uniform: RDUniform = RDUniform.new()
	texture_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	texture_uniform.binding = 1
	texture_uniform.add_id(input)

	var permute_uniform_set: RID = rd.uniform_set_create([texture_uniform], fft_permute_shader, 0)
	rd.compute_list_bind_uniform_set(permute_compute_list, permute_uniform_set, 0)

	rd.compute_list_dispatch(permute_compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()
	rd.barrier(RenderingDevice.BARRIER_MASK_COMPUTE)

	used_rd_resources.append(permute_uniform_set)

	# -------------------- CLEAN UP --------------------

	for rid: RID in used_rd_resources:
		rd.free_rid(rid)



#func debug(inp: RID, buf: RID, step: int, fft_mode: String, ping_pong: int) -> void:
#
	#if ping_pong == 0:
		#var inp_img: Image = Image.create_from_data(
				#texture_size,
				#texture_size,
				#false,
				#Image.FORMAT_RGF,
				#rd.texture_get_data(inp, 0)
		#)
		#inp_img.save_png("res://test/" + fft_mode + "/" + str(step) + "_inp_" + fft_mode + ".png")
#
		#print("inp_" + fft_mode + "_" + str(step) + ": ", debug_check_if_image_has_data(inp_img))
#
	#else:
		#var buf_img: Image = Image.create_from_data(
				#texture_size,
				#texture_size,
				#false,
				#Image.FORMAT_RGF,
				#rd.texture_get_data(buf, 0)
		#)
		#buf_img.save_png("res://test/" + fft_mode + "/" + str(step) + "_buf_" + fft_mode + ".png")
#
		#print("buf_" + fft_mode + "_" + str(step) + ": ", debug_check_if_image_has_data(buf_img))
#
#func debug_save_img(inp: RID, filepath: String) -> void:
	#var inp_img: Image = Image.create_from_data(
			#texture_size,
			#texture_size,
			#false,
			#Image.FORMAT_RGF,
			#rd.texture_get_data(inp, 0)
	#)
	#inp_img.save_png(filepath)
#
#func debug_check_if_image_has_data(img: Image) -> bool:
	#var constains_data: bool = false
	#for i: int in range(0, texture_size):
		#for j: int in range(0, texture_size):
			#if img.get_pixel(i, j) != Color.BLACK:
				#constains_data = true
	#return constains_data


func cleanup_gpu() -> void:
	rd.free_rid(twiddle_texture)
	rd.free_rid(twiddle_shader)
	rd.free_rid(fft_v_shader)
	rd.free_rid(fft_h_shader)
