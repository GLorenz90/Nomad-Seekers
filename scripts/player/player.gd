class_name Player
extends CharacterBody3D
## The Seeker controller: ground movement, jump and dash/dodge.
##
## Movement is camera-relative. While the camera is locked on, the Seeker always
## faces the target, and stick input becomes forward/back toward the target and
## strafing around it (Dark Souls-style orbit).
##
## Feel goals, borrowed from Spiral Knights: snappy acceleration, no slippery
## stops, a forgiving jump (coyote time + input buffer), and a dash you can
## chain into a jump.
##
## While an attack plays (see CombatController) the Seeker is either rooted
## (apart from the attack's lunge) or keeps moving at the attack's reduced
## move_speed_scale, without jumping. Dashing cancels an attack once its hit is out.

signal jumped
signal landed
signal dash_started(direction: Vector3)
signal dash_ended

enum State { GROUND, AIR, DASH }

@export_group("Ground")
@export var move_speed := 7.0
@export var acceleration := 55.0
@export var deceleration := 65.0
@export var turn_speed := 16.0
## Speed multiplier while locked on (strafing is a little slower).
@export var lock_on_speed_scale := 0.85

@export_group("Jump")
@export var jump_height := 1.6
@export var time_to_peak := 0.34
@export var time_to_land := 0.28
## Extra gravity while rising after jump is released, for short hops.
@export var jump_cut_gravity_scale := 2.5
@export_range(0.0, 1.0) var air_control := 0.65
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12
@export var max_fall_speed := 30.0

@export_group("Dash")
@export var dash_distance := 4.5
@export var dash_duration := 0.18
@export var dash_cooldown := 0.3
## Invulnerability window at the start of a dash (used by combat in Part 2).
@export var dash_invuln_time := 0.15
@export var air_dash_count := 1
## How much dash speed is kept when the dash ends (or turns into a jump).
@export_range(0.0, 1.0) var dash_exit_speed_scale := 0.55

var camera_rig: CameraRig
var state: State = State.AIR

var _jump_velocity := 0.0
var _gravity_up := 0.0
var _gravity_down := 0.0

var _coyote_timer := 0.0
var _jump_buffer := 0.0
var _dash_timer := 0.0
var _dash_cooldown_timer := 0.0
var _invuln_timer := 0.0
var _dash_direction := Vector3.FORWARD
var _air_dashes_left := 0
var _squash_tween: Tween

@onready var _visual: Node3D = $Visual
@onready var combat: CombatController = $Combat
@onready var health: Health = $Health


func _ready() -> void:
	add_to_group("player")
	health.max_hp = combat.stats.max_hp
	health.hp = health.max_hp


func _physics_process(delta: float) -> void:
	_recalculate_jump()
	_tick_timers(delta)

	if Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time

	var move_dir := _get_move_direction()

	if Input.is_action_just_pressed("dash") and _can_dash():
		combat.cancel()
		_start_dash(move_dir)

	if state == State.DASH:
		_process_dash(delta)
	elif combat.is_attacking() or combat.is_blocking():
		_process_attacking(delta, move_dir)
	else:
		_process_movement(delta, move_dir)

	move_and_slide()
	_update_ground_state()
	_update_facing(delta, move_dir)


# --- Public -----------------------------------------------------------------

func get_lock_target() -> Node3D:
	if camera_rig and is_instance_valid(camera_rig.lock_target):
		return camera_rig.lock_target
	return null


func is_invulnerable() -> bool:
	return _invuln_timer > 0.0


## Every incoming enemy hit goes through here: dash i-frames, then blocking and
## parrying (CombatController.resolve_incoming), then Health.
func receive_hit(info: DamageInfo, attacker: Node3D) -> float:
	if is_invulnerable():
		combat.combo_feedback.emit("Dodged")
		return 0.0
	var scale := combat.resolve_incoming(attacker)
	if scale <= 0.0:
		return 0.0
	info.amount *= scale
	var amount := health.take_damage(info)
	DamageNumber.spawn(get_parent(), global_position + Vector3.UP * 1.9, amount, info.damage_type, false)
	return amount


## Camera-relative stick direction (zero when the stick is centered).
func get_move_input_direction() -> Vector3:
	return _get_move_direction()


