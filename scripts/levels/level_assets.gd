class_name LevelAssets
extends RefCounted
## Models for data levels (Part 13a). Imported assets are glTF / GLB files in
## the level's assets/ folder, loaded at runtime with GLTFDocument, so they
## work for levels that were never imported by the Godot editor (your own
## and, later, the workshop's). Built-in pieces ("builtin:box"...) let a
## level be blocked out without importing anything.
##
## Collision ("collision" on a piece): "none", "box" (the model's bounds) or
## "mesh" (its exact triangles; static only). Collision goes on the world
## layer, so the navmesh is baked from it.

const MODEL_EXTENSIONS := ["glb", "gltf"]

## Loaded models per file (a level often places the same model many times).
static var _cache := {}


## The model for an asset id: a fresh copy each call. Null if it can't load.
static func model(level: LevelData, asset_id: String) -> Node3D:
	for a in level.map.assets:
		if String(a.get("id", "")) != asset_id:
			continue
		var file := String(a.get("file", ""))
		# Only files inside the level folder, and only model files.
		if file.contains("..") or file.is_absolute_path() \
				or not MODEL_EXTENSIONS.has(file.get_extension().to_lower()):
			push_warning("Level asset %s: not allowed (%s)" % [asset_id, file])
			return null
		return load_model(level.dir.path_join(file))
	push_warning("Level asset %s isn't in map.json's assets" % asset_id)
	return null


static func load_model(path: String) -> Node3D:
	if not _cache.has(path):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err := doc.append_from_file(path, state)
		if err != OK:
			push_warning("Couldn't load %s (%s)" % [path, error_string(err)])
			_cache[path] = null
		else:
			var scene := doc.generate_scene(state) as Node3D
			_strip_scripts(scene)
			var packed := PackedScene.new()
			_own(scene, scene)
			packed.pack(scene)
			scene.free()
			_cache[path] = packed
	var cached: PackedScene = _cache[path]
	return cached.instantiate() as Node3D if cached else null


static func clear_cache() -> void:
	_cache.clear()


## A built-in blockout shape: box, cylinder or ramp, `size` metres, colored.
static func builtin(kind: String, size: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	match kind:
		"builtin:cylinder":
			var cm := CylinderMesh.new()
			cm.top_radius = size.x * 0.5
			cm.bottom_radius = size.x * 0.5
			cm.height = size.y
			cm.material = mat
			mesh.mesh = cm
		"builtin:ramp":
			# A wedge rising toward -Z.
			var pm := PrismMesh.new()
			pm.left_to_right = 0.0
			pm.size = Vector3(size.z, size.y, size.x)
			pm.material = mat
			mesh.mesh = pm
			mesh.rotation_degrees.y = 90.0
		_:
			var bm := BoxMesh.new()
			bm.size = size
			bm.material = mat
			mesh.mesh = bm
	mesh.position.y = size.y * 0.5
	root.add_child(mesh)
	return root


## Adds collision on the world layer under `root`, from its meshes.
static func add_collision(root: Node3D, mode: String) -> void:
	if mode == "none":
		return
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	for mi in _meshes(root):
		var shape := CollisionShape3D.new()
		shape.transform = _relative(root, mi)
		if mode == "mesh":
			shape.shape = mi.mesh.create_trimesh_shape()
		else:
			var aabb := mi.mesh.get_aabb()
			var box := BoxShape3D.new()
			box.size = aabb.size
			shape.shape = box
			shape.transform = shape.transform * Transform3D(Basis(), aabb.get_center())
		if shape.shape:
			body.add_child(shape)


static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh:
			out.append(child)
		out.append_array(_meshes(child))
	return out


static func _relative(root: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## glTF can't carry Godot scripts, but be sure nothing in it runs anyway.
static func _strip_scripts(node: Node) -> void:
	node.set_script(null)
	for child in node.get_children():
		_strip_scripts(child)


static func _own(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_own(child, owner)
