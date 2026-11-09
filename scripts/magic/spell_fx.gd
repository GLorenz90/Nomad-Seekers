class_name SpellFx
extends RefCounted
## Blockout visuals for spells and traps: rings, beams, cones, bursts and
## lines that fade out on their own. Placeholder art, readable at a glance.


static func _material(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color, alpha)
	return mat


static func _spawn(parent: Node, mesh: Mesh, at: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = at
	return mi


static func _fade(mi: MeshInstance3D, mat: StandardMaterial3D, seconds: float) -> Tween:
	var tween := mi.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, seconds)
	tween.tween_callback(mi.queue_free)
	return tween


## A flat ring on the ground growing from 0 to radius.
static func ring(parent: Node, at: Vector3, radius: float, color: Color, seconds := 0.45) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(radius - 0.35, 0.05)
	torus.outer_radius = radius
	var mat := _material(color, 0.75)
	var mi := _spawn(parent, torus, at + Vector3.UP * 0.15, mat)
	mi.scale = Vector3(0.05, 1.0, 0.05)
	var tween := mi.create_tween()
	tween.tween_property(mi, "scale", Vector3.ONE, seconds * 0.7)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, seconds)
	tween.tween_callback(mi.queue_free)


## A translucent dome / sphere burst.
static func burst(parent: Node, at: Vector3, radius: float, color: Color, seconds := 0.35) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	var mat := _material(color, 0.45)
	var mi := _spawn(parent, sphere, at, mat)
	mi.scale = Vector3.ONE * 0.3
	var tween := mi.create_tween()
	tween.tween_property(mi, "scale", Vector3.ONE, seconds * 0.5)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, seconds)
	tween.tween_callback(mi.queue_free)


## A vertical beam from the sky onto a point (Zonde, Grants, sky beams).
static func beam(parent: Node, at: Vector3, color: Color, width := 0.35, seconds := 0.3) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = width
	cyl.bottom_radius = width
	cyl.height = 12.0
	var mat := _material(color, 0.85)
	var mi := _spawn(parent, cyl, at + Vector3.UP * 6.0, mat)
	_fade(mi, mat, seconds)


## A spike out of the ground (thorns).
static func spike(parent: Node, at: Vector3, color: Color, seconds := 0.4) -> void:
	var prism := PrismMesh.new()
	prism.size = Vector3(0.5, 1.4, 0.5)
	var mat := _material(color, 0.9)
	var mi := _spawn(parent, prism, at + Vector3.UP * 0.7, mat)
	mi.scale = Vector3(1.0, 0.1, 1.0)
	var tween := mi.create_tween()
	tween.tween_property(mi, "scale", Vector3.ONE, 0.08)
	tween.tween_property(mat, "albedo_color:a", 0.0, seconds)
	tween.tween_callback(mi.queue_free)


## A straight line between two points (chain lightning).
static func line(parent: Node, from: Vector3, to: Vector3, color: Color, seconds := 0.25) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.12, length)
	var mat := _material(color, 0.9)
	var mi := _spawn(parent, box, (from + to) * 0.5, mat)
	mi.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	_fade(mi, mat, seconds)


## A flat fan on the ground in front (cones, channels).
static func cone(parent: Node, at: Vector3, direction: Vector3, reach: float, cone_deg: float,
		color: Color, seconds := 0.2) -> void:
	var mat := _material(color, 0.35)
	var mi := _spawn(parent, HitAreaView._sector(reach, cone_deg), at + Vector3.UP * 0.1, mat)
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() > 0.0001:
		mi.look_at(mi.global_position + flat.normalized(), Vector3.UP)
	_fade(mi, mat, seconds)
