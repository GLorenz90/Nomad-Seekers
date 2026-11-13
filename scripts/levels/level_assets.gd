class_name LevelAssets
extends RefCounted
## Models for data levels (Part 13a). Imported assets are glTF / GLB files in
## the level's assets/ folder, loaded at runtime with GLTFDocument, so they
## work for levels that were never imported by the Godot editor (your own
## and, later, the workshop's). Built-in pieces ("builtin:box"...) let a
## level be blocked out without importing anything.
##
## Collision (format 2): a piece that's a floor or an obstacle gets a hitbox
## made from its meshes, "concave" (every triangle; static only) or "convex"
## (one hull per mesh); intangible pieces get none (LevelData.SURFACES).

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


## A built-in blockout shape: box, cylinder or ramp, `size` metres, colored
## (the same shapes the editor and the navmesh use: LevelNav.builtin_meshes).
## `params` are its shape settings (a curved wall's bend, a stair's steps);
## `material`, when given, replaces the plain color.
static func builtin(kind: String, size: Vector3, color: Color, params := {}, material: Material = null) -> Node3D:
	var root := Node3D.new()
	var mat := material
	if mat == null:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = color
		mat = plain
	for m in LevelNav.builtin_meshes(kind, size, params):
		var mesh := MeshInstance3D.new()
		mesh.mesh = m[0]
		mesh.material_override = mat
		mesh.transform = m[1]
		root.add_child(mesh)
	return root


## Puts one material on every mesh of a model (a level material on an
## imported model).
static func apply_material(root: Node, material: Material) -> void:
	for mi in _meshes(root):
		mi.material_override = material


## A static body on the world layer holding a piece's hitbox (LevelNav.hitbox).
static func collision_body(hit: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = hit.xform
	for pair in hit.shapes:
		var shape := CollisionShape3D.new()
		shape.shape = pair[0]
		shape.transform = pair[1]
		body.add_child(shape)
	return body


## Adds a hitbox under an unscaled model ("concave" or "convex").
static func add_collision(root: Node3D, hitbox: String) -> void:
	if hitbox == "none" or hitbox == "":
		return
	var shapes := LevelNav.shapes_for(LevelNav.node_meshes(root), Vector3.ONE, hitbox == "convex")
	root.add_child(collision_body({"xform": Transform3D.IDENTITY, "shapes": shapes}))


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
