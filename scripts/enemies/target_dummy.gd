class_name TargetDummy
extends CharacterBody3D
## Stand-in enemy for testing combat. Has HP, an optional elemental weakness and
## resistance, and moves with a NavigationAgent3D on the level's navmesh.
## Respawns a few seconds after it dies. Real enemies replace it in Part 4.
##
## Optional attacks, for testing blocks and parries: SHOOT fires a slow bolt at
## the Seeker; SWING telegraphs (glows orange) and then hits in front of it.
## A parry staggers it (glows blue); a shove knocks it back.

enum Behavior { STAND, PATROL, CHASE }
enum AttackMode { NONE, SHOOT, SWING }

@export var behavior: Behavior = Behavior.STAND
## PATROL: walks between its start and start + patrol_offset.
@export var patrol_offset := Vector3.ZERO
@export var move_speed := 2.5
## CHASE: follows the Seeker inside this range, stopping at stop_distance.
@export var aggro_range := 12.0
@export var stop_distance := 2.2
@export var max_hp := 200.0
## Takes double damage of this type (GENERIC = none).
@export var weak_to: Element.Type = Element.Type.GENERIC
## Takes half damage of this type (GENERIC = none).
@export var resists: Element.Type = Element.Type.GENERIC
@export var respawn_time := 3.0

@export_group("Attacks")
@export var attack_mode: AttackMode = AttackMode.NONE
@export var attack_damage := 20.0
@export var attack_element: Element.Type = Element.Type.GENERIC
@export var attack_interval := 2.5
@export var attack_range := 14.0
## SWING: telegraph time before the hit lands.
@export var windup := 0.6
@export var swing_reach := 2.6
@export var parry_stagger := 1.5
@export var lock_height := 1.1

var _start := Vector3.ZERO
var _heading_out := true
var _stagger := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _material: StandardMaterial3D
var _flash_tween: Tween
var _attack_cooldown := 1.0
var _windup_left := -1.0
var _hit_area: HitAreaView
var _knockback := Vector3.ZERO

@onready var _label: Label3D = $Label3D
@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var health: Health = $Health
@onready var status: StatusEffects = $StatusEffects
@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	add_to_group("lockable")
	_start = global_position
	health.max_hp = max_hp
	health.hp = max_hp
	if weak_to != Element.Type.GENERIC:
		health.multipliers[weak_to] = 2.0
	if resists != Element.Type.GENERIC:
		health.multipliers[resists] = 0.5
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	# Per-instance material so hit flashes don't affect every dummy.
	_material = (_mesh.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
	_mesh.material_override = _material
	_update_label()


func get_lock_point() -> Vector3:
	return global_position + Vector3.UP * lock_height


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_stagger = maxf(_stagger - delta, 0.0)
	_update_attack(delta)

	var flat := Vector3.ZERO
	var goal: Variant = _current_goal()
	if goal != null and _stagger <= 0.0 and _navmesh_ready():
		_agent.target_position = goal
		if not _agent.is_navigation_finished():
			var next := _agent.get_next_path_position()
			var to := next - global_position
			to.y = 0.0
			if to.length_squared() > 0.0001:
				flat = to.normalized() * move_speed * status.move_scale()
				rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-8.0 * delta))
	_knockback = _knockback.move_toward(Vector3.ZERO, 30.0 * delta)
	velocity.x = flat.x + _knockback.x
	velocity.z = flat.z + _knockback.z
	move_and_slide()


func _current_goal() -> Variant:
	match behavior:
		Behavior.PATROL:
			if patrol_offset == Vector3.ZERO:
				return null
			var goal := _start + (patrol_offset if _heading_out else Vector3.ZERO)
			var flat := goal - global_position
			flat.y = 0.0
			if flat.length() < 0.6:
				_heading_out = not _heading_out
			_agent.target_desired_distance = 0.5
			return goal
		Behavior.CHASE:
			var seeker := get_tree().get_first_node_in_group("player") as Node3D
			if seeker == null or seeker.global_position.distance_to(global_position) > aggro_range:
				return null
			_agent.target_desired_distance = stop_distance
			return seeker.global_position
	return null


func on_parried() -> void:
	_windup_left = -1.0
	if _hit_area:
		_hit_area.stop()
	_stagger = parry_stagger
	_attack_cooldown = maxf(_attack_cooldown, parry_stagger + 0.5)
	_glow(Color(0.3, 0.6, 1.0), parry_stagger)


