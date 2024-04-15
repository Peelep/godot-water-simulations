class_name WaveParameters extends Resource

@export var gravity: float = 9.81
@export var depth: float = 500.0
@export_range(0.0, 1.0) var lambda: float = 1.0
@export var local: WaveSettings = null
@export var swell: WaveSettings = null



func calculate_settings() -> void:
	calculate_internal_settings(local)
	calculate_internal_settings(swell)

func calculate_internal_settings(settings: WaveSettings) -> void:
	settings.jonswap_gamma = settings.wave_peak_enhancement
	settings.angle = deg_to_rad(settings.wind_direction)
	settings.swell = clampf(settings.swell, 0.01, 1.0)
	settings.jonswap_alpha = calculate_jonswap_alpha(settings)
	settings.jonswap_peak_omega = jonswap_peak_frequency(settings)

## https://wikiwaves.org/Ocean-Wave_Spectra
func calculate_jonswap_alpha(settings: WaveSettings) -> float:
	return 0.076 * pow(gravity * settings.fetch / settings.wind_speed / settings.wind_speed, -0.22)

## https://wikiwaves.org/Ocean-Wave_Spectra
func jonswap_peak_frequency(settings: WaveSettings) -> float:
	return 22 * pow(settings.wind_speed * settings.fetch / gravity / gravity, -0.33)
