class_name HitResolver
extends RefCounted
## The one place a hit gets applied to anything. Bodies with receive_hit()
## (the Seeker, enemies) handle defense, blocking, misses and status themselves;
## anything else with a Health node (test dummies) just takes the damage and
## any status buildup.
##
## Returns the damage actually dealt (0 for a miss, block-out or parry).


static func apply(body: Node, info: DamageInfo, attacker: Node3D, projectile: Node = null) -> float:
	if body == null:
		return 0.0
	if body.has_method("receive_hit"):
		return body.receive_hit(info, attacker, projectile)
	var health := Health.find(body)
	if health == null or health.is_dead():
		return 0.0
	var amount := health.take_damage(info)
	var status := StatusEffects.find(body)
	if status:
		status.add_buildup(info, attacker)
	return amount
