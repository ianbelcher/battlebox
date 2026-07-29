class_name DayNight
extends Node3D
## Sky, sun, moon and the Forward+ environment. This is where the renderer
## gets to show off: real directional shadows, SSAO, glow, subtle volumetric
## fog, and (WORLD_MAXFX=1) SDFGI bounce light. The clock is replicated from
## the server; visuals slide smoothly as it advances.

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var environment: Environment
var sky_material: ProceduralSkyMaterial
var _clock := 0.35
var allow_shadows := true
## The GL Compatibility renderer (LITE mode) has no SSAO/GI, so it reads
## darker — boost light to keep the same friendly look.
var _gl_boost := 1.0

const DAY_TOP := Color("4a9de8")
const DAY_HORIZON := Color("bcd8ee")
const DUSK_TOP := Color("3a4a7a")
const DUSK_HORIZON := Color("f2a05e")
const NIGHT_TOP := Color("0a0e22")
const NIGHT_HORIZON := Color("1c2445")

func _ready() -> void:
	if RenderingServer.get_rendering_device() == null:
		_gl_boost = 1.45
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 120.0
	sun.shadow_bias = 0.03
	sun.light_color = Color(1.0, 0.96, 0.88)
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 90.0
	moon.light_color = Color(0.62, 0.72, 0.95)
	moon.light_energy = 0.0
	# Never draw a second (dark) sun disc for the moon in the sky.
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)

	sky_material = ProceduralSkyMaterial.new()
	sky_material.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 1.0
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 6.0
	environment.ssao_enabled = true
	environment.ssao_intensity = 1.6
	environment.ssao_radius = 1.6
	environment.glow_enabled = true
	environment.glow_intensity = 0.5
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.0
	# Depth fog softens the draw-distance edge exactly like Minecraft;
	# main retunes fog_depth_end whenever the player changes draw distance.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_curve = 1.6
	environment.fog_depth_begin = 70.0
	environment.fog_depth_end = 128.0
	# No volumetric fog ever: it fills an orthographic frustum with a flat
	# gray wash (verified). WORLD_MAXFX adds SDFGI bounce light only.
	if OS.get_environment("WORLD_MAXFX") == "1":
		environment.sdfgi_enabled = true
		environment.sdfgi_use_occlusion = true
		environment.sdfgi_cascades = 2
		environment.sdfgi_min_cell_size = 0.4
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)
	set_clock(_clock)

func set_clock(clock: float) -> void:
	_clock = clock

## Old-computer mode: drop the expensive post effects, keep the look.
func set_low_fx(low: bool) -> void:
	environment.ssao_enabled = not low
	environment.glow_enabled = not low
	sun.directional_shadow_max_distance = 60.0 if low else 120.0
	moon.shadow_enabled = false if low else moon.shadow_enabled

func _process(delta: float) -> void:
	_clock = fposmod(_clock + delta / WorldNode.day_seconds(), 1.0)
	_apply(_clock)

## clock: 0 midnight, 0.25 dawn, 0.5 noon, 0.75 dusk.
func _apply(clock: float) -> void:
	var sun_angle := (clock - 0.25) * TAU  # 0 at dawn
	var elevation := sin(sun_angle)
	sun.rotation = Vector3(-maxf(elevation, 0.02) * 1.35, 0.8 + cos(sun_angle) * 0.4, 0)
	# The sun keeps glowing a little past the horizon so dusk stays warm
	# instead of collapsing into a black trough before the moon takes over.
	var daylight := clampf(elevation * 2.2 + 0.3, 0.0, 1.0)
	sun.light_energy = daylight * 1.4 * _gl_boost
	sun.shadow_enabled = allow_shadows and daylight > 0.1
	var warmth := clampf(1.0 - elevation * 2.0, 0.0, 1.0)  # low sun = warm
	sun.light_color = Color(1.0, 0.96 - warmth * 0.25, 0.88 - warmth * 0.4)

	var moonlight := clampf(-elevation * 5.0, 0.0, 1.0)
	moon.rotation = Vector3(-maxf(-elevation, 0.02) * 1.2, -0.6, 0)
	moon.light_energy = moonlight * 0.4
	moon.shadow_enabled = allow_shadows and moonlight > 0.4

	var top: Color
	var horizon: Color
	if elevation > 0.15:
		top = DAY_TOP
		horizon = DAY_HORIZON
	elif elevation > -0.12:
		var mix := inverse_lerp(-0.12, 0.15, elevation)
		top = NIGHT_TOP.lerp(DUSK_TOP, mix).lerp(DAY_TOP, maxf(0.0, mix * 2.0 - 1.0))
		horizon = NIGHT_HORIZON.lerp(DUSK_HORIZON, mix).lerp(DAY_HORIZON, maxf(0.0, mix * 2.0 - 1.0))
	else:
		top = NIGHT_TOP
		horizon = NIGHT_HORIZON
	sky_material.sky_top_color = top
	sky_material.sky_horizon_color = horizon
	environment.fog_light_color = horizon
	# The below-horizon half fades gently from the horizon color instead
	# of a flat dark gray slab.
	sky_material.ground_bottom_color = horizon.darkened(0.25)
	sky_material.ground_horizon_color = horizon
	environment.ambient_light_energy = (0.72 + daylight * 0.28) * _gl_boost
