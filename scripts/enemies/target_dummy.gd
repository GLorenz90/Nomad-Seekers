class_name TargetDummy
extends CharacterBody3D
## Stand-in enemy for testing combat. Has HP, an optional elemental weakness and
## resistance, and moves with a NavigationAgent3D on the level's navmesh.
## Respawns a few seconds after it dies. Real enemies replace it in Part 4.

enum Behavior { STAND, PATROL, CHASE }

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
@export var lock_height := 1.1

var _start := Vector3.ZERO
var _heading_out := true
var _stagger := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _material: StandardMaterial3D
var _flash_tween: Tween

@onready var _label: Label3D = $Label3D
@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var health: Health = $Health
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

	var flat := Vector3.ZERO
	var goal: Variant = _current_goal()
	if goal != null and _stagger <= 0.0 and _navmesh_ready():
		_agent.target_position = goal
		if not _agent.is_navigation_finished():
			var next := _agent.get_next_path_position()
			var to := next - global_position
			to.y = 0.0
			if to.length_squared() > 0.0001:
				flat = to.normalized() * move_speed
				rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-8.0 * delta))
	velocity.x = flat.x
	velocity.z = flat.z
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
