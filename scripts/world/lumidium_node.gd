class_name LumidiumNode
extends StaticBody3D
## A Lumidium crystal deposit (North Star §7.1). Hit it HITS_TO_BREAK times
## with any attack and it shatters into Lumidium pickups. Carried Lumidium is
## lost on death until it's deposited at a teleporter.
##
## On the enemy layer so attacks hit it, but not lockable (lock-on and soft
## aim ignore it) and not on the world layer (the navmesh ignores it).

const ENEMY_LAYER := 4
const HITS_TO_BREAK := 3

## Inventory.LUMIDIUM color. "raw" is the rare typeless kind.
@export var color: StringName = &"fire"
@export var yield_amount := 3

var health: Health
var _hits := 0
var _crystal: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group("lumidium_nodes")
	collision_layer = ENEMY_LAYER
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.4, 1.2)
	shape.shape = box
	shape.position.y = 0.7
	add_child(shape)
	_material = StandardMaterial3D.new()
	_material.albedo_color = Inventory.LUMIDIUM_COLORS.get(color, Color.WHITE)
	_material.emission_enabled = true
	_material.emission = _material.albedo_color
	_material.emission_energy_multiplier = 0.6
	_material.roughness = 0.2
	_crystal = MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(1.0, 1.5, 1.0)
	prism.material = _material
	_crystal.mesh = prism
	_crystal.position.y = 0.75
	add_child(_crystal)
	# A Health node so attacks treat it like a target; it never dies from damage.
	health = Health.new()
	health.name = "Health"
	health.max_hp = 1.0e9
	add_child(health)
	health.hp = health.max_hp


func receive_hit(_info: DamageInfo, _attacker: Node3D, _projectile: Node = null) -> float:
	if _hits >= HITS_TO_BREAK:
		return 0.0
	_hits += 1
	DamageNumber.spawn_text(get_parent(), global_position + Vector3.UP * 1.8,
		"%d / %d" % [_hits, HITS_TO_BREAK])
	_crystal.scale = Vector3.ONE * (1.0 - 0.15 * _hits)
	if _hits >= HITS_TO_BREAK:
		_shatter()
	return 0.0


func is_broken() -> bool:
	return _hits >= HITS_TO_BREAK


func _shatter() -> void:
	collision_layer = 0
	health.hp = 0.0  # targeting ignores it now
	for i in yield_amount:
		var p := ItemPickup.create({"lumidium": color})
		get_parent().add_child(p)
		var angle := TAU * float(i) / float(yield_amount)
		p.global_position = global_position + Vector3(cos(angle), 0.0, sin(angle)) * 1.0
	var tween := create_tween()
	tween.tween_property(_crystal, "scale", Vector3.ZERO, 0.25)
	tween.tween_callback(queue_free)
