class_name TargetMarkers
extends Node3D
## PSU-style target cursors.
##
## Small rings sit on every enemy your next attack would hit (from
## CombatController.predict_targets), so you can see a Great Sword sweep
## catching two enemies or a piercing spell lining up three. The locked-on
## enemy gets a larger ring instead.

const SMALL_SIZE := 0.55
const LARGE_SIZE := 1.1
const SMALL_COLOR := Color(1.0, 0.85, 0.3, 0.9)
const LARGE_COLOR := Color(1.0, 0.4, 0.2, 0.95)

var combat: CombatController
var camera_rig: CameraRig

var _small_texture: Texture2D
var _large_texture: Texture2D
var _pool: Array[Sprite3D] = []
var _lock_marker: Sprite3D
var _time := 0.0


func setup(controller: CombatController, rig: CameraRig) -> void:
	combat = controller
	camera_rig = rig
	top_level = true
	_small_texture = _ring_texture(64, 6.0, true)
	_large_texture = _ring_texture(128, 7.0, false)
	_lock_marker = _make_sprite(_large_texture, LARGE_SIZE, LARGE_COLOR)


## Enemies currently showing a small marker (for tests and debugging).
func get_marked() -> Array[Node3D]:
	var marked: Array[Node3D] = []
	for sprite in _pool:
		if sprite.visible and sprite.has_meta("target"):
			marked.append(sprite.get_meta("target"))
	return marked


func is_lock_marker_visible() -> bool:
	return _lock_marker != null and _lock_marker.visible


func _physics_process(delta: float) -> void:
	if combat == null:
		return
	_time += delta
	var lock_target: Node3D = camera_rig.lock_target if is_instance_valid(camera_rig.lock_target) else null
	var targets := combat.predict_targets()

	var used := 0
	for target in targets:
		if target == lock_target:
			continue
		if used >= _pool.size():
			_pool.append(_make_sprite(_small_texture, SMALL_SIZE, SMALL_COLOR))
		var sprite := _pool[used]
		sprite.visible = true
		sprite.set_meta("target", target)
		sprite.global_position = CameraRig.get_lock_point(target)
		used += 1
	for i in range(used, _pool.size()):
		_pool[i].visible = false
		_pool[i].remove_meta("target")

	_lock_marker.visible = lock_target != null
	if lock_target:
		_lock_marker.global_position = CameraRig.get_lock_point(lock_target)
		# Brighter pulse when the next attack will actually connect.
		var hits := lock_target in targets
		var pulse := 1.0 + 0.08 * sin(_time * 6.0)
		_lock_marker.scale = Vector3.ONE * pulse
		_lock_marker.modulate = LARGE_COLOR if hits else Color(LARGE_COLOR, 0.45)


func _make_sprite(texture: Texture2D, world_size: float, color: Color) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.pixel_size = world_size / float(texture.get_width())
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.render_priority = 3
	sprite.modulate = color
	sprite.visible = false
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sprite)
	return sprite


## A white ring drawn into a texture. gaps = four notches like a PSU cursor;
## otherwise a double ring for the lock-on marker.
static func _ring_texture(size: int, thickness: float, gaps: bool) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	var outer := c - 1.0
	for y in size:
		for x in size:
			var dx := x - c
			var dy := y - c
			var d := sqrt(dx * dx + dy * dy)
			var a := clampf(minf(outer - d, d - (outer - thickness)) + 0.5, 0.0, 1.0)
			if not gaps:
				var inner := outer * 0.55
				a = maxf(a, clampf(minf(inner - d, d - (inner - thickness * 0.6)) + 0.5, 0.0, 1.0))
			elif a > 0.0:
				var angle := fposmod(rad_to_deg(atan2(dy, dx)), 90.0)
				if angle > 35.0 and angle < 55.0:
					a = 0.0
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)
