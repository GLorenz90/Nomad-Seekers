class_name TrapDevice
extends StaticBody3D
## The physical part of a level trap (Grayson, 2026-11-09): a small device on
## the floor. While its trap is visible (scanned, or seen by a Goluman) it is
## on the enemy layer and in the "lockable" group, so lock-on, weapons and
## spells treat it like an enemy, and any hit destroys the trap. While hidden
## it is off every layer and out of the group, so nothing can touch it.

const ENEMY_LAYER := 4

var trap: HazardTrap
var health: Health
var _shown := false
var _mesh: MeshInstance3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.35
	cyl.height = 0.5
	shape.shape = cyl
	shape.position.y = 0.25
	add_child(shape)
	_mesh = MeshInstance3D.new()
	var body := CylinderMesh.new()
	body.top_radius = 0.22
	body.bottom_radius = 0.35
	body.height = 0.45
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.35, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.25, 0.2)
	mat.emission_energy_multiplier = 0.6
	body.material = mat
	_mesh.mesh = body
	_mesh.position.y = 0.23
	add_child(_mesh)
	visible = false
	# A Health node so attacks and spells see a live target.
	health = Health.new()
	health.name = "Health"
	health.max_hp = 1.0
	add_child(health)
	health.hp = 1.0


func is_shown() -> bool:
	return _shown


func set_shown(shown: bool) -> void:
	if shown == _shown:
		return
	_shown = shown
	visible = shown
	collision_layer = ENEMY_LAYER if shown else 0
	if shown:
		add_to_group("lockable")
	else:
		remove_from_group("lockable")


func get_lock_point() -> Vector3:
	return global_position + Vector3.UP * 0.3


## Any hit on a shown device destroys the trap; a hidden one ignores hits.
func receive_hit(_info: DamageInfo, _attacker: Node3D, _projectile: Node = null) -> float:
	if not _shown or trap == null:
		return 0.0
	remove_from_group("lockable")
	collision_layer = 0
	trap.destroy()
	return 1.0
