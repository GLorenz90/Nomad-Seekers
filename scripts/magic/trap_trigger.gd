class_name TrapTrigger
extends StaticBody3D
## The hittable part of a Goluman's trap (Grayson, 2026-11-10): on the enemy
## layer and lockable, so any Seeker can shoot, swing at or blast it to set the
## trap off early, armed or not. A Ranger can pop a partner's bomb as enemies
## close in; the Goluman can spring it before it arms. Enemies never hit it.
## Lock-on and auto-aim prefer enemies over it.

const ENEMY_LAYER := 4

var trap: Trap
var health: Health


func _ready() -> void:
	collision_layer = ENEMY_LAYER
	collision_mask = 0
	add_to_group("lockable")
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.4
	cyl.height = 0.5
	shape.shape = cyl
	shape.position.y = 0.25
	add_child(shape)
	health = Health.new()
	health.name = "Health"
	health.max_hp = 1.0
	add_child(health)
	health.hp = 1.0


func get_lock_point() -> Vector3:
	return global_position + Vector3.UP * 0.25


## Any Seeker's hit sets the trap off.
func receive_hit(_info: DamageInfo, attacker: Node3D, _projectile: Node = null) -> float:
	if trap == null or not is_instance_valid(trap) or (attacker != null and not attacker is Player):
		return 0.0
	remove_from_group("lockable")
	collision_layer = 0
	trap.spring.call_deferred()
	return 1.0
