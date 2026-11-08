class_name CombatController
extends Node3D
## The Seeker's hands: input, timing combos, LP and attack execution (North Star §4).
##
## Input: each face button is one hand (x_is_left picks which). Tap = Normal
## attack (fires on release), hold past hold_threshold = Hard attack. On a casting
## item, holding Shift (RT) casts the item's second spell.
##
## Combo rules:
## - A chain has 3 steps. Any attack from either hand can fill the next step.
## - The next step only chains if pressed inside the current attack's window
##   (window_open..window_close). Pressing too early breaks the combo; too late
##   and a new chain starts.
## - Each weapon's animation step counts its own consecutive uses: Sword, Pistol,
##   Sword plays the sword's step 1 both times. Committing to one weapon gives its
##   step 2 and 3 attacks and their bonus damage.
## - No-combo weapons and casting items are standalone and end any chain.
##
## Must be a direct child of the Player.

signal attack_started(hand: int, weapon: WeaponData, attack: AttackData, chain_step: int, hard: bool)
signal combo_feedback(text: String)
signal loadout_changed(index: int)
signal hit_landed(target: Node, info: DamageInfo, amount: float)

enum Hand { LEFT, RIGHT }

const ENEMY_MASK := 4
const MAX_CHAIN := 3
const WEAPON_DIR := "res://data/weapons/"
## Prototype loadouts as [left hand, right hand]. LB/RB cycles. Proper loadout
## editing arrives in Part 3.
const STARTER_LOADOUTS := [["sword", "pistol"], ["wand", "sword"], ["pistol", "pistol"]]

@export var stats: Stats
## North Star: the player chooses which face button is which hand.
@export var x_is_left := true
@export var hold_threshold := 0.22
@export var soft_aim_angle_deg := 25.0
@export var soft_aim_range := 25.0
## Melee attacks snap to face an enemy this close (PSO-style auto-turn).
@export var melee_turn_range := 4.0
@export var show_hitboxes := true

var lp := 0.0
var loadouts: Array = []
var loadout_index := 0
## Steps used in the current chain (0 = no chain).
var chain_step := 0


class ActiveAttack:
	var hand := 0
	var weapon: WeaponData
	var attack: AttackData
	var hard := false
	var elapsed := 0.0
	var fired := false
	var hit: Array[Node] = []
	var direction := Vector3.FORWARD
	var target: Node3D


var _current: ActiveAttack
var _chain_expire := 0.0
var _chain_locked := false
var _last_hand := -1
var _weapon_streak := 0
var _time := 0.0
var _lp_regen_delay := 0.0
var _held: Array[float] = [-1.0, -1.0]
var _hard_fired: Array[bool] = [false, false]

var _player: Player
var _pivots: Array[Node3D] = []
var _meshes: Array[MeshInstance3D] = []
var _tweens: Array[Tween] = [null, null]
var _hitbox_debug: MeshInstance3D


func _ready() -> void:
	_player = get_parent() as Player
	if stats == null:
		stats = Stats.new()
	lp = stats.max_lp
	for pair in STARTER_LOADOUTS:
		loadouts.append([load(WEAPON_DIR + pair[0] + ".tres"), load(WEAPON_DIR + pair[1] + ".tres")])
	_build_hand(Vector3(-0.5, 1.05, -0.1))
	_build_hand(Vector3(0.5, 1.05, -0.1))
	_build_hitbox_debug()
	_equip_visuals()


func _physics_process(delta: float) -> void:
	_time += delta
	_regen_lp(delta)
	_handle_loadout_input()
	for hand in [Hand.LEFT, Hand.RIGHT]:
		_read_hand(hand, delta)
	if _current:
		_update_attack(delta)
	elif chain_step > 0 and _time > _chain_expire:
		chain_step = 0
		_chain_locked = false
	_update_hitbox_debug()


# --- Public -----------------------------------------------------------------

func current_weapon(hand: int) -> WeaponData:
	if loadouts.is_empty():
		return null
	return loadouts[loadout_index][hand]


func is_attacking() -> bool:
	return _current != null


## Dashing can cancel an attack once its hit is out.
func can_dash_cancel() -> bool:
	return _current == null or _current.elapsed >= _current.attack.active_end


func cancel() -> void:
	_current = null
	chain_step = 0
	_chain_locked = false
	for hand in [Hand.LEFT, Hand.RIGHT]:
		_return_to_rest(hand)


