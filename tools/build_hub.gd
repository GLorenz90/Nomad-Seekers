extends SceneTree
## Builds scenes/hub.tscn: Nomad-2's lobby (Part 8), the hub every character
## enters from the title screen. No full levels yet: its teleporter goes to the
## gym and the test arena. Part 10: the counters work (ServiceCounter): the
## Guild and the bank on the west wall, the weapons, armor and curatives shops
## on the east wall. After generating, edit the scene in the editor (rerunning this
## overwrites it):
##   godot --headless --path . --script res://tools/build_hub.gd
##
## Layout (looking north, -Z): spawn at the south end, the teleporter at the
## north end, counters along the east and west walls.

const WALL_H := 5.0

var _root: Node3D
var _level: Node3D
var _mats := {}


func _initialize() -> void:
	_root = Node3D.new()
	_root.name = "Hub"
	_root.set_script(load("res://scripts/levels/hub_level.gd"))
	_root.set("peaceful", true)  # no fighting in Nomad-2 (Grayson, 2026-11-10)

	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.04, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.62, 0.75)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	_add(_root, env)

	var light := DirectionalLight3D.new()
	light.name = "CeilingLight"
	light.shadow_enabled = true
	light.light_energy = 0.8
	light.rotation_degrees = Vector3(-70.0, 20.0, 0.0)
	_add(_root, light)

	var nav := NavigationRegion3D.new()
	nav.name = "Navigation"
	var navmesh := NavigationMesh.new()
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_collision_mask = 1
	navmesh.agent_height = 2.0
	navmesh.agent_radius = 0.5
	navmesh.agent_max_climb = 0.25
	nav.navigation_mesh = navmesh
	_add(_root, nav)
	_level = Node3D.new()
	_level.name = "Level"
	_add(nav, _level)
	_build_level()

	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	player.name = "Player"
	_add(_root, player)
	player.position = Vector3(0.0, 0.1, 10.0)
	var rig := (load("res://scenes/camera/camera_rig.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	rig.name = "CameraRig"
	_add(_root, rig)
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	hud.name = "HUD"
	_add(_root, hud)

	var pad := Area3D.new()
	pad.name = "Teleporter"
	pad.set_script(load("res://scripts/world/teleporter.gd"))
	pad.set("destinations", PackedStringArray(["res://scenes/main.tscn", "res://scenes/arena.tscn", "area:test_1"]))
	pad.set("destination_names", PackedStringArray(["The gym (test room)", "The test arena (wave rooms)",
		"Demo level (made from data)"]))
	pad.position = Vector3(0, 0, -10)
	_add(_root, pad)

	# Lumidium depot by the bank (Grayson, 2026-11-10).
	var depot := Node3D.new()
	depot.name = "LumidiumDepot"
	depot.set_script(load("res://scripts/world/lumidium_depot.gd"))
	depot.position = Vector3(-10, 0, 7.5)
	_add(_root, depot)

	var packed := PackedScene.new()
	var err := packed.pack(_root)
	if err == OK:
		err = ResourceSaver.save(packed, "res://scenes/hub.tscn")
	print("res://scenes/hub.tscn -> %s" % error_string(err))
	_root.free()
	quit()


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = _root
	for c in child.get_children():
		if c.owner == null:
			c.owner = _root


func _mat(key: String, base: Color, line: Color) -> ShaderMaterial:
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://assets/shaders/blockout_grid.gdshader")
		m.set_shader_parameter("base_color", base)
		m.set_shader_parameter("line_color", line)
		_mats[key] = m
	return _mats[key]


func _box(parent: Node, node_name: String, size: Vector3, pos: Vector3, mat: Material) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = node_name
	b.size = size
	b.position = pos
	b.use_collision = true
	b.material = mat
	_add(parent, b)
	return b


func _build_level() -> void:
	var floor_mat := _mat("floor", Color(0.32, 0.36, 0.42), Color(0.24, 0.28, 0.34))
	var wall_mat := _mat("wall", Color(0.22, 0.26, 0.36), Color(0.16, 0.19, 0.27))
	var counter_mat := _mat("counter", Color(0.45, 0.4, 0.3), Color(0.35, 0.3, 0.22))
	_box(_level, "Floor", Vector3(32, 1, 30), Vector3(0, -0.5, 0), floor_mat)
	_box(_level, "WallNorth", Vector3(32, WALL_H, 1), Vector3(0, WALL_H / 2.0, -15.5), wall_mat)
	_box(_level, "WallSouth", Vector3(32, WALL_H, 1), Vector3(0, WALL_H / 2.0, 15.5), wall_mat)
	_box(_level, "WallWest", Vector3(1, WALL_H, 30), Vector3(-16.5, WALL_H / 2.0, 0), wall_mat)
	_box(_level, "WallEast", Vector3(1, WALL_H, 30), Vector3(16.5, WALL_H / 2.0, 0), wall_mat)
	# Service counters (Part 10): [name, counter centre, ServiceCounter.Service].
	var counters := Node3D.new()
	counters.name = "Counters"
	_add(_level, counters)
	for spec in [["Guild", Vector3(-13, 0, -6), 4], ["Bank", Vector3(-13, 0, 3), 3],
			["Weapons", Vector3(13, 0, -8), 0], ["Armor", Vector3(13, 0, -1), 1], ["Curatives", Vector3(13, 0, 6), 2]]:
		var at: Vector3 = spec[1]
		var counter := _box(counters, "%sCounter" % spec[0], Vector3(3, 1.1, 5), at + Vector3(0, 0.55, 0), counter_mat)
		var sign := Label3D.new()
		sign.name = "Sign"
		sign.text = spec[0]
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.font_size = 48
		sign.outline_size = 10
		sign.modulate = Color(1.0, 0.9, 0.6)
		sign.position = Vector3(0, 1.8, 0)
		_add(counter, sign)
		# The clerk's spot: just in front of the counter, facing the room.
		var clerk := Node3D.new()
		clerk.name = "%sClerk" % spec[0]
		clerk.set_script(load("res://scripts/world/service_counter.gd"))
		clerk.set("service", spec[2])
		clerk.position = at + Vector3(-1.9 if at.x > 0 else 1.9, 0, 0)
		_add(_root, clerk)
	var title := Label3D.new()
	title.name = "Title"
	title.text = "NOMAD-2"
	title.font_size = 120
	title.outline_size = 16
	title.modulate = Color(0.7, 0.9, 1.0)
	title.position = Vector3(0, 3.6, -14.9)
	_add(_level, title)
