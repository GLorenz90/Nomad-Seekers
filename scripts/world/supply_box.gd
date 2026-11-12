class_name SupplyBox
extends StaticBody3D
## A breakable box, like PSO's (Part 13a, level editor Layer 2). One hit
## breaks it and it drops something: Oro, a consumable or, rarely, a normal
## enemy-style drop. On the enemy layer so attacks hit it, but not lockable,
## and not on the world layer (the navmesh ignores it).

signal broken(box: SupplyBox)

const ENEMY_LAYER := 4
## Share of boxes that roll a real drop (weapon, armor...) instead of
## Oro or a consumable. Claude's pick.
const RARE_SHARE := 0.15

@export var box_id := ""
## "random" or a fixed drop: "oro", "hp_gel", "lp_cell", "cure_salt", "trap_scanner".
@export var contents := "random"

var health: Health
var _broken := false
var _mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("supply_boxes")
	collision_layer = ENEMY_LAYER
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	shape.shape = box
	shape.position.y = 0.5
	add_child(shape)
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.95, 0.95, 0.95)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.6, 0.3)
	bm.material = mat
	_mesh.mesh = bm
	_mesh.position.y = 0.5
	add_child(_mesh)
	health = Health.new()
	health.name = "Health"
	health.max_hp = 1.0e9  # targeting treats it as alive until it breaks
	add_child(health)
	health.hp = health.max_hp


func receive_hit(_info: DamageInfo, _attacker: Node3D, _projectile: Node = null) -> float:
	if not _broken:
		smash()
	return 0.0


func is_broken() -> bool:
	return _broken


func smash() -> void:
	_broken = true
	collision_layer = 0
	health.hp = 0.0
	var drop := roll(contents, RandomNumberGenerator.new())
	var level := Scope.level(self)
	if level and not drop.is_empty():
		level.call("spawn_drop", drop, global_position + Vector3.UP * 0.3)
	broken.emit(self)
	var tween := create_tween()
	tween.tween_property(_mesh, "scale", Vector3(1.2, 0.05, 1.2), 0.2)
	tween.tween_callback(queue_free)


static func roll(what: String, rng: RandomNumberGenerator) -> Dictionary:
	rng.randomize()
	if what == "oro":
		return {"oro": rng.randi_range(15, 60)}
	if Inventory.CONSUMABLES.has(StringName(what)):
		return {"consumable": StringName(what)}
	if rng.randf() < RARE_SHARE:
		var drop := {}
		var generic := EnemyData.new()
		for i in 4:  # a box always gives something
			drop = Loot.roll_drop(generic, 0, rng)
			if not drop.is_empty():
				return drop
	if rng.randf() < 0.5:
		return {"oro": rng.randi_range(15, 60)}
	var ids := Inventory.CONSUMABLES.keys()
	return {"consumable": ids[rng.randi() % ids.size()]}
