class_name TargetMarkers
extends Node3D
## PSU-style target cursors, one color per hand.
##
## Small rings sit on every enemy each hand's next attack would hit (from
## CombatController.predict_targets): blue for the primary hand, yellow for the
## off hand, green when both hands would hit the same enemy. So you can see a
## Great Sword sweep catching two enemies, or a piercing spell lining up three.
## The locked-on enemy also gets a larger red ring, dimmed when neither hand's
## next attack would reach it.

enum { RIGHT_BIT = 1, LEFT_BIT = 2 }

const SMALL_SIZE := 0.55
const LARGE_SIZE := 1.1
const RIGHT_COLOR := Color(0.3, 0.6, 1.0, 0.95)
const LEFT_COLOR := Color(1.0, 0.85, 0.3, 0.95)
const BOTH_COLOR := Color(0.35, 1.0, 0.45, 0.95)
const LOCK_COLOR := Color(1.0, 0.35, 0.2, 0.95)

var combat: CombatController
var camera_rig: CameraRig

var _small_texture: Texture2D
var _large_texture: Texture2D
var _pool: Array[Sprite3D] = []
var _lock_marker: Sprite3D
var _time := 0.0
## target -> RIGHT_BIT | LEFT_BIT, as of the last physics frame.
var _hands_on: Dictionary = {}


func setup(controller: CombatController, rig: CameraRig) -> void:
	combat = controller
	camera_rig = rig
	top_level = true
	_small_texture = _ring_texture(64, 6.0, true)
	_large_texture = _ring_texture(128, 7.0, false)
	_lock_marker = _make_sprite(_large_texture, LARGE_SIZE, LOCK_COLOR)


## Enemies currently marked, with which hands would hit them (for tests).
func get_marked() -> Dictionary:
	return _hands_on.duplicate()


static func color_for(bits: int) -> Color:
	if bits == RIGHT_BIT | LEFT_BIT:
		return BOTH_COLOR
	return RIGHT_COLOR if bits == RIGHT_BIT else LEFT_COLOR


func is_lock_marker_visible() -> bool:
	return _lock_marker != null and _lock_marker.visible


func _physics_process(delta: float) -> void:
	if combat == null:
		return
	_time += delta
	_hands_on.clear()
	for target in combat.predict_targets(CombatController.Hand.RIGHT):
		_hands_on[target] = _hands_on.get(target, 0) | RIGHT_BIT
	for target in combat.predict_targets(CombatController.Hand.LEFT):
		_hands_on[target] = _hands_on.get(target, 0) | LEFT_BIT

	var used := 0
	for target in _hands_on:
		if used >= _pool.size():
			_pool.append(_make_sprite(_small_texture, SMALL_SIZE, RIGHT_COLOR))
		var sprite := _pool[used]
		sprite.visible = true
		sprite.modulate = color_for(_hands_on[target])
		sprite.global_position = CameraRig.get_lock_point(target)
		used += 1
	for i in range(used, _pool.size()):
		_pool[i].visible = false

	var lock_target: Node3D = camera_rig.lock_target if is_instance_valid(camera_rig.lock_target) else null
	_lock_marker.visible = lock_target != null
	if lock_target:
		_lock_marker.global_position = CameraRig.get_lock_point(lock_target)
		var pulse := 1.0 + 0.08 * sin(_time * 6.0)
		_lock_marker.scale = Vector3.ONE * pulse
		_lock_marker.modulate = LOCK_COLOR if _hands_on.has(lock_target) else Color(LOCK_COLOR, 0.45)


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