## Lunge velocity for the Seeker while a melee attack winds up.
func get_lunge_velocity() -> Vector3:
	if _current == null or _current.attack.is_projectile:
		return Vector3.ZERO
	var a := _current.attack
	if _current.elapsed >= a.active_end or a.lunge_distance <= 0.0:
		return Vector3.ZERO
	return _current.direction * (a.lunge_distance / maxf(a.active_end, 0.05))


func button_for(hand: int) -> String:
	return "X" if (hand == Hand.LEFT) == x_is_left else "Y"


func report_hit(target: Node, info: DamageInfo, amount: float) -> void:
	hit_landed.emit(target, info, amount)


func get_debug_text() -> String:
	var lines := PackedStringArray()
	lines.append("Loadout %d/%d (LB/RB)" % [loadout_index + 1, loadouts.size()])
	for hand in [Hand.LEFT, Hand.RIGHT]:
		var w := current_weapon(hand)
		var label := w.display_name if w else "-"
		if w and w.casting:
			label += " [%s / Shift: %s]" % [w.get_spell_name(0), w.get_spell_name(1)]
		lines.append("%s (%s hand): %s" % [button_for(hand), "left" if hand == Hand.LEFT else "right", label])
	if _current:
		lines.append("Attack: %s%s  %.2fs  window %.2f-%.2f" % [
			_current.attack.display_name, " (Hard)" if _current.hard else "",
			_current.elapsed, _current.attack.window_open, _current.attack.window_close])
	return "\n".join(lines)


# --- Input ------------------------------------------------------------------

func _action_for(hand: int) -> StringName:
	return &"hand_x" if (hand == Hand.LEFT) == x_is_left else &"hand_y"


func _read_hand(hand: int, delta: float) -> void:
	var action := _action_for(hand)
	if Input.is_action_just_pressed(action):
		_held[hand] = 0.0
		_hard_fired[hand] = false
	elif _held[hand] >= 0.0:
		if Input.is_action_pressed(action):
			_held[hand] += delta
			if not _hard_fired[hand] and _held[hand] >= hold_threshold:
				_hard_fired[hand] = true
				_request_attack(hand, true)
		else:
			if not _hard_fired[hand]:
				_request_attack(hand, false)
			_held[hand] = -1.0


func _handle_loadout_input() -> void:
	if _current:
		return
	var step := 0
	if Input.is_action_just_pressed("loadout_next"):
		step = 1
	elif Input.is_action_just_pressed("loadout_prev"):
		step = -1
	if step != 0:
		loadout_index = posmod(loadout_index + step, loadouts.size())
		chain_step = 0
		_equip_visuals()
		loadout_changed.emit(loadout_index)


# --- Combo logic ------------------------------------------------------------

func _request_attack(hand: int, hard: bool) -> void:
	var weapon := current_weapon(hand)
	if weapon == null:
		return
	var standalone := weapon.no_combo or weapon.casting
	var slot := 1 if Input.is_action_pressed("shift") else 0

	if _current:
		var cur := _current
		if cur.weapon.no_combo or cur.weapon.casting or _chain_locked:
			return
		if cur.elapsed < cur.attack.window_open:
			_chain_locked = true
			combo_feedback.emit("Too early!")
			return
		if cur.elapsed > cur.attack.window_close or chain_step >= MAX_CHAIN:
			return
		_begin(hand, weapon, hard, slot, not standalone)
		return

	var continuing := not standalone and not _chain_locked and chain_step > 0 \
		and chain_step < MAX_CHAIN and _time <= _chain_expire
	_begin(hand, weapon, hard, slot, continuing)


func _begin(hand: int, weapon: WeaponData, hard: bool, slot: int, continuing: bool) -> void:
	var next_step := chain_step + 1 if continuing else 1
	var next_streak := 1
	if continuing and hand == _last_hand:
		next_streak = _weapon_streak + 1
	if weapon.no_combo or weapon.casting:
		next_step = 0
		next_streak = 1

	var attack := weapon.get_attack(next_streak, hard, slot)
	if attack == null:
		return
	if lp < attack.lp_cost:
		combo_feedback.emit("Not enough LP")
		return

	if not continuing:
		_chain_locked = false
	chain_step = next_step
	_weapon_streak = next_streak
	_last_hand = hand
	lp -= attack.lp_cost
	if attack.lp_cost > 0.0:
		_lp_regen_delay = 0.75

	var a := ActiveAttack.new()
	a.hand = hand
	a.weapon = weapon
	a.attack = attack
	a.hard = hard
	_aim(a)
	_current = a
	_chain_expire = 0.0
	_animate(hand, attack)
	if chain_step == MAX_CHAIN and _weapon_streak == MAX_CHAIN:
		combo_feedback.emit("Finisher!")
	attack_started.emit(hand, weapon, attack, chain_step, hard)


