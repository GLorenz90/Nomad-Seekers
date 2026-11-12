class_name DarkVision
extends MeshInstance3D
## One Seeker's sight in a darkness room (RoomHazard.DARKNESS; Grayson
## 2026-11-11: a real distance limit instead of a vignette). A full-screen
## quad blacks out everything past the room's `sight_range` from the Seeker.
## It sits on the Seeker's marker layer (TargetMarkers.render_layers), so in
## split screen only their own pane draws it. Lock-on still reaches past it,
## and the rings draw on top.

const SHADER := preload("res://shaders/dark_vision.gdshader")
## How fast the dark closes in or lifts (per second, 0..1).
const FADE_SPEED := 2.5
## Height of the sight centre above the Seeker's feet.
const EYE_HEIGHT := 1.0

var seeker: Player
## 0 = clear, 1 = full darkness (eases in and out).
var strength := 0.0
var _material: ShaderMaterial
var _radius := RoomHazard.DEFAULT_SIGHT


func _init() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.render_priority = 1  # under damage numbers (2) and target rings (3)
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The quad is moved to the screen in the vertex shader: never cull it.
	custom_aabb = AABB(Vector3(-1.0e5, -1.0e5, -1.0e5), Vector3(2.0e5, 2.0e5, 2.0e5))
	top_level = true
	visible = false


func setup(who: Player) -> void:
	seeker = who


func _process(delta: float) -> void:
	if seeker == null or not is_instance_valid(seeker):
		visible = false
		return
	var range_m := RoomHazard.sight_range_for(seeker)
	if range_m > 0.0:
		_radius = range_m
	strength = move_toward(strength, 1.0 if range_m > 0.0 else 0.0, delta * FADE_SPEED)
	visible = strength > 0.0
	if not visible:
		return
	global_position = seeker.global_position
	_material.set_shader_parameter("center", seeker.global_position + Vector3.UP * EYE_HEIGHT)
	_material.set_shader_parameter("radius", _radius)
	_material.set_shader_parameter("strength", strength)
