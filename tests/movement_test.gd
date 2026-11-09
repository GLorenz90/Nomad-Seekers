extends SceneTree
## Automated smoke test for Part 1. Loads the test room, drives the Seeker with
## simulated input, and checks movement, jump, dash, lock-on and recenter.
##
## Run from the project folder:
##   godot --headless --path . --script res://tests/movement_test.gd

var _main: Node
var _player: Player
var _rig: CameraRig
var _failures := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	_player = _main.get_node("Player")
	_rig = _main.get_node("CameraRig")
	await _frames(30)  # settle onto the floor

	_check("starts grounded", _player.state == Player.State.GROUND)

	# --- Walk forward 1 s ---
	var start := _player.global_position
	await _hold("move_forward", 60)
	var walked := _flat(_player.global_position - start)
	_check("walks ~7 m in 1 s (got %.2f)" % walked, walked > 5.5 and walked < 7.5)
	await _frames(20)
	_check("stops quickly after release", _flat_speed() < 0.5)

	# --- Jump height ---
	var floor_y := _player.global_position.y
	var peak := floor_y
	Input.action_press("jump")
	for i in 40:
		await physics_frame
		peak = maxf(peak, _player.global_position.y)
	Input.action_release("jump")
	await _frames(40)
	_check("full jump ~1.6 m (got %.2f)" % (peak - floor_y), absf(peak - floor_y - 1.6) < 0.2)
	_check("lands again", _player.state == Player.State.GROUND)

	# --- Short hop ---
	peak = _player.global_position.y
	floor_y = peak
	Input.action_press("jump")
	await _frames(3)
	Input.action_release("jump")
	for i in 40:
		await physics_frame
		peak = maxf(peak, _player.global_position.y)
	_check("tap gives a short hop (got %.2f)" % (peak - floor_y), peak - floor_y < 1.0)
	await _frames(20)

	# --- Dash ---
	start = _player.global_position
	await _tap("dash")
	await _frames(20)
	var dashed := _flat(_player.global_position - start)
	_check("dash covers ~4.5 m (got %.2f)" % dashed, dashed > 4.0 and dashed < 6.5)
	start = _player.global_position
	await _tap("dash")
	await _frames(20)
	_check("a second dash right away is refused: 5 s between dashes (moved %.2f, %.1fs left)" % [
		_flat(_player.global_position - start), _player.dash_cooldown_left()],
		_flat(_player.global_position - start) < 0.5 and _player.dash_cooldown_left() > 4.0)
	_player._dash_cooldown_timer = 0.0  # don't wait 5 s in the test

	# --- Lock-on ---
	_player.global_position = Vector3(0, 0.1, 0)
	_player.rotation.y = 0.0
	_player.reset_physics_interpolation()
	_rig.setup(_player)
	await _frames(10)
	await _tap("lock_on")
	await _frames(5)
	_check("locks onto DummyA (got %s)" % _name(_rig.lock_target), _name(_rig.lock_target) == "DummyA")

	# Strafe around the target: distance should stay roughly constant.
	var target := _rig.lock_target
	var d0 := _flat(_player.global_position - target.global_position)
	await _hold("move_right", 90)
	var d1 := _flat(_player.global_position - target.global_position)
	_check("strafing orbits the target (%.2f -> %.2f m)" % [d0, d1], absf(d1 - d0) < 1.5)
	var to_target := target.global_position - _player.global_position
	var facing := -_player.global_basis.z
	_check("faces the target while locked", Vector2(facing.x, facing.z).normalized().dot(Vector2(to_target.x, to_target.z).normalized()) > 0.9)

	await _tap("lock_on")
	await _frames(5)
	_check("second press releases lock", _rig.lock_target == null)

	# --- Recenter to a fixed angle, even while turning ---
	# Camera faces the south wall, so nothing lockable is in view.
	_player.global_position = Vector3(20, 0.1, 25)
	_player.rotation.y = PI * 0.5
	_player.reset_physics_interpolation()
	_rig.setup(_player)
	_rig._yaw = PI
	await _frames(5)
	await _tap("lock_on")
	var expected := _player.rotation.y
	await _hold("move_back", 6)  # turn the Seeker during the recenter
	await _frames(40)
	_check("recenter lands on the press-time angle (off by %.3f rad)" % absf(angle_difference(_rig._yaw, expected)),
		absf(angle_difference(_rig._yaw, expected)) < 0.15)

	# --- Camera height eases back after manual look ---
	var default_pitch := deg_to_rad(_rig.default_pitch_deg)
	await _hold("look_up", 30)
	var raised := absf(angle_difference(_rig._pitch, default_pitch))
	await _frames(15)
	var after_short := absf(angle_difference(_rig._pitch, default_pitch))
	_check("pitch holds briefly after looking up (%.2f -> %.2f rad)" % [raised, after_short],
		raised > 0.3 and after_short > raised * 0.8)
	await _frames(150)
	var after_long := absf(angle_difference(_rig._pitch, default_pitch))
	_check("pitch eases back to default (off by %.3f rad)" % after_long, after_long < 0.05)

	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + label)
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _hold(action: StringName, n: int) -> void:
	Input.action_press(action)
	await _frames(n)
	Input.action_release(action)


func _tap(action: StringName) -> void:
	await _hold(action, 2)


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _flat_speed() -> float:
	return Vector2(_player.velocity.x, _player.velocity.z).length()


func _name(n: Node) -> String:
	return str(n.name) if is_instance_valid(n) else "none"