func _update_attack(delta: float) -> void:
	var cur := _current
	cur.elapsed += delta
	var a := cur.attack
	if a.is_projectile:
		if not cur.fired and cur.elapsed >= a.active_start:
			cur.fired = true
			_fire_projectile(cur)
	elif cur.elapsed >= a.active_start and cur.elapsed <= a.active_end:
		_melee_hits(cur)

	if cur.elapsed >= a.duration:
		var standalone := cur.weapon.no_combo or cur.weapon.casting
		if standalone or _chain_locked or chain_step >= MAX_CHAIN:
			chain_step = 0
			_chain_locked = false
			_chain_expire = 0.0
		else:
			# Grace period: the window can stay open a little after the attack ends.
			_chain_expire = _time + maxf(a.window_close - a.duration, 0.0)
		_current = null


# --- Aim, hits, damage ------------------------------------------------------

func _aim(a: ActiveAttack) -> void:
	var target := _player.get_lock_target()
	if target == null:
		if a.attack.is_projectile:
			target = _find_soft_target(soft_aim_range, soft_aim_angle_deg)
		else:
			target = _find_soft_target(melee_turn_range, 80.0)
	a.target = target

	var dir := -_player.global_basis.z
	if target:
		dir = target.global_position - _player.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = -_player.global_basis.z
		dir.y = 0.0
	a.direction = dir.normalized()
	_player.face_direction(a.direction)


func _find_soft_target(max_range: float, max_angle_deg: float) -> Node3D:
	var origin := _player.global_position
	var forward := -_player.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var best: Node3D = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group("lockable"):
		var n := node as Node3D
		if n == null or not n.is_visible_in_tree():
			continue
		var to := n.global_position - origin
		to.y = 0.0
		var dist := to.length()
		if dist > max_range or dist < 0.01:
			continue
		var angle := rad_to_deg(forward.angle_to(to / dist))
		if angle > max_angle_deg:
			continue
		var score := angle / max_angle_deg + dist / max_range
		if score < best_score:
			best_score = score
			best = n
	return best


func _make_damage(cur: ActiveAttack) -> DamageInfo:
	var info := DamageInfo.new()
	var stat := stats.attack_stat(cur.weapon.weapon_class)
	info.amount = cur.weapon.base_damage * cur.attack.damage_mult * (1.0 + stat / 100.0)
	info.damage_type = cur.attack.damage_type if cur.attack.override_damage_type else cur.weapon.damage_type
	info.is_hard = cur.hard
	if randf() < stats.crit_chance():
		info.is_crit = true
		info.amount *= 1.5
	info.source = _player
	return info


func _hitbox_transform(cur: ActiveAttack) -> Transform3D:
	var origin := _player.global_position + Vector3.UP * 1.0 + cur.direction * cur.attack.reach
	return Transform3D(Basis.looking_at(cur.direction), origin)


func _melee_hits(cur: ActiveAttack) -> void:
	var shape := BoxShape3D.new()
	shape.size = cur.attack.hitbox_size
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = _hitbox_transform(cur)
	params.collision_mask = ENEMY_MASK
	for result in get_world_3d().direct_space_state.intersect_shape(params, 16):
		var body: Node = result.collider
		if body in cur.hit:
			continue
		cur.hit.append(body)
		var health := Health.find(body)
		if health == null or health.is_dead():
			continue
		var info := _make_damage(cur)
		info.hit_position = (body as Node3D).global_position + Vector3.UP * 1.2
		report_hit(body, info, health.take_damage(info))


func _fire_projectile(cur: ActiveAttack) -> void:
	var muzzle := _pivots[cur.hand].global_position + cur.direction * 0.6
	var aim := cur.direction
	if is_instance_valid(cur.target):
		aim = (CameraRig.get_lock_point(cur.target) - muzzle).normalized()
	var info := _make_damage(cur)
	var color := Element.color_of(info.damage_type)
	if info.damage_type == Element.Type.GENERIC:
		color = Color(1.0, 0.85, 0.5)
	Projectile.spawn(_player.get_parent(), muzzle, aim, cur.attack, info, color, _player, self)


