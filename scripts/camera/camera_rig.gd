class_name CameraRig
extends Node3D
## PSO-style follow camera with Dark Souls-style lock-on.
##
## Follow modes:
##   LOOSE (default): the camera trails the Seeker like someone walking behind
##     them with a camera on a leash. It doesn't turn when the Seeker turns; it
##     only swings around as the Seeker walks away from it. Walk toward it and it
##     backs up. leash_radius sets how lazily it swings.
##   RIGID: the camera keeps its angle until you turn it (third-person shooter style).
##
## Layout: CameraRig (follows the player, rotates for yaw) > Pitch > SpringArm3D > Camera3D
##
## Lock-on (R3): picks the lockable target closest to where the camera faces.
## With nothing in range, R3 recenters the camera behind the Seeker instead.
## The recenter angle is captured when R3 is pressed, so turning during the
## recenter doesn't make the camera chase a moving angle.
## While locked, flicking the right stick (or sweeping the mouse) switches to the
## next target on that side of the screen.
##
## Anything in the "lockable" group can be targeted. If it has a
## get_lock_point() method, the camera aims there; otherwise 1 m above its origin.

signal lock_target_changed(target: Node3D)

const WORLD_MASK := 1

enum FollowMode { LOOSE, RIGID }

@export_group("Framing")
@export var follow_mode: FollowMode = FollowMode.LOOSE
## LOOSE mode only. Bigger = the camera swings around more lazily.
@export var leash_radius := 4.5
@export var pivot_height := 1.55
## Sideways camera offset. 0 keeps the Seeker centred (Grayson, 2026-11-08):
## twin SyncAIDa float on both shoulders, so neither side is favoured.
@export var shoulder_offset := 0.0
@export var distance := 4.5
## Positional lag. Lower = looser, more like a person keeping up.
@export var follow_speed := 9.0
## Lower than follow_speed so jumps don't jerk the camera.
@export var vertical_follow_speed := 6.0

@export_group("Look")
## Right-stick turn speed in radians per second (yaw, pitch).
@export var stick_speed := Vector2(3.2, 2.2)
@export var mouse_sensitivity := 0.0025
@export var invert_y := false
@export var default_pitch_deg := -20.0
@export var min_pitch_deg := -65.0
@export var max_pitch_deg := 35.0
@export var recenter_speed := 14.0
## Seconds after the last manual up/down look before the camera eases back to
## default_pitch_deg. Set to a negative number to turn this off.
@export var pitch_return_delay := 0.8
@export var pitch_return_speed := 2.5

@export_group("Lock-on")
@export var lock_range := 22.0
@export var lock_break_range := 28.0
## When the locked target dies, lock the next closest one.
@export var retarget_on_kill := true
## Targets further than this from the camera's facing are ignored.
@export var lock_max_angle_deg := 75.0
@export var lock_turn_speed := 10.0
@export var lock_pitch_offset_deg := -18.0
@export var switch_stick_threshold := 0.7
@export var switch_mouse_pixels := 80.0
## Lock-on and the retarget after a kill only pick targets on screen, within
## this fraction of the way from the centre to each edge (Grayson,
## 2026-11-09: less aggressive, no turning to something behind you).
@export_range(0.1, 1.0) var lock_screen_fraction := 0.75
## The simple sphere marker. Off when TargetMarkers draws the lock-on ring.
@export var show_lock_marker := true

var player: Player
var lock_target: Node3D = null
## What the player actually sees through this camera (a split-screen pane sets
## these each frame; 0 = this camera's own FOV and its viewport's shape).
var view_fov := 0.0
var view_aspect := 0.0

var _yaw := 0.0
var _pitch := 0.0
var _recentering := false
var _recenter_yaw := 0.0
var _since_manual_pitch := 0.0
var _switch_armed := true
var _mouse_switch_accum := 0.0

@onready var _pitch_pivot: Node3D = $Pitch
@onready var _spring_arm: SpringArm3D = $Pitch/SpringArm3D
@onready var camera: Camera3D = $Pitch/SpringArm3D/Camera3D
@onready var _marker: Node3D = $LockMarker


func setup(seeker: Player) -> void:
	player = seeker
	_spring_arm.add_excluded_object(seeker.get_rid())
	_yaw = seeker.rotation.y
	_pitch = deg_to_rad(default_pitch_deg)
	global_position = _player_pivot()
	_apply_rotation()


func get_flat_forward() -> Vector3:
	var forward := -global_basis.z
	forward.y = 0.0
	return forward.normalized()


func get_debug_text() -> String:
	return "Lock-on: %s" % (lock_target.name if is_instance_valid(lock_target) else "none")


static func get_lock_point(node: Node3D) -> Vector3:
	if node.has_method("get_lock_point"):
		return node.call("get_lock_point")
	return node.global_position + Vector3.UP


