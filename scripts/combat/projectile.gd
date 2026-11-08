class_name Projectile
extends Node3D
## Bullet / spell bolt. Moves in a straight line, sweeps for hits each physics
## step (so fast shots don't tunnel through enemies) and stops on world geometry.
## Hits bodies on target_mask: enemies for the Seeker's shots, the player for
## enemy shots. Bodies with receive_hit() (the Player) get to block or parry.

const WORLD_MASK := 1
const ENEMY_MASK := 4
const PLAYER_MASK := 2

var velocity := Vector3.ZERO
var radius := 0.12
var max_range := 30.0
var pierce := false
var damage: DamageInfo
var reporter: CombatController
var target_mask := ENEMY_MASK
var shooter: Node3D

var _travelled := 0.0
var _already_hit: Array[Node] = []
var _exclude: Array[RID] = []


static func spawn(parent: Node, from: Vector3, direction: Vector3, attack: AttackData,
		info: DamageInfo, color: Color, from_body: CollisionObject3D,
		combat: CombatController, mask: int = ENEMY_MASK) -> Projectile:
	var p := Projectile.new()
	p.velocity = direction.normalized() * attack.projectile_speed
	p.radius = attack.projectile_radius
	p.max_range = attack.projectile_range
	p.pierce = attack.projectile_pierce
	p.damage = info
	p.reporter = combat
	p.target_mask = mask
	p.shooter = from_body
	if from_body:
		p._exclude = [from_body.get_rid()]

	var mesh := SphereMesh.new()
	mesh.radius = p.radius
	mesh.height = p.radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mesh.material = mat
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(visual)

	parent.add_child(p)
	p.global_position = from
	return p


func _physics_process(delta: float) -> void:
	var from := global_position
	var step := velocity * delta
	var to := from + step
	var space := get_world_3d().direct_space_state

	# World geometry stops the projectile.
	var ray := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK, _exclude)
	var wall := space.intersect_ray(ray)
	if not wall.is_empty():
		to = wall.position

	# Enemies: a sphere covering this whole step.
	var sweep := SphereShape3D.new()
	sweep.radius = radius + from.distance_to(to) * 0.5
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sweep
	params.transform = Transform3D(Basis.IDENTITY, (from + to) * 0.5)
	params.collision_mask = target_mask
	params.exclude = _exclude
	for result in space.intersect_shape(params, 8):
		var body: Node = result.collider
		if body in _already_hit:
			continue
		_already_hit.append(body)
		damage.hit_position = to
		var amount := 0.0
		if body.has_method("receive_hit"):
			amount = body.receive_hit(damage, shooter if is_instance_valid(shooter) else null)
		else:
			var health := Health.find(body)
			if health == null or health.is_dead():
				continue
			amount = health.take_damage(damage)
		if is_instance_valid(reporter):
			reporter.report_hit(body, damage, amount)
		if not pierce:
			queue_free()
			return

	global_position = to
	_travelled += from.distance_to(to)
	if not wall.is_empty() or _travelled >= max_range:
		queue_free()
