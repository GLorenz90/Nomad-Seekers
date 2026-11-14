class_name DataLevel
extends "res://scripts/main.gd"
## A level made in the level editor (Part 13a): built at load from its JSON
## folder (LevelData, docs/level_format.md), then run like any other level
## (main.gd: Seekers, co-op, loot, respawns, the navmesh bake).
##
## Built only from the game's own pieces (a whitelist): models come from
## glTF files and the level's JSON; nothing in a level can run code.
##
## Layer 1 (map.json)          lighting, start, pieces (floor / obstacle /
##                             intangible), invisible walls, areas (rooms and
##                             corridors), decorations
## Layer 2 (interaction.json)  doors, teleporters, depots, Lumidium, boxes,
##                             traps, buttons, hazards, trigger zones,
##                             platforms, bridges, dialogue, wiring (LevelEvents)
## Layer 3 (combat.json)       wave rooms and corridor enemies
##
## The navmesh comes from LevelNav (shared with the editor): floors are
## walked on, obstacles block it, sized for a Seeker. Doors, platforms,
## bridges and Seeker-only walls stay out of it (Part 4's rule for doors).

## The level folder (set by Maps.instantiate before it enters the tree).
@export var level_path := ""
## Laid over a hand-built scene (HubLevel: a quest's Nomad-2 additions): the
## scene keeps its own lighting, start and navmesh bake, and no folder is fine.
var overlay := false

var data: LevelData
var events: LevelEvents
## id -> LevelRoom for every room and corridor (navmesh areas).
var rooms := {}
var _props: Node3D
var _objects: Node3D
var _enemies: Node3D


func _ready() -> void:
	if map_id == "":
		map_id = level_path
	events = LevelEvents.new()
	events.name = "LevelEvents"
	events.level = self
	add_child(events)
	data = LevelData.load_dir(level_path) if level_path != "" else null
	if data == null and not overlay:
		push_error("No level at %s" % level_path)
		_fallback_floor()
	elif data != null:
		_build()
	else:
		_props = _group_node(self, "Props")
		_objects = _group_node(self, "Objects")
		_enemies = _group_node(self, "Enemies")
	super._ready()
	navmesh_ready.connect(func():
		_bring_escorts()
		events.emit_event("level_started"), CONNECT_ONE_SHOT)
	if data == null and not overlay:
		banner.call_deferred("Couldn't load this level")


func _build() -> void:
	if not overlay:
		for node in LevelLighting.build(data.map.lighting):
			add_child(node)
		var start: Dictionary = data.map.start
		player.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(start.get("yaw", 0.0)))),
			LevelData.vec3(start.get("pos")))
	_props = _group_node(self, "Props")
	_objects = _group_node(self, "Objects")
	_enemies = _group_node(self, "Enemies")
	_build_map()
	_build_interaction()
	_build_combat()