func apply_knockback(push: Vector3) -> void:
	push.y = 0.0
	_knockback = push
	_stagger = maxf(_stagger, 0.6)


func _update_attack(delta: float) -> void:
	if attack_mode == AttackMode.NONE:
		return
	var seeker := get_tree().get_first_node_in_group("player") as Player
	if seeker == null:
		return
	if _windup_left >= 0.0:
		_windup_left -= delta
		_swing_area().telegraph(1.0 - _windup_left / maxf(windup, 0.01))
		if _windup_left < 0.0:
			_swing_area().strike()
			_swing_hit(seeker)
		return
	_attack_cooldown -= delta
	if _attack_cooldown > 0.0 or _stagger > 0.0 or not status.can_act():
		return
	var to := seeker.global_position - global_position
	to.y = 0.0
	var reach := swing_reach if attack_mode == AttackMode.SWING else attack_range
	if to.length() > reach:
		return
	rotation.y = atan2(-to.x, -to.z)
	_attack_cooldown = attack_interval
	if attack_mode == AttackMode.SHOOT:
		_shoot(seeker)
	else:
		_windup_left = windup
		_glow(Color(1.0, 0.55, 0.1), windup)


func _make_hit(kind: DamageInfo.Kind = DamageInfo.Kind.MELEE) -> DamageInfo:
	var info := DamageInfo.new()
	info.kind = kind
	info.amount = attack_damage
	info.damage_type = attack_element
	info.source = self
	info.accuracy = 50.0  # same ATA as a typical enemy (Accuracy)
	return info


func _shoot(seeker: Player) -> void:
	var bolt := AttackData.new()
	bolt.projectile_speed = 10.0
	bolt.projectile_radius = 0.2
	bolt.projectile_range = attack_range + 4.0
	var from := get_lock_point() + Vector3.UP * 0.2
	var aim := (seeker.global_position + Vector3.UP * 1.1 - from).normalized()
	Projectile.spawn(get_parent(), from, aim, bolt, _make_hit(DamageInfo.Kind.RANGED), Color(1.0, 0.3, 0.6), self, null,
		Projectile.PLAYER_MASK)


## Debug view of the swing's hit area (built on first use).
func _swing_area() -> HitAreaView:
	if _hit_area == null:
		_hit_area = HitAreaView.create(swing_reach, 120.0)
		add_child(_hit_area)
	return _hit_area


func _swing_hit(seeker: Player) -> void:
	var to := seeker.global_position - global_position
	to.y = 0.0
	var facing := -global_basis.z
	if to.length() <= swing_reach and facing.angle_to(to.normalized()) <= deg_to_rad(60.0):
		HitResolver.apply(seeker, _make_hit(), self)


func _glow(color: Color, seconds: float) -> void:
	if _flash_tween:
		_flash_tween.kill()
	_material.emission_enabled = true
	_material.emission = color
	_material.emission_energy_multiplier = 1.2
	_flash_tween = create_tween()
	_flash_tween.tween_property(_material, "emission_energy_multiplier", 0.0, seconds)


func _navmesh_ready() -> bool:
	return NavigationServer3D.map_get_iteration_id(_agent.get_navigation_map()) > 0


func _on_damaged(info: DamageInfo, amount: float) -> void:
	DamageNumber.spawn(get_parent(), info.hit_position if info.hit_position != Vector3.ZERO else get_lock_point(),
		amount, info.damage_type, info.is_crit)
	_stagger = 0.35 if info.is_hard else 0.2
	_update_label()
	if _flash_tween:
		_flash_tween.kill()
	_material.emission_enabled = true
	_material.emission = Color.WHITE
	_material.emission_energy_multiplier = 1.5
	_flash_tween = create_tween()
	_flash_tween.tween_property(_material, "emission_energy_multiplier", 0.0, 0.15)


func _on_died() -> void:
	remove_from_group("lockable")
	visible = false
	collision_layer = 0
	set_physics_process(false)
	await get_tree().create_timer(respawn_time).timeout
	if not is_inside_tree():
		return
	global_position = _start
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	health.restore_full()
	status.clear_all()
	collision_layer = 4
	visible = true
	set_physics_process(true)
	add_to_group("lockable")
	_update_label()


func _update_label() -> void:
	var text := "%s\n%d / %d" % [name, ceili(health.hp), roundi(health.max_hp)]
	if weak_to != Element.Type.GENERIC:
		text += "\nWeak: " + Element.name_of(weak_to)
	if resists != Element.Type.GENERIC:
		text += "\nResists: " + Element.name_of(resists)
	_label.text = text