## Snap to face a direction (used when an attack starts).
func face_direction(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		rotation.y = atan2(-direction.x, -direction.z)


func get_debug_text() -> String:
	var horizontal := Vector2(velocity.x, velocity.z).length()
	return "State: %s\nSpeed: %.1f m/s   Vertical: %.1f\nAir dashes: %d   Dash cooldown: %.2f\nInvulnerable: %s" % [
		State.keys()[state], horizontal, velocity.y,
		_air_dashes_left, _dash_cooldown_timer, is_invulnerable()]


# --- Movement ---------------------------------------------------------------

func _process_movement(delta: float, move_dir: Vector3, speed_scale: float = 1.0,
		can_jump: bool = true) -> void:
	var on_floor := is_on_floor()

	if can_jump and _jump_buffer > 0.0 and (on_floor or _coyote_timer > 0.0):
		_do_jump()
		on_floor = false

	if not on_floor:
		var gravity := _gravity_up if velocity.y > 0.0 else _gravity_down
		if velocity.y > 0.0 and not Input.is_action_pressed("jump"):
			gravity *= jump_cut_gravity_scale
		velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)

	var speed := move_speed * speed_scale * (lock_on_speed_scale if get_lock_target() else 1.0)
	var desired := move_dir * speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if move_dir.length_squared() > 0.0001 else deceleration
	if not on_floor:
		rate *= air_control
	horizontal = horizontal.move_toward(desired, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


## Mobile attacks and blocking keep walking at a reduced speed; rooted attacks
## only lunge.
func _process_attacking(delta: float, move_dir: Vector3) -> void:
	var scale := combat.get_move_scale()
	if scale > 0.0:
		_process_movement(delta, move_dir, scale, false)
		return
	if not is_on_floor():
		velocity.y = maxf(velocity.y - _gravity_down * delta, -max_fall_speed)
	var lunge := combat.get_lunge_velocity()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if lunge != Vector3.ZERO:
		horizontal = lunge
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, deceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _do_jump() -> void:
	velocity.y = _jump_velocity
	_jump_buffer = 0.0
	_coyote_timer = 0.0
	state = State.AIR
	jumped.emit()
	_squash(Vector3(0.85, 1.2, 0.85))


func _update_ground_state() -> void:
	if is_on_floor():
		_coyote_timer = coyote_time
		_air_dashes_left = air_dash_count
		if state == State.AIR:
			state = State.GROUND
			landed.emit()
			_squash(Vector3(1.15, 0.85, 1.15))
	elif state == State.GROUND:
		state = State.AIR


func _get_move_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input == Vector2.ZERO:
		return Vector3.ZERO

	var forward := _camera_forward()
	var target := get_lock_target()
	if target:
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.01:
			forward = to_target.normalized()

	var right := forward.cross(Vector3.UP)
	return right * input.x + forward * -input.y


func _camera_forward() -> Vector3:
	if camera_rig:
		return camera_rig.get_flat_forward()
	var f := -global_basis.z
	f.y = 0.0
	return f.normalized()


func _update_facing(delta: float, move_dir: Vector3) -> void:
	var target := get_lock_target()
	if combat.controls_facing() and target == null:
		return  # The attack aims us (strafe while firing).
	var face := Vector3.ZERO
	if target:
		face = target.global_position - global_position
	elif state == State.DASH:
		face = _dash_direction
	elif move_dir.length_squared() > 0.01:
		face = move_dir
	face.y = 0.0
	if face.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-face.x, -face.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))


# --- Dash -------------------------------------------------------------------

func _can_dash() -> bool:
	if state == State.DASH or _dash_cooldown_timer > 0.0:
		return false
	if not combat.can_dash_cancel():
		return false
	return is_on_floor() or _coyote_timer > 0.0 or _air_dashes_left > 0


func _start_dash(move_dir: Vector3) -> void:
	var dir := move_dir.normalized() if move_dir.length_squared() > 0.01 else _neutral_dash_direction()
	if not (is_on_floor() or _coyote_timer > 0.0):
		_air_dashes_left -= 1
	_dash_direction = dir
	_dash_timer = dash_duration
	_invuln_timer = dash_invuln_time
	state = State.DASH
	dash_started.emit(dir)
	_squash(Vector3(0.9, 0.9, 1.25))


## No stick input: backstep away from a locked target, otherwise dash forward.
func _neutral_dash_direction() -> Vector3:
	var target := get_lock_target()
	if target:
		var away := global_position - target.global_position
		away.y = 0.0
		if away.length_squared() > 0.001:
			return away.normalized()
	var forward := -global_basis.z
	forward.y = 0.0
	return forward.normalized()


func _process_dash(delta: float) -> void:
	_dash_timer -= delta
	# Dashes ignore gravity, so an air dash holds its height.
	velocity = _dash_direction * (dash_distance / dash_duration)

	# Dash-jump: jumping out of a ground dash keeps some of its momentum.
	if _jump_buffer > 0.0 and is_on_floor():
		_end_dash()
		_do_jump()
		return

	if _dash_timer <= 0.0:
		_end_dash()


func _end_dash() -> void:
	velocity.x *= dash_exit_speed_scale
	velocity.z *= dash_exit_speed_scale
	_dash_cooldown_timer = dash_cooldown
	state = State.GROUND if is_on_floor() else State.AIR
	dash_ended.emit()


# --- Helpers ----------------------------------------------------------------

func _recalculate_jump() -> void:
	# Recomputed every frame so inspector tweaks apply while the game runs.
	_jump_velocity = 2.0 * jump_height / time_to_peak
	_gravity_up = 2.0 * jump_height / (time_to_peak * time_to_peak)
	_gravity_down = 2.0 * jump_height / (time_to_land * time_to_land)


func _tick_timers(delta: float) -> void:
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	_dash_cooldown_timer = maxf(_dash_cooldown_timer - delta, 0.0)
	_invuln_timer = maxf(_invuln_timer - delta, 0.0)


func _squash(amount: Vector3) -> void:
	if _squash_tween:
		_squash_tween.kill()
	_visual.scale = amount
	_squash_tween = create_tween()
	_squash_tween.tween_property(_visual, "scale", Vector3.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
