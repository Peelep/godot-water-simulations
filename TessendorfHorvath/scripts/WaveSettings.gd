class_name WaveSettings extends Resource

@export_range(0.0, 1.0) var scale: float = 1.0
@export var wind_speed: float = 0.5
@export var wind_direction: float = 1.0
@export var fetch: float = 100000.0
@export_range(0.0, 1.0) var spread_blend: float = 1.0
@export_range(0.0, 1.0) var swell: float = 1.0
@export var short_waves_fade: float = 0.01

## Wave data from the JONSWAP experiment determined this to be 3.3
@export var wave_peak_enhancement: float = 3.3

# Internal variables calculated based on exports.
var angle: float = 0.0
var jonswap_alpha: float = 0.0
var jonswap_peak_omega: float = 0.0
var jonswap_gamma: float = 3.3
