extends Node3D

## Fps is capped to monitor refresh rate by default, that can be changed by disabling vsync.
@export var vsync: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED

## If true, prints out all generated variables to the console.
@export var print_generated_params: bool = true

## Wave algorithm that is used. Steep sine gives the waves sharper peaks and wider troughs
## using the steepness variable that is otherwise ignored.
@export_enum("Sine", "Steep Sine", "Gerstner") var wave_type: String = "Sine"

@export_range(0, 100) var wave_amount: int = 5

@export_group("Wave Generator Parameters")
## degrees
@export_range(0.0, 360.0) var median_direction:  float = 0.0
## degrees
@export_range(0.0, 360.0) var direction_range:   float = 20.0
## meters
@export var median_wavelength: float = 0.5
## meters
@export var wavelength_range:  float = 0.6
## meters per second
@export var median_speed:      float = 0.3
## meters per second
@export var speed_range:       float = 0.5
## meters
@export var median_amplitude:  float = 0.2
## exponential mystery unit
@export var steepness:         float = 2.5

@export_group("Light Paremeters")
@export var water_color: Color = Color.ROYAL_BLUE
@export var specular_color: Color = Color.WHITE
@export var specular_shininess: float = 6.0
@export var fresnel_color: Color = Color.WHITE
@export var fresnel_shininess: float = 5.0
@export var tip_color: Color = Color.WHITE
@export var tip_attenuation: float = 1.0


var shader_material: ShaderMaterial = preload("res://GPUGems1Ch1/materials/SumOfSinesWaterPlane.material")

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(vsync)
	randomize() # sets a random seed for all random number generators.
	make_waves_and_update_shader()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		make_waves_and_update_shader()

# This function converts color to a vector3 by removing the alpha channel.
func color_to_vec3(color: Color) -> Vector3:
	return Vector3(color.r, color.g, color.b)

func make_waves_and_update_shader() -> void:
	var wavelength_min: float = median_wavelength / (1.0 + wavelength_range)
	var wavelength_max: float = median_wavelength * (1.0 + wavelength_range)
	var direction_min:  float = median_direction - direction_range
	var direction_max:  float = median_direction + direction_range
	var speed_min:      float = max(0.01, median_speed - speed_range)
	var speed_max:      float = median_speed + speed_range

	var wave_params: Array[float] = []

	for i: int in range(0, wave_amount): # Generate 10 random waves, changing this requires changes to the shader.
		var speed: float = randf_range(speed_min, speed_max) # not sent to shader
		var wavelength: float = randf_range(wavelength_min, wavelength_max) # not sent to shader

		var amplitude: float = median_amplitude * (median_amplitude / median_wavelength)
		var frequency: float = 2.0 / wavelength
		var phase_speed: float = speed * frequency

		var direction: float = randf_range(direction_min, direction_max)
		var dir_vec: Vector2 = Vector2(cos(deg_to_rad(direction)), sin(deg_to_rad(direction))).normalized()

		wave_params.append_array([
			dir_vec.x,
			dir_vec.y,
			amplitude,
			frequency,
			phase_speed,
			steepness
			])

	shader_material.set_shader_parameter("wave_params", wave_params)

	# Set the lighting uniforms.
	shader_material.set_shader_parameter("water_color", color_to_vec3(water_color))
	shader_material.set_shader_parameter("specular_color", color_to_vec3(specular_color))
	shader_material.set_shader_parameter("specular_shininess", specular_shininess)
	shader_material.set_shader_parameter("fresnel_color", color_to_vec3(fresnel_color))
	shader_material.set_shader_parameter("fresnel_shininess", fresnel_shininess)
	shader_material.set_shader_parameter("tip_color", color_to_vec3(tip_color))
	shader_material.set_shader_parameter("tip_attenuation", tip_attenuation)

	shader_material.set_shader_parameter("sun_dir", $"DirectionalLight3D".global_transform.basis.z)

	if wave_type == "Gerstner":
		shader_material.set_shader_parameter("use_gerstner", true)
		shader_material.set_shader_parameter("use_steep_sine", false)
	elif wave_type == "Steep Sine":
		shader_material.set_shader_parameter("use_gerstner", false)
		shader_material.set_shader_parameter("use_steep_sine", true)
	else:
		shader_material.set_shader_parameter("use_gerstner", false)
		shader_material.set_shader_parameter("use_steep_sine", false)

	if print_generated_params:
		print(wave_params)