static func _group_node(parent: Node, node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	parent.add_child(n)
	return n


func _solid() -> Node3D:
	return $Navigation/Level


static func _place(node: Node3D, spec: Dictionary) -> void:
	node.position = LevelData.vec3(spec.get("pos"))
	if spec.get("rot") is Array:
		node.rotation_degrees = LevelData.vec3(spec.rot)
	else:
		node.rotation_degrees = Vector3(0.0, float(spec.get("yaw", 0.0)), 0.0)
	if spec.get("scale") is Array:
		var s := LevelData.vec3(spec.scale, Vector3.ONE)
		node.scale = Vector3(clampf(s.x, 0.01, 100.0), clampf(s.y, 0.01, 100.0), clampf(s.z, 0.01, 100.0))


static func _color(v, fallback: Color) -> Color:
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
	return fallback


# --- Layer 1: map -----------------------------------------------------------------------------

func _build_map() -> void:
	for a in data.map.areas:
		var room := LevelRoom.new()
		room.room_id = String(a.get("id", ""))
		room.name = "Room_" + room.room_id
		room.kind = String(a.get("kind", "room"))
		room.area = a
		room.position = LevelData.vec3(a.get("seed"))
		add_child(room)
		rooms[room.room_id] = room
		events.objects[room.room_id] = room
	for p in data.map.pieces:
		_add_piece(p)
	for w in data.map.walls:
		var wall := InvisibleWall.new()
		wall.name = "Wall_" + String(w.get("id", ""))
		wall.size = LevelData.vec3(w.get("size"), Vector3(4, 4, 0.4))
		wall.seekers_only = String(w.get("blocks", "all")) == "seekers"
		_place(wall, w)
		(_props if wall.seekers_only else _solid()).add_child(wall)
	for spec in data.map.decorations:
		var d: Dictionary = spec
		var asset := String(d.get("asset", ""))
		var node: Node3D
		match asset:
			"builtin:fireflies":
				node = _fireflies(d)
				_props.add_child(node)
			"builtin:light":
				node = LevelLighting.point_light(_color(d.get("color"), Color(1.0, 0.85, 0.6)),
					float(d.get("energy", 1.0)), float(d.get("range", 6.0)))
				_place(node, d)
				_props.add_child(node)
			"builtin:searchlight":
				var spot := SpotLight3D.new()
				spot.light_color = _color(d.get("color"), Color(1.0, 0.95, 0.8))
				spot.light_energy = clampf(float(d.get("energy", 2.0)), 0.0, 4.0)
				spot.spot_range = clampf(float(d.get("range", 18.0)), 2.0, 30.0)
				spot.spot_angle = 18.0
				spot.shadow_enabled = true
				node = Node3D.new()
				_place(node, d)
				node.add_child(spot)
				spot.rotation_degrees.x = -25.0
				_props.add_child(node)
				if not d.has("animation"):
					d = d.duplicate()
					d.animation = {"preset": "sweep"}
			_:
				push_warning("Unknown decoration %s" % asset)
		if node and d.get("animation") is Dictionary:
			var anim := DecorAnimator.new()
			anim.preset = String(d.animation.get("preset", "none"))
			anim.amount = float(d.animation.get("amount", 1.0))
			anim.speed = float(d.animation.get("speed", 1.0))
			node.add_child(anim)


## A piece: an imported model or a built-in shape. Floors and obstacles get a
## hitbox (concave or convex); intangible pieces get none and may be animated.
func _add_piece(spec: Dictionary) -> Node3D:
	var asset := String(spec.get("asset", "builtin:box"))
	var model: Node3D
	var material := LevelMaterials.build(data, String(spec.get("material", "")))
	if asset.begins_with("builtin:"):
		model = LevelAssets.builtin(asset, LevelData.vec3(spec.get("size"), Vector3(4, 0.5, 4)),
			_color(spec.get("color"), Color(0.55, 0.57, 0.6)), LevelNav.shape_params(spec), material)
	else:
		model = LevelAssets.model(data, asset)
		if model == null:
			return null
		if material:
			LevelAssets.apply_material(model, material)
	model.name = String(spec.get("id", "Piece"))
	var surface := data.surface_of(spec)
	model.transform = LevelNav.transform_of(spec)
	(_props if surface == "intangible" else _solid()).add_child(model)
	if surface != "intangible":
		var hit := LevelNav.hitbox(spec, data, func(id: String) -> Node3D: return LevelAssets.model(data, id))
		var body := LevelAssets.collision_body(hit)
		body.name = model.name + "_Collision"
		_solid().add_child(body)
	if surface == "intangible" and spec.get("animation") is Dictionary:
		var anim := DecorAnimator.new()
		anim.preset = String(spec.animation.get("preset", "none"))
		anim.amount = float(spec.animation.get("amount", 1.0))
		anim.speed = float(spec.animation.get("speed", 1.0))
		model.add_child(anim)
	return model


## People the party is escorting (QuestSession) come along: the ones placed
## here start following, the rest appear beside the first Seeker.
func _bring_escorts() -> void:
	var leader := Scope.first(self, "player") as Node3D
	var i := 0
	for e in QuestSession.escorts():
		var here := events.objects.get(String(e.id)) as Person
		if here == null:
			here = Person.from_spec(e)
			here.name = "Escort_" + String(e.id)
			events.objects[String(e.id)] = here
			_objects.add_child(here)
			if leader:
				here.global_position = leader.global_position + Vector3(1.5 + i, 0.0, 1.5)
			here.talked.connect(events.on_talked)
			i += 1
		here.shown_override = true
		here.escorting = true
		here.refresh()


## The navmesh: LevelNav's bake (the same one the editor shows), on a
## navigation map with the matching cell size. An overlay keeps its scene's
## own bake (which takes in the overlay's floors and obstacles too).
func _bake_navmesh() -> void:
	await get_tree().process_frame
	if overlay:
		await get_tree().physics_frame
		navigation.bake_navigation_mesh(false)
	elif data != null:
		var map_rid := get_world_3d().navigation_map
		NavigationServer3D.map_set_cell_size(map_rid, LevelData.NAV.cell)
		NavigationServer3D.map_set_cell_height(map_rid, LevelData.NAV.cell_height)
		navigation.navigation_mesh = LevelNav.bake(data, func(id: String) -> Node3D: return LevelAssets.model(data, id))
	else:
		await get_tree().physics_frame
		navigation.bake_navigation_mesh(false)
	navmesh_ready.emit()


func _fireflies(d: Dictionary) -> Node3D:
	var size := LevelData.vec3(d.get("size"), Vector3(6, 3, 6))
	var p := GPUParticles3D.new()
	p.amount = clampi(int(d.get("amount", 24)), 1, 200)
	p.lifetime = 4.0
	p.visibility_aabb = AABB(-size, size * 2.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = size * 0.5
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.3
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.turbulence_enabled = true
	p.process_material = pm
	var dot := SphereMesh.new()
	dot.radius = 0.04
	dot.height = 0.08
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _color(d.get("color"), Color(1.0, 0.95, 0.5))
	dot.material = mat
	p.draw_pass_1 = dot
	_place(p, d)
	p.position.y += size.y * 0.5
	return p


# --- Layer 2: interaction -------------------------------------------------------------------

func _build_interaction() -> void:
	var sugar: Array = []
	var buttons := {}
	for o in data.interaction.objects:
		var id := String(o.get("id", ""))
		var node := _make_object(o)
		if node == null:
			continue
		node.name = id if id != "" else node.name
		_objects.add_child(node)
		events.objects[id] = node
		match String(o.type):
			"button":
				buttons[id] = node
			"door":
				# The door shortcuts (Grayson: a door opens by a button, or at
				# the end of combat).
				var cleared := String(o.get("open_when_cleared", ""))
				if cleared != "":
					sugar.append({"id": "_%s_cleared" % id, "when": {"event": "combat_ended", "source": cleared},
						"do": [{"action": "open", "target": id}]})
				var shut := String(o.get("shut_during_combat", ""))
				if shut != "":
					sugar.append({"id": "_%s_shut" % id, "when": {"event": "combat_started", "source": shut},
						"do": [{"action": "close", "target": id}]})
					sugar.append({"id": "_%s_reopen" % id, "when": {"event": "combat_ended", "source": shut},
						"do": [{"action": "open", "target": id}]})
	_build_buttons(buttons)
	for d in data.interaction.dialogues:
		events.dialogues[String(d.get("id", ""))] = d
	events.flags = (data.interaction.flags as Dictionary).duplicate()
	events.rules = sugar + data.interaction.rules


func _make_object(o: Dictionary) -> Node3D:
	var node: Node3D
	match String(o.get("type", "")):
		"person":
			var person := Person.from_spec(o)
			var model_id := String(person.look.get("model", ""))
			if model_id != "":
				person.model = LevelAssets.model(data, model_id)
			person.talked.connect(events.on_talked)
			node = person
		"door":
			var door := SwitchDoor.new()
			door.size = LevelData.vec3(o.get("size"), Vector3(4.2, 4.0, 0.6))
			door.label = String(o.get("label", "LOCKED"))
			door.is_open = String(o.get("start", "closed")) == "open"
			node = door
		"teleporter":
			var pad := Teleporter.new()
			pad.destination = String(o.get("destination", ""))
			pad.destination_name = String(o.get("label", ""))
			pad.requires_rooms_cleared = bool(o.get("requires_clear", false))
			pad.dormant = bool(o.get("dormant", false))
			node = pad
		"lumidium_depot":
			node = LumidiumDepot.new()
		"lumidium_node":
			var crystal := LumidiumNode.new()
			var color := String(o.get("color", "fire"))
			crystal.color = StringName(color if LevelData.LUMIDIUM_COLORS.has(color) else "fire")
			crystal.yield_amount = clampi(int(o.get("yield", 3)), 1, 10)
			var id := String(o.get("id", ""))
			crystal.tree_exiting.connect(func():
				if crystal.is_broken() and is_instance_valid(events):
					events.emit_event("node_broken", id))
			node = crystal
		"box":
			var box := SupplyBox.new()
			box.box_id = String(o.get("id", ""))
			box.contents = String(o.get("contents", "random"))
			box.broken.connect(func(b: SupplyBox): events.emit_event("box_broken", b.box_id))
			node = box
		"trap":
			var trap := HazardTrap.new()
			var kind := String(o.get("kind", "damage")).to_upper()
			trap.kind = HazardTrap.Kind.get(kind, HazardTrap.Kind.DAMAGE)
			node = trap
		"button":
			var button := RoomButton.new()
			button.mode = RoomButton.Mode.FLOOR if String(o.get("mode", "press")) == "floor" else RoomButton.Mode.PRESS
			node = button
		"hazard":
			var hazard := RoomHazard.new()
			hazard.kind = RoomHazard.Kind.DARKNESS if String(o.get("kind", "")) == "darkness" \
				else RoomHazard.Kind.POISON_MIST
			hazard.active = bool(o.get("active", true))
			for z in o.get("zones", []):
				var size := LevelData.vec3(z.get("size"), Vector3(16, 6, 16))
				var at := LevelData.vec3(z.get("pos"))
				hazard.zones.append(AABB(at - Vector3(size.x * 0.5, 0.0, size.z * 0.5), size))
			return hazard  # zones are world boxes: stays at the origin
		"trigger_zone":
			var zone := TriggerZone.new()
			zone.zone_id = String(o.get("id", ""))
			zone.size = LevelData.vec3(o.get("size"), Vector3(4, 4, 4))
			zone.once = bool(o.get("once", true))
			zone.whole_party = bool(o.get("whole_party", false))
			zone.enabled = bool(o.get("enabled", true))
			zone.entered.connect(func(z: TriggerZone, _s: Player): events.emit_event("entered", z.zone_id))
			zone.party_present.connect(func(z: TriggerZone): events.emit_event("party_present", z.zone_id))
			node = zone
		"platform":
			var platform := MovingPlatform.new()
			platform.platform_id = String(o.get("id", ""))
			platform.size = LevelData.vec3(o.get("size"), Vector3(4, 0.5, 4))
			platform.color = _color(o.get("color"), platform.color)
			for pt in o.get("points", []):
				platform.points.append(LevelData.vec3(pt))
			var mode := String(o.get("mode", "ping_pong"))
			platform.mode = mode if LevelData.PLATFORM_MODES.has(mode) else "ping_pong"
			platform.speed = float(o.get("speed", 2.0))
			platform.wait = float(o.get("wait", 1.0))
			platform.running = bool(o.get("running", true))
			return platform  # placed by its points
		"bridge":
			var bridge := Bridge.new()
			bridge.bridge_id = String(o.get("id", ""))
			bridge.length = clampf(float(o.get("length", 8.0)), 1.0, 64.0)
			bridge.width = clampf(float(o.get("width", 4.0)), 1.0, 16.0)
			bridge.extended = bool(o.get("extended", false))
			bridge.speed = float(o.get("speed", 4.0))
			node = bridge
		_:
			push_warning("Unknown object type %s" % o.get("type", ""))
			return null
	_place(node, o)
	return node


## Buttons belong to a SwitchGroup each: the level's button groups, and a
## group of one for every other button. A group "pressed" is the group's id
## (or the button's).
func _build_buttons(buttons: Dictionary) -> void:
	var grouped := {}
	var groups := []
	for g in data.interaction.button_groups:
		var members := []
		for b in g.get("buttons", []):
			if buttons.has(String(b)):
				members.append(buttons[String(b)])
				grouped[String(b)] = true
		groups.append([String(g.get("id", "")), members, bool(g.get("once", true))])
	for id in buttons:
		if not grouped.has(id):
			groups.append([id, [buttons[id]], true])
	for g in groups:
		var group := SwitchGroup.new()
		group.name = "Group_" + String(g[0])
		group.once = g[2]
		for b in g[1]:
			group.buttons.append((b as Node).get_path())
		var gid := String(g[0])
		group.fired.connect(func(): events.emit_event("pressed", gid))
		_objects.add_child(group)
		if not events.objects.has(gid):
			events.objects[gid] = group


# --- Layer 3: combat --------------------------------------------------------------------------

func _build_combat() -> void:
	for c in data.combat.rooms:
		var room_id := String(c.get("room", ""))
		var area: LevelRoom = rooms.get(room_id)
		if area == null:
			push_warning("Combat for %s, which isn't a room" % room_id)
			continue
		var wave_room := WaveRoom.new()
		wave_room.name = "Waves_" + room_id
		wave_room.room_id = room_id
		var room_spec := data.find_area(room_id)
		var shown := String(room_spec.get("name", ""))
		wave_room.room_name = shown if shown != "" else room_id.capitalize()
		wave_room.trigger_area = room_spec
		wave_room.start_on_enter = String(c.get("start", "enter")) == "enter"
		wave_room.start_delay = clampf(float(c.get("start_delay", 0.8)), 0.0, 10.0)
		wave_room.wave_delay = clampf(float(c.get("wave_delay", 1.0)), 0.0, 10.0)
		for w in c.get("waves", []):
			var wave := WaveData.new()
			for p in w.get("enemies", []):
				wave.placements.append(p)
			wave_room.waves.append(wave)
		for child_name in ["Doors", "SpawnPoints"]:
			var n := Node3D.new()
			n.name = child_name
			wave_room.add_child(n)
		wave_room.position = area.position
		_objects.add_child(wave_room)
		events.objects[room_id] = wave_room
		wave_room.combat_started.connect(func(r: WaveRoom): events.emit_event("combat_started", r.room_id))
		wave_room.wave_cleared.connect(func(r: WaveRoom, i: int): events.emit_event("wave_cleared", r.room_id, i + 1))
		wave_room.room_cleared.connect(func(r: WaveRoom): events.emit_event("combat_ended", r.room_id))
		wave_room.enemy_spawned.connect(func(_r: WaveRoom, e: Enemy): _watch_enemy(e))
	for p in data.combat.free:
		var enemy_data := Enemy.data_for(String(p.get("enemy", "")))
		if enemy_data == null:
			push_warning("Unknown enemy %s" % p.get("enemy", ""))
			continue
		var enemy := Enemy.create(enemy_data)
		enemy.configure(p)
		_enemies.add_child(enemy)
		enemy.global_position = LevelData.vec3(p.get("pos"))
		enemy.rotation = Vector3(0.0, deg_to_rad(float(p.get("yaw", 0.0))), 0.0)
		_watch_enemy(enemy)


## Reports an enemy's death and HP to the wiring (boss phases).
func _watch_enemy(enemy: Enemy) -> void:
	var id := enemy.placement_id
	if id == "":
		return
	events.objects[id] = enemy
	enemy.defeated.connect(func(_e: Enemy): events.emit_event("enemy_defeated", id))
	enemy.health.damaged.connect(func(_info: DamageInfo, _amount: float):
		events.emit_event("health_below", id, 100.0 * enemy.health.hp / maxf(enemy.health.max_hp, 1.0)))


# --- A level that didn't load ----------------------------------------------------------------

func _fallback_floor() -> void:
	var floor_box := CSGBox3D.new()
	floor_box.size = Vector3(20, 1, 20)
	floor_box.position.y = -0.5
	floor_box.use_collision = true
	_solid().add_child(floor_box)
	for node in LevelLighting.build({}):
		add_child(node)