# --- Input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Part 12: only this Seeker's devices turn this camera (the mouse belongs
	# to the leader).
	if player == null or not player.input.owns(event) or not player.input.uses_mouse():
		return
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if event is InputEventMouseButton and event.is_pressed() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		if lock_target:
			_mouse_switch_accum += motion.relative.x
		else:
			_recentering = false
			_yaw -= motion.relative.x * mouse_sensitivity
			_pitch -= motion.relative.y * mouse_sensitivity * (-1.0 if invert_y else 1.0)
			if absf(motion.relative.y) > 0.0:
				_since_manual_pitch = 0.0


# --- Lock-on (physics step, because it raycasts) ----------------------------

func _physics_process(delta: float) -> void:
	if player == null:
		return

	var locked_out: bool = player is Player and (player as Player).input_locked
	if player.input.just_pressed("lock_on") and not locked_out:
		_toggle_lock()

	_validate_lock()

	if lock_target and not locked_out:
		_handle_switch_input(player.input.axis("look_left", "look_right"), delta)


func _toggle_lock() -> void:
	if lock_target:
		_set_lock(null)
		return
	var best := _find_best_target()
	if best:
		_set_lock(best)
	else:
		_recentering = true
		_recenter_yaw = player.rotation.y  # Fixed at press time.


func _set_lock(target: Node3D) -> void:
	if target == lock_target:
		return
	lock_target = target
	_since_manual_pitch = 0.0
	_marker.visible = target != null and show_lock_marker
	_mouse_switch_accum = 0.0
	lock_target_changed.emit(target)


func _validate_lock() -> void:
	if lock_target == null:
		return
	# The target died or went away: move on to the next closest one (Grayson,
	# 2026-11-09), or drop the lock when nothing is left in range.
	if not is_instance_valid(lock_target) or not lock_target.is_inside_tree() \
			or not lock_target.is_in_group("lockable") or not lock_target.is_visible_in_tree():
		var gone := lock_target if is_instance_valid(lock_target) else null
		# Same rules as pressing lock-on, so it never swings to something
		# behind you or far off screen.
		_set_lock(_find_best_target(gone) if retarget_on_kill else null)
		return
	if _player_center().distance_to(get_lock_point(lock_target)) > lock_break_range:
		_set_lock(null)


## Whether a point is within lock_screen_fraction of the screen centre (and in
## front of the camera).
func is_near_screen_centre(point: Vector3) -> bool:
	var local := camera.global_transform.affine_inverse() * point
	if local.z >= -0.1:
		return false  # behind the camera
	var fov := deg_to_rad(view_fov if view_fov > 0.0 else camera.fov)
	var aspect := view_aspect
	if aspect <= 0.0:
		var rect := get_viewport().get_visible_rect().size
		aspect = rect.x / maxf(rect.y, 1.0)
	var half_h := tan(fov / 2.0)
	var x := (local.x / -local.z) / (half_h * aspect)
	var y := (local.y / -local.z) / half_h
	return absf(x) <= lock_screen_fraction and absf(y) <= lock_screen_fraction


func _find_best_target(exclude: Node3D = null) -> Node3D:
	var origin := _player_center()
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var max_angle := deg_to_rad(lock_max_angle_deg)

	var best: Node3D = null
	var best_score := INF
	for node in Scope.group(self, "lockable"):
		var candidate := node as Node3D
		if candidate == null or candidate == exclude or not candidate.is_visible_in_tree():
			continue
		var point := get_lock_point(candidate)
		var to := point - origin
		var dist := to.length()
		if dist > lock_range or not is_near_screen_centre(point):
			continue
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length_squared() < 0.01:
			continue
		var angle := forward.angle_to(flat.normalized())
		if angle > max_angle:
			continue
		if not _has_line_of_sight(origin, point):
			continue
		# Facing matters most, distance breaks ties.
		var score := (angle / max_angle) * 2.0 + dist / lock_range
		if score < best_score:
			best_score = score
			best = candidate
	return best


## The closest lockable target in range and in sight, any direction (used
## when the locked target dies).
func _find_nearest_target(exclude: Node3D = null) -> Node3D:
	var origin := _player_center()
	var best: Node3D = null
	var best_dist := INF
	for node in Scope.group(self, "lockable"):
		var candidate := node as Node3D
		if candidate == null or candidate == exclude or not candidate.is_visible_in_tree():
			continue
		var point := get_lock_point(candidate)
		var dist := origin.distance_to(point)
		if dist > lock_range or dist >= best_dist:
			continue
		if not _has_line_of_sight(origin, point):
			continue
		best_dist = dist
		best = candidate
	return best


func _handle_switch_input(look_x: float, delta: float) -> void:
	if absf(look_x) < 0.3:
		_switch_armed = true
	elif _switch_armed and absf(look_x) > switch_stick_threshold:
		_switch_armed = false
		_switch_target(signf(look_x))

	if absf(_mouse_switch_accum) > switch_mouse_pixels:
		_switch_target(signf(_mouse_switch_accum))
		_mouse_switch_accum = 0.0
	_mouse_switch_accum = move_toward(_mouse_switch_accum, 0.0, 200.0 * delta)


