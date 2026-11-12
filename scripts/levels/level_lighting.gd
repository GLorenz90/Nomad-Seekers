class_name LevelLighting
extends RefCounted
## A data level's sky, sun and ambient light (Part 13a, level editor Layer 1).
## Presets plus a few sliders, each kept inside LevelData.LIGHT_LIMITS so no
## level is too dark to see or annoyingly bright (Grayson, 2026-11-12). A
## room that's meant to be dark uses the Darkness hazard instead.
##
## map.json "lighting":
##   {"preset": "dusk", "sun_energy": 1.0, "ambient_energy": 1.0,
##    "exposure": 1.0, "fog_density": 0.0, "sun_angle": [-50, 35],
##    "tint": [1, 1, 1]}

const PRESETS := {
	"day": {"top": Color(0.32, 0.5, 0.82), "horizon": Color(0.72, 0.78, 0.85),
		"sun": Color(1.0, 0.97, 0.9), "sun_energy": 1.0, "ambient": 1.0, "angle": [-55.0, 35.0]},
	"dusk": {"top": Color(0.28, 0.25, 0.45), "horizon": Color(0.95, 0.55, 0.35),
		"sun": Color(1.0, 0.7, 0.45), "sun_energy": 0.8, "ambient": 0.85, "angle": [-15.0, 60.0]},
	"overcast": {"top": Color(0.5, 0.53, 0.58), "horizon": Color(0.68, 0.7, 0.72),
		"sun": Color(0.9, 0.92, 0.95), "sun_energy": 0.45, "ambient": 1.15, "angle": [-65.0, 20.0]},
	"night": {"top": Color(0.04, 0.06, 0.14), "horizon": Color(0.12, 0.16, 0.28),
		"sun": Color(0.6, 0.7, 1.0), "sun_energy": 0.35, "ambient": 0.75, "angle": [-40.0, -30.0]},
	"cave": {"top": Color(0.08, 0.08, 0.1), "horizon": Color(0.16, 0.15, 0.16),
		"sun": Color(0.85, 0.75, 0.6), "sun_energy": 0.3, "ambient": 0.8, "angle": [-80.0, 0.0]},
	"interior": {"top": Color(0.3, 0.32, 0.36), "horizon": Color(0.45, 0.45, 0.48),
		"sun": Color(1.0, 0.95, 0.88), "sun_energy": 0.4, "ambient": 1.1, "angle": [-75.0, 10.0]},
}


## Builds the WorldEnvironment and sun for a level's lighting.
static func build(lighting: Dictionary) -> Array[Node]:
	var l := LevelData.clamp_lighting(lighting)
	var p: Dictionary = PRESETS[l.preset]
	var tint := Color.WHITE
	if lighting.get("tint") is Array and (lighting.tint as Array).size() >= 3:
		var t: Array = lighting.tint
		# A tint can colour the light but never darken it much.
		tint = Color(clampf(float(t[0]), 0.6, 1.0), clampf(float(t[1]), 0.6, 1.0),
			clampf(float(t[2]), 0.6, 1.0))

	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = p.top
	sky_mat.sky_horizon_color = p.horizon
	sky_mat.ground_horizon_color = p.horizon
	sky_mat.ground_bottom_color = (p.horizon as Color).darkened(0.5)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = float(p.ambient) * float(l.ambient_energy)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = float(l.exposure)
	e.ssao_enabled = true
	if float(l.fog_density) > 0.0:
		e.fog_enabled = true
		e.fog_density = float(l.fog_density)
		e.fog_light_color = p.horizon
	env.environment = e

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.light_color = (p.sun as Color) * tint
	sun.light_energy = float(p.sun_energy) * float(l.sun_energy)
	var angle: Array = lighting.get("sun_angle", p.angle)
	if angle.size() >= 2:
		# Never flat or from below: keep the sun 10-90 degrees up.
		sun.rotation_degrees = Vector3(clampf(float(angle[0]), -90.0, -10.0), float(angle[1]), 0.0)
	return [env, sun]


## Decoration lights: kept within a sane range and brightness.
static func point_light(color: Color, energy: float, light_range: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = clampf(energy, 0.0, 3.0)
	light.omni_range = clampf(light_range, 1.0, 20.0)
	return light