func _regen_lp(delta: float) -> void:
	if _lp_regen_delay > 0.0:
		_lp_regen_delay -= delta
		return
	lp = minf(lp + stats.lp_regen_per_second * delta, stats.max_lp)


# --- Placeholder visuals ----------------------------------------------------

func _build_hand(shoulder: Vector3) -> void:
	var pivot := Node3D.new()
	pivot.position = shoulder
	add_child(pivot)
	var mesh := MeshInstance3D.new()
	pivot.add_child(mesh)
	_pivots.append(pivot)
	_meshes.append(mesh)


func _equip_visuals() -> void:
	for hand in [Hand.LEFT, Hand.RIGHT]:
		var w := current_weapon(hand)
		var mesh_instance := _meshes[hand]
		if w == null:
			mesh_instance.mesh = null
			continue
		var box := BoxMesh.new()
		box.size = w.mesh_size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = w.mesh_color
		mat.metallic = 0.4
		mat.roughness = 0.4
		box.material = mat
		mesh_instance.mesh = box
		mesh_instance.position = Vector3(0.0, 0.0, -(w.mesh_size.z * 0.5 + 0.05))
		_return_to_rest(hand)


func _rest_pose(hand: int) -> Vector3:
	var w := current_weapon(hand)
	if w and w.weapon_class == WeaponData.WeaponClass.MELEE:
		return Vector3(-0.6, 0.0, 0.0)
	return Vector3(-0.2, 0.0, 0.0)


func _return_to_rest(hand: int) -> void:
	if _tweens[hand]:
		_tweens[hand].kill()
	_pivots[hand].rotation = _rest_pose(hand)
	_pivots[hand].position.z = -0.1


func _animate(hand: int, a: AttackData) -> void:
	var pivot := _pivots[hand]
	if _tweens[hand]:
		_tweens[hand].kill()
	pivot.position.z = -0.1
	var start := Vector3.ZERO
	var finish := Vector3.ZERO
	match a.swing:
		AttackData.Swing.SLASH_RIGHT:
			start = Vector3(-0.1, -1.4, 0.0)
			finish = Vector3(-0.3, 1.4, 0.0)
		AttackData.Swing.SLASH_LEFT:
			start = Vector3(-0.1, 1.4, 0.0)
			finish = Vector3(-0.3, -1.4, 0.0)
		AttackData.Swing.OVERHEAD:
			start = Vector3(1.6, 0.0, 0.0)
			finish = Vector3(-0.9, 0.0, 0.0)
		AttackData.Swing.THRUST:
			start = Vector3(0.0, 0.0, 0.0)
			finish = Vector3(0.0, 0.0, 0.0)
		AttackData.Swing.SHOT:
			start = Vector3(0.0, 0.0, 0.0)
			finish = Vector3(0.4, 0.0, 0.0)
		AttackData.Swing.CAST:
			start = Vector3(0.3, 0.0, 0.0)
			finish = Vector3(0.1, 0.0, 0.0)

	var windup := maxf(a.active_start, 0.03)
	var active := maxf(a.active_end - a.active_start, 0.05)
	var recover := maxf(a.duration - a.active_end, 0.05)
	var tween := create_tween()
	tween.tween_property(pivot, "rotation", start, windup)
	if a.swing == AttackData.Swing.THRUST:
		tween.tween_property(pivot, "position:z", -0.8, active)
		tween.tween_property(pivot, "position:z", -0.1, recover * 0.5)
	else:
		tween.tween_property(pivot, "rotation", finish, active)
	tween.tween_property(pivot, "rotation", _rest_pose(hand), recover)
	_tweens[hand] = tween


func _build_hitbox_debug() -> void:
	_hitbox_debug = MeshInstance3D.new()
	_hitbox_debug.top_level = true
	_hitbox_debug.visible = false
	_hitbox_debug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.3, 0.2, 0.25)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var box := BoxMesh.new()
	box.material = mat
	_hitbox_debug.mesh = box
	add_child(_hitbox_debug)


func _update_hitbox_debug() -> void:
	var live := show_hitboxes and _current != null and not _current.attack.is_projectile \
		and _current.elapsed >= _current.attack.active_start \
		and _current.elapsed <= _current.attack.active_end
	_hitbox_debug.visible = live
	if live:
		(_hitbox_debug.mesh as BoxMesh).size = _current.attack.hitbox_size
		_hitbox_debug.global_transform = _hitbox_transform(_current)
