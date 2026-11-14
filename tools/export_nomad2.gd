extends SceneTree
## Writes a read-only copy of Nomad-2 for the level editor (Grayson
## 2026-11-13: quests add people and props on top of a fixed Nomad-2): its
## floor, walls and counters as boxes, its signs, and where the teleporter,
## depot, clerks and spawn point are. Run it after changing the hub, then copy
## the file into the editor (catalog/nomad2_base.json).
##   godot --headless --path . --script res://tools/export_nomad2.gd -- <out.json>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := args[0] if args.size() > 0 else ProjectSettings.globalize_path("user://nomad2_base.json")
	var hub := (load("res://scenes/hub.tscn") as PackedScene).instantiate()
	var data := {"format": 1, "source": "res://scenes/hub.tscn", "pieces": [], "labels": [], "markers": []}
	for node in hub.find_children("*", "CSGBox3D", true, false):
		var box := node as CSGBox3D
		var at := _world(box)
		data.pieces.append({"id": "nomad2_" + String(box.name).to_snake_case(), "name": String(box.name).capitalize(),
			"asset": "builtin:box", "size": _arr(box.size), "pos": _arr(at.origin - Vector3(0, box.size.y * 0.5, 0)),
			"yaw": snappedf(rad_to_deg(at.basis.get_euler().y), 0.1), "color": _color(box.material), "surface": "floor" if box.name == "Floor" else "obstacle"})
	for node in hub.find_children("*", "Label3D", true, false):
		var label := node as Label3D
		data.labels.append({"text": label.text, "pos": _arr(_world(label).origin), "size": label.font_size})
	for node in hub.get_children():
		var kind := ""
		if node.name == "Player":
			kind = "start"
		elif node is Teleporter:
			kind = "teleporter"
		elif node is LumidiumDepot:
			kind = "depot"
		elif node is ServiceCounter:
			kind = "clerk"
		if kind != "":
			data.markers.append({"type": kind, "name": String(node.name).capitalize(), "pos": _arr((node as Node3D).position)})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t", false))
	f.close()
	hub.free()
	print("wrote ", out_path)
	quit()


func _world(node: Node3D) -> Transform3D:
	var t := node.transform
	var p := node.get_parent()
	while p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


func _color(mat: Material) -> Array:
	var c := Color(0.5, 0.5, 0.55)
	if mat is StandardMaterial3D:
		c = (mat as StandardMaterial3D).albedo_color
	elif mat is ShaderMaterial and (mat as ShaderMaterial).get_shader_parameter("base_color") is Color:
		c = (mat as ShaderMaterial).get_shader_parameter("base_color")
	return [snappedf(c.r, 0.01), snappedf(c.g, 0.01), snappedf(c.b, 0.01)]
