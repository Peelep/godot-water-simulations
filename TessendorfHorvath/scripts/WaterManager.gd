extends Node3D

## Fps is capped to monitor refresh rate by default, can be changed by disabling vsync.
@export var vsync: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED
## Must be a power of 2.
@export_range(128, 4096) var texture_size: int = 256
@export var water_color: Color = Color.ROYAL_BLUE

@export_group("Compute Shader Filepaths")
@export_file("*.glsl") var cooley_tukey_fft_v: String = ""
@export_file("*.glsl") var cooley_tukey_fft_h: String = ""
@export_file("*.glsl") var cooley_tukey_fft_permute: String = ""
@export_file("*.glsl") var pre_compute_fft_twiddle: String = ""
@export_file("*.glsl") var pre_compute_spectrum: String = ""
@export_file("*.glsl") var pre_compute_conjugate_spectrum: String = ""
@export_file("*.glsl") var realtime_spectrum: String = ""
@export_file("*.glsl") var merge_textures: String = ""

@export_group("Wave Settings")
@export var length_scale_1: float = 500.0
@export var length_scale_2: float = 27.0
@export var length_scale_3: float = 5.0
@export var wave_parameters: WaveParameters = null

@onready var shader_material: ShaderMaterial = preload("res://TessendorfHorvath/materials/FFTWaterPlane.material")
@onready var fft: FFT = $FFT
@onready var ws1: WaterSpectrum = $WaterSpectrums/WaterSpectrum1
@onready var ws2: WaterSpectrum = $WaterSpectrums/WaterSpectrum2
@onready var ws3: WaterSpectrum = $WaterSpectrums/WaterSpectrum3

var initials_ready: bool = false
var rd: RenderingDevice = null


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(vsync)
	rd = RenderingServer.get_rendering_device()
	assert(texture_size % 2 == 0, "Texture size must be a power of two.")
	init_water()


func _process(delta: float) -> void:
	if initials_ready:
		ws1.calculate_realtime_spectrum(delta)
		ws2.calculate_realtime_spectrum(delta)
		ws3.calculate_realtime_spectrum(delta)


func init_water() -> void:
	wave_parameters.calculate_settings()
	var gaussian_noise: RID = create_gaussian_noise_texture()

	fft.setup_fft(
			rd,
			texture_size,
			cooley_tukey_fft_v,
			cooley_tukey_fft_h,
			cooley_tukey_fft_permute,
			pre_compute_fft_twiddle
	)

	for ws: WaterSpectrum in $WaterSpectrums.get_children():
		ws.setup_spectrum(
				rd,
				texture_size,
				fft,
				gaussian_noise,
				pre_compute_spectrum,
				pre_compute_conjugate_spectrum,
				realtime_spectrum,
				merge_textures
		)

	calculate_initial_spectrums()
	setup_shader_params()
	initials_ready = true



func calculate_initial_spectrums() -> void:
	var boundary_2: float = 2 * (PI / length_scale_2) * 6.0
	var boundary_3: float = 2 * (PI / length_scale_3) * 6.0

	ws1.calculate_initial_spectrum(wave_parameters, length_scale_1, 0.0001, boundary_2)
	ws2.calculate_initial_spectrum(wave_parameters, length_scale_2, boundary_2, boundary_3)
	ws3.calculate_initial_spectrum(wave_parameters, length_scale_3, boundary_3, 9999.0)


func setup_shader_params() -> void:
	shader_material.set_shader_parameter("water_color", Vector3(water_color.r, water_color.g, water_color.b))
	shader_material.set_shader_parameter("w1_lengthscale", length_scale_1)
	shader_material.set_shader_parameter("w2_lengthscale", length_scale_2)
	shader_material.set_shader_parameter("w3_lengthscale", length_scale_3)

	shader_material.get_shader_parameter("w1_displacement").texture_rd_rid = ws1.displacement
	shader_material.get_shader_parameter("w1_derivatives").texture_rd_rid = ws2.derivatives
	shader_material.get_shader_parameter("w1_turbulence").texture_rd_rid = ws1.turbulence

	shader_material.get_shader_parameter("w2_displacement").texture_rd_rid = ws2.displacement
	shader_material.get_shader_parameter("w2_derivatives").texture_rd_rid = ws2.derivatives
	shader_material.get_shader_parameter("w2_turbulence").texture_rd_rid = ws2.turbulence

	shader_material.get_shader_parameter("w3_displacement").texture_rd_rid = ws3.displacement
	shader_material.get_shader_parameter("w3_derivatives").texture_rd_rid = ws3.derivatives
	shader_material.get_shader_parameter("w3_turbulence").texture_rd_rid = ws3.turbulence


func create_gaussian_noise_texture() -> RID:

	var gaussian_noise: Image = Image.create(texture_size, texture_size, false, Image.FORMAT_RGF)
	for i: int in range(0, texture_size):
		for j: int in range(0, texture_size):
			gaussian_noise.set_pixel(i, j, Color(randfn(0.5, 0.5), randfn(0.5, 0.5), 0.0))

	var texture_format: RDTextureFormat = RDTextureFormat.new()
	texture_format.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	texture_format.width = texture_size
	texture_format.height = texture_size
	texture_format.usage_bits = (
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT +
			RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT +
			RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)

	return rd.texture_create(texture_format, RDTextureView.new(), [gaussian_noise.get_data()])



func _exit_tree() -> void:
	ws1.cleanup_gpu()
	ws2.cleanup_gpu()
	ws3.cleanup_gpu()
	fft.cleanup_gpu()
	rd.free()
