extends Node3D


@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var sunlight: DirectionalLight3D = $Sunlight
@onready var moonlight: DirectionalLight3D = $Moonlight

var time: float = 0
const day_len_in_seconds: float = 300

func _process(delta: float):
	time += delta
	#time = 35 # Lock to morning
	
	var time_percent: float = fposmod(time, day_len_in_seconds) / day_len_in_seconds
	_update_sky(time_percent)
	_update_sun_and_moon(time_percent)

#region sun / moon
@export var sun_color_gradient: GradientTexture1D
@export var moon_color_gradient: GradientTexture1D

func _update_sun_and_moon(time_percent: float):
	var sky_material = world_environment.environment.sky.sky_material
	
	# 1. Rotate the lights (Opposite each other)
	var sun_rotation = fposmod(time_percent * TAU, TAU) + (PI / 2)
	sunlight.rotation.x = sun_rotation

	# Keep the moon exactly opposite the sun
	moonlight.rotation.x = sun_rotation + PI 

	# 2. Update Shader Uniforms
	# We use -basis.z because that is the "Forward" direction of the light
	var sun_dir = -sunlight.global_transform.basis.z
	var moon_dir = -moonlight.global_transform.basis.z

	sky_material.set_shader_parameter("sun_direction", -sun_dir)
	sky_material.set_shader_parameter("moon_direction", -moon_dir)
	
	moonlight.light_color = moon_color_gradient.gradient.sample(time_percent)
	sunlight.light_color = sun_color_gradient.gradient.sample(time_percent)

	# 3. Handle Light Intensity (Don't want both on at once!)
	# If the sun is below the horizon, turn it down and turn the moon up
	var sun_altitude = sun_dir.y 
	sunlight.light_energy = clamp(-sun_altitude * 2.0, 0.0, 2.0)
	moonlight.light_energy = clamp(sun_altitude * 2.0, 0.0, 0.5) # Moon is dimmer
	
	# 4. Set moon crescent-ness
	sky_material.set_shader_parameter("moon_crescent_offset", fposmod(time / (day_len_in_seconds * 17), 0.2) - 0.1)
#endregion

#region sky
@export var zenith_gradient: GradientTexture1D
@export var horizon_gradient: GradientTexture1D
@export var ground_gradient: GradientTexture1D

# Simple logic for your _process loop
func _update_sky(time_percent: float):
	var sky_material = world_environment.environment.sky.sky_material
	
	sky_material.set_shader_parameter("zenith_color", zenith_gradient.gradient.sample(time_percent))
	sky_material.set_shader_parameter("horizon_color", horizon_gradient.gradient.sample(time_percent))
	sky_material.set_shader_parameter("ground_color", ground_gradient.gradient.sample(time_percent))
#endregion
