class_name Projectile
extends Node3D
## Bullet / spell bolt. Moves in a straight line, sweeps for hits each physics
## step (so fast shots don't tunnel through enemies) and stops on world geometry.
## Hits bodies on target_mask: enemies for the Seeker's shots, the player for
## enemy shots. Hits go through HitResolver, so the Seeker can block, parry or
## (with a Ward or Barrier) reflect them back at the shooter.
##
## Patterns (Part 5): gravity (lobbed grenades), explosions (area damage on
## impact), homing chains (Boomerang: flies to each enemy in `chain` in turn)
## and out-and-back throws (Gigarang: returns to the shooter, hitting again).

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
var gravity := 0.0
var explosion_radius := 0.0
## Homing: enemies to visit in order. Each one hit is removed; when the list
## runs out the projectile is spent.
var chain: Array[Node3D] = []
var returns := false

var _travelled := 0.0
var _reflected := false
var _already_hit: Array[Node] = []
var _exclude: Array[RID] = []
var _returning := false
var _speed := 0.0


static func spawn(parent: Node, from: Vector3, direction: Vector3, attack: AttackData,
		info: DamageInfo, color: Color, from_body: CollisionObject3D,
		combat: CombatController, mask: int = ENEMY_MASK) -> Projectile:
	var p := Projectile.new()
	p.velocity = direction.normalized() * attack.projectile_speed
	p.radius = attack.projectile_radius
	p.max_range = attack.projectile_range
	p.pierce = attack.projectile_pierce
	p.gravity = attack.projectile_gravity
	p.explosion_radius = attack.explosion_radius
	p.returns = attack.returns
	p._speed = attack.projectile_speed
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
	_steer(delta)
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
		if explosion_radius > 0.0:
			_explode(to)
			return
		# Each body gets its own copy: defense scaling must not stack on piercing shots.
		var info := damage.duplicate_info()
		var amount := HitResolver.apply(body, info, shooter if is_instance_valid(shooter) else null, self)
		if _reflected:
			_reflected = false
			return  # turned around: keep flying, now at the shooter
		if is_instance_valid(reporter):
			reporter.report_hit(body, info, amount)
		if not chain.is_empty():
			chain.erase(body)
			_prune_chain()
			if chain.is_empty():
				queue_free()
				return
			continue
		if not pierce:
			queue_free()
			return

	global_position = to
	_travelled += from.distance_to(to)
	if returns and not _returning and (_travelled >= max_range * 0.5 or not wall.is_empty()):
		_returning = true
		_already_hit.clear()  # hits again on the way back
		return
	if _returning and is_instance_valid(shooter) and global_position.distance_to(_shooter_point()) < 1.0:
		queue_free()
		return
	if not wall.is_empty() or _travelled >= max_range * (2.0 if returns else 1.0):
		if explosion_radius > 0.0:
			_explode(to)
			return
		queue_free()


func _shooter_point() -> Vector3:
	return shooter.global_position + Vector3.UP * 1.1


## Gravity, homing to the next chain target, or heading back to the shooter.
func _steer(delta: float) -> void:
	if gravity > 0.0:
		velocity.y -= gravity * delta
	if _returning and is_instance_valid(shooter):
		velocity = (_shooter_point() - global_position).normalized() * _speed
		return
	if not chain.is_empty():
		_prune_chain()
		if chain.is_empty():
			queue_free()
			return
		var aim := CameraRig.get_lock_point(chain[0]) - global_position
		velocity = aim.normalized() * _speed


func _prune_chain() -> void:
	chain = chain.filter(func(n: Node3D) -> bool:
		if not is_instance_valid(n) or not n.is_inside_tree():
			return false
		var h := Health.find(n)
		return h != null and not h.is_dead())


## Area damage: every target inside explosion_radius takes the hit once.
func _explode(at: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = explosion_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, at)
	params.collision_mask = target_mask
	params.exclude = _exclude
	var hit: Array[Node] = []
	for result in space.intersect_shape(params, 24):
		var body: Node = result.collider
		if body in hit:
			continue
		hit.append(body)
		var info := damage.duplicate_info()
		info.hit_position = (body as Node3D).global_position + Vector3.UP * 1.0
		var amount := HitResolver.apply(body, info, shooter if is_instance_valid(shooter) else null, null)
		if is_instance_valid(reporter):
			reporter.report_hit(body, info, amount)
	_blast_visual(at)
	queue_free()


func _blast_visual(at: Vector3) -> void:
	var flash := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = explosion_radius
	mesh.height = explosion_radius * 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var color := Element.color_of(damage.damage_type) if damage.damage_type != Element.Type.GENERIC \
		else Color(1.0, 0.6, 0.2)
	color.a = 0.45
	mat.albedo_color = color
	mesh.material = mat
	flash.mesh = mesh
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(flash)
	flash.global_position = at
	flash.scale = Vector3.ONE * 0.3
	var tween := flash.create_tween()
	tween.tween_property(flash, "scale", Vector3.ONE, 0.15)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tween.tween_callback(flash.queue_free)


## Ward / Barrier parry: send this shot back at whoever fired it, as the
## Seeker's shot, a little faster.
func reflect(new_shooter: CollisionObject3D, combat: CombatController) -> void:
	var old_shooter := shooter
	var dir := -velocity.normalized()
	if is_instance_valid(old_shooter):
		dir = (CameraRig.get_lock_point(old_shooter) - global_position).normalized()
	velocity = dir * velocity.length() * 1.25
	target_mask = ENEMY_MASK
	shooter = new_shooter
	_exclude = [new_shooter.get_rid()]
	_already_hit.clear()
	_travelled = 0.0
	reporter = combat
	damage.source = new_shooter
	_reflected = true