## Switch to the nearest target on the given side of the screen (-1 left, 1 right).
func _switch_target(side: float) -> void:
	var current_x := camera.unproject_position(get_lock_point(lock_target)).x
	var origin := _player_center()
	var best: Node3D = null
	var best_dx := INF
	for node in Scope.group(self, "lockable"):
		var candidate := node as Node3D
		if candidate == null or candidate == lock_target or not candidate.is_visible_in_tree():
			continue
		var point := get_lock_point(candidate)
		if origin.distance_to(point) > lock_range or camera.is_position_behind(point):
			continue
		if not _has_line_of_sight(origin, point):
			continue
		var dx := (camera.unproject_position(point).x - current_x) * side
		if dx > 1.0 and dx < best_dx:
			best_dx = dx
			best = candidate
	if best:
		_set_lock(best)


func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	query.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- Camera motion (render step, for smoothness) ----------------------------

func _process(delta: float) -> void:
	if player == null:
		return

	# Where the "camera operator" stood before the Seeker moved this frame.
	var trail := _leash_point()
	_follow(delta)

	if is_instance_valid(lock_target):
		_recentering = false
		_track_lock_target(delta)
	else:
		if follow_mode == FollowMode.LOOSE and not _recentering:
			_apply_leash(trail)
		_free_look(delta)

	_pitch = clampf(_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	_apply_rotation()
	_update_marker()


func _leash_point() -> Vector3:
	return global_position + Vector3(sin(_yaw), 0.0, cos(_yaw)) * leash_radius


## Turn so the camera stays where it was standing, only dragged along by the
## Seeker. Moving away pulls it around behind; turning on the spot does nothing.
func _apply_leash(trail: Vector3) -> void:
	var offset := trail - global_position
	offset.y = 0.0
	if offset.length_squared() < 0.01:
		return
	_yaw = atan2(offset.x, offset.z)


func _free_look(delta: float) -> void:
	var look := player.input.vector("look_left", "look_right", "look_up", "look_down") if player else Vector2.ZERO
	if player is Player and (player as Player).input_locked:
		look = Vector2.ZERO
	if look != Vector2.ZERO:
		_recentering = false
		_yaw -= look.x * stick_speed.x * delta
		_pitch -= look.y * stick_speed.y * delta * (-1.0 if invert_y else 1.0)
	if absf(look.y) > 0.0:
		_since_manual_pitch = 0.0
	else:
		_since_manual_pitch += delta
		if pitch_return_delay >= 0.0 and _since_manual_pitch > pitch_return_delay and not _recentering:
			_pitch = lerp_angle(_pitch, deg_to_rad(default_pitch_deg), 1.0 - exp(-pitch_return_speed * delta))

	if _recentering:
		var t := 1.0 - exp(-recenter_speed * delta)
		_yaw = lerp_angle(_yaw, _recenter_yaw, t)
		_pitch = lerpf(_pitch, deg_to_rad(default_pitch_deg), t)
		if absf(angle_difference(_yaw, _recenter_yaw)) < 0.01:
			_yaw = _recenter_yaw
			_recentering = false


func _track_lock_target(delta: float) -> void:
	var to := get_lock_point(lock_target) - global_position
	var flat_dist := Vector2(to.x, to.z).length()
	if flat_dist < 0.5:
		return
	var desired_yaw := atan2(-to.x, -to.z)
	var desired_pitch := atan2(to.y, flat_dist) + deg_to_rad(lock_pitch_offset_deg)
	var t := 1.0 - exp(-lock_turn_speed * delta)
	_yaw = lerp_angle(_yaw, desired_yaw, t)
	_pitch = lerp_angle(_pitch, desired_pitch, t)


func _apply_rotation() -> void:
	rotation = Vector3(0.0, _yaw, 0.0)
	_pitch_pivot.rotation = Vector3(_pitch, 0.0, 0.0)
	_spring_arm.spring_length = distance
	_spring_arm.position.x = shoulder_offset


func _follow(delta: float) -> void:
	var goal := _player_pivot()
	var pos := global_position
	var t_flat := 1.0 - exp(-follow_speed * delta)
	var t_vertical := 1.0 - exp(-vertical_follow_speed * delta)
	pos.x = lerpf(pos.x, goal.x, t_flat)
	pos.z = lerpf(pos.z, goal.z, t_flat)
	pos.y = lerpf(pos.y, goal.y, t_vertical)
	global_position = pos


func _update_marker() -> void:
	if is_instance_valid(lock_target):
		_marker.global_position = get_lock_point(lock_target)


func _player_pivot() -> Vector3:
	# Interpolated position, because the camera moves every rendered frame.
	return player.get_global_transform_interpolated().origin + Vector3.UP * pivot_height


func _player_center() -> Vector3:
	return player.global_position + Vector3.UP * 1.2
