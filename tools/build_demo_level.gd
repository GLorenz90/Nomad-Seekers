extends SceneTree
## Writes the demo data level (format 2) to res://levels/test_1/demo/, using
## LevelData the way the level editor will. It's a Small level (5 rooms)
## that uses something from every layer, so it doubles as the format's
## worked example and as the level the tests play:
##   godot --headless --path . --script res://tools/build_demo_level.gd
##
## Built from boxes (floors and obstacle walls); room boundaries across each
## corridor's ends split the navmesh into rooms and corridors.
## Layout (looking north, -Z), rooms 16 x 16 m on the 4 m grid:
##   Landing (z 0)      start, depot, box, Lumidium, a dialogue zone, a button
##                      that opens the gate north
##   corridor           a Grub Hound that wanders and gives up a chase
##   Arena (z -24)      two waves; the way in shuts during the fight and the
##                      way on opens when it's cleared
##   corridor
##   Bridge hall (z -48) a pit; two floor plates extend the bridge
##   corridor
##   Platform room (z -72) a pit; a moving platform ferries you over
##   corridor
##   Boss room (z -96)  the whole party at the door starts a holo-call; when
##                      it ends the fight starts; below 50% HP the boss
##                      enrages (a banner); beating it wakes the exit pad

const OUT := "res://levels/test_1/demo"
const ROOM := 16.0
const WALL_H := 4.0
const FLOOR_COLOR := [0.42, 0.45, 0.4]
const WALL_COLOR := [0.5, 0.5, 0.56]

var level: LevelData
var _n := 0


func _initialize() -> void:
	level = LevelData.create("Demo Run", "test_1")
	level.meta.author = "Nomad's Seekers"
	level.meta.description = "A worked example of every level editor layer."
	level.map.lighting = {"preset": "dusk", "sun_energy": 1.1, "ambient_energy": 1.1}
	level.map.start = {"pos": [0, 0.1, 4], "yaw": 0}
	_rooms()
	_interaction()
	_combat()
	# Rooms are areas of the navmesh: bake with the room boundaries cut in
	# and save each area's polygons (what the editor does on save).
	var found := LevelNav.assign_areas(level, LevelNav.bake(level, Callable(), true))
	for id in found.added:
		printerr("problem: an unplanned area appeared: ", id, " at ", level.find_area(id).seed)
	for id in found.removed:
		printerr("problem: area ", id, " found no navmesh")
	var problems := level.validate(Enemy.known_ids())
	for p in problems:
		printerr("problem: ", p)
	var err := level.save_dir(ProjectSettings.globalize_path(OUT))
	print("wrote %s (%s), %d problem(s)" % [OUT, error_string(err), problems.size()])
	quit(1 if err != OK or not problems.is_empty() else 0)


func _id(prefix: String) -> String:
	_n += 1
	return "%s_%d" % [prefix, _n]


## A built-in box: floors are walked on, walls are obstacles.
func _box(pos: Vector3, size: Vector3, color: Array, surface := "obstacle") -> void:
	level.map.pieces.append({"id": _id("piece"), "asset": "builtin:box", "pos": LevelData.arr3(pos),
		"size": LevelData.arr3(size), "color": color, "surface": surface})


func _floor(pos: Vector3, size: Vector3) -> void:
	_box(pos, size, FLOOR_COLOR, "floor")


# --- Layer 1 -------------------------------------------------------------------------------

func _rooms() -> void:
	var names := ["Landing", "Arena", "Bridge hall", "Platform room", "Boss room"]
	for i in 5:
		var z := -24.0 * i
		var pit := i == 2 or i == 3
		var area := {"id": "room_%d" % (i + 1), "kind": "room", "name": names[i],
			"seed": [0, 0, z + 6 if pit else z - 2], "color": LevelNav.area_color(i)}
		if pit:
			# Floor before and after an 8 m pit (z+4 .. z-4): both halves are one room.
			area.also = [[0, 0, z - 6]]
			_floor(Vector3(0, -1, z + 6), Vector3(ROOM, 1, 4))
			_floor(Vector3(0, -1, z - 6), Vector3(ROOM, 1, 4))
		else:
			_floor(Vector3(0, -1, z), Vector3(ROOM, 1, ROOM))
		level.map.areas.append(area)
		_box(Vector3(-ROOM / 2 - 0.5, 0, z), Vector3(1, WALL_H, ROOM), WALL_COLOR)
		_box(Vector3(ROOM / 2 + 0.5, 0, z), Vector3(1, WALL_H, ROOM), WALL_COLOR)
		for side: float in [-1.0, 1.0]:  # north (-1) and south (+1) walls
			var wz := z + side * (ROOM / 2 + 0.5)
			var doorway := (side < 0 and i < 4) or (side > 0 and i > 0)
			if doorway:
				for x: float in [-5.0, 5.0]:
					_box(Vector3(x, 0, wz), Vector3(6, WALL_H, 1), WALL_COLOR)
			else:
				_box(Vector3(0, 0, wz), Vector3(ROOM + 2, WALL_H, 1), WALL_COLOR)
		if i < 4:
			var cz := z - 12.0
			level.map.areas.append({"id": "hall_%d" % (i + 1), "kind": "corridor", "name": "",
				"seed": [0, 0, cz], "color": LevelNav.area_color(5 + i)})
			_floor(Vector3(0, -1, cz), Vector3(4, 1, 8))
			# Room boundaries where the corridor meets each room's doorway.
			for bz: float in [z - 8.5, z - 15.5]:
				level.map.boundaries.append({"id": _id("boundary"), "pos": [0, -0.5, bz], "rot": [0, 0, 0], "size": [4, 5]})
			_box(Vector3(-2.5, 0, cz), Vector3(1, WALL_H, 8), WALL_COLOR)
			_box(Vector3(2.5, 0, cz), Vector3(1, WALL_H, 8), WALL_COLOR)
	# A Seeker-only wall: the arena's north-west corner is a pen enemies can
	# leave but Seekers can't enter.
	level.map.walls.append({"id": "arena_pen", "pos": [-6, 0, -30], "size": [0.4, 2, 4],
		"blocks": "seekers"})
	level.map.decorations.append_array([
		{"id": "fireflies", "asset": "builtin:fireflies", "pos": [0, 0, -2], "size": [12, 3, 12]},
		{"id": "lamp", "asset": "builtin:light", "pos": [6, 3, 6], "color": [1, 0.8, 0.55],
			"energy": 1.5, "range": 10},
		{"id": "beacon", "asset": "builtin:searchlight", "pos": [6, 3.5, -102]},
	])
	level.map.pieces.append({"id": "sapling", "asset": "builtin:cylinder", "pos": [-6, 0, 6], "size": [0.6, 3, 0.6],
		"color": [0.3, 0.55, 0.3], "surface": "intangible", "animation": {"preset": "sway", "amount": 1.0}})


# --- Layer 2 -------------------------------------------------------------------------------

func _interaction() -> void:
	var it := level.interaction
	it.objects.append_array([
		{"id": "depot_start", "type": "lumidium_depot", "pos": [4, 0, 5]},
		{"id": "crate_1", "type": "box", "pos": [-5, 0, -3]},
		{"id": "crystal_1", "type": "lumidium_node", "pos": [5, 0, -4], "color": "nature", "yield": 3},
		{"id": "gate_button", "type": "button", "mode": "press", "pos": [-4, 0, -5]},
		{"id": "gate", "type": "door", "pos": [0, 0, -8.5], "size": [4, 4, 0.6], "start": "closed",
			"label": "Press the button"},
		{"id": "hello_zone", "type": "trigger_zone", "pos": [0, 0, 2], "size": [6, 3, 4]},
		{"id": "arena_in", "type": "door", "pos": [0, 0, -15.5], "start": "open",
			"shut_during_combat": "room_2"},
		{"id": "arena_out", "type": "door", "pos": [0, 0, -32.5], "start": "closed",
			"open_when_cleared": "room_2", "label": "LOCKED"},
		{"id": "trap_1", "type": "trap", "kind": "slow", "pos": [0, 0, -36]},
		{"id": "plate_a", "type": "button", "mode": "floor", "pos": [-5, 0, -42]},
		{"id": "plate_b", "type": "button", "mode": "floor", "pos": [5, 0, -42]},
		{"id": "bridge_1", "type": "bridge", "pos": [0, 0, -44], "yaw": 0, "length": 8, "width": 4},
		{"id": "ferry", "type": "platform", "size": [4, 0.5, 4], "mode": "ping_pong", "speed": 2.5,
			"wait": 1.5, "points": [[0, 0, -70], [0, 0, -74]]},
		{"id": "mist", "type": "hazard", "kind": "poison_mist", "zones": [{"pos": [0, 0, -84], "size": [4, 3, 8]}]},
		{"id": "mist_button", "type": "button", "mode": "press", "pos": [6, 0, -66]},
		{"id": "boss_door", "type": "trigger_zone", "pos": [0, 0, -89.5], "size": [4, 3, 3],
			"whole_party": true},
		{"id": "boss_in", "type": "door", "pos": [0, 0, -87.5], "start": "open",
			"shut_during_combat": "room_5"},
		{"id": "exit", "type": "teleporter", "pos": [0, 0, -100], "destination": "hub",
			"label": "Back to Nomad-2", "dormant": true},
		{"id": "depot_end", "type": "lumidium_depot", "pos": [4, 0, -100]},
	])
	it.button_groups.append({"id": "plates", "buttons": ["plate_a", "plate_b"], "once": true})
	it.dialogues.append_array([
		{"id": "hello", "lines": [
			{"speaker": "SyncAIDa", "text": "Demo level loaded. Every layer of the level editor is in here."},
			{"speaker": "SyncAIDa", "text": "The gate opens with the button on the left."}]},
		{"id": "boss_intro", "lines": [
			{"speaker": "Commander Brandt", "text": "Something big is in there, Seeker. Ready?"}],
			"choices": [{"id": "ready", "text": "Ready."}, {"id": "go", "text": "Let's go."}]},
	])
	it.flags = {"enraged": false}
	it.rules.append_array([
		{"id": "say_hello", "when": {"event": "entered", "source": "hello_zone"},
			"do": [{"action": "start_dialogue", "target": "hello"}]},
		{"id": "open_gate", "when": {"event": "pressed", "source": "gate_button"},
			"do": [{"action": "open", "target": "gate"}]},
		{"id": "bridge_out", "when": {"event": "pressed", "source": "plates"},
			"do": [{"action": "extend", "target": "bridge_1"}, {"action": "banner", "text": "The bridge slides out"}]},
		{"id": "clear_mist", "when": {"event": "pressed", "source": "mist_button"},
			"do": [{"action": "disable", "target": "mist"}]},
		{"id": "boss_call", "when": {"event": "party_present", "source": "boss_door"},
			"do": [{"action": "start_dialogue", "target": "boss_intro"}]},
		{"id": "boss_fight", "when": {"event": "dialogue_ended", "source": "boss_intro"},
			"do": [{"action": "start_combat", "target": "room_5"}]},
		{"id": "enrage", "when": {"event": "health_below", "source": "boss", "value": 50},
			"if": [{"check": "flag", "flag": "enraged", "is": false}],
			"do": [{"action": "set_flag", "flag": "enraged", "value": true},
				{"action": "banner", "text": "The Umbral Eye is enraged!"}]},
		{"id": "won", "when": {"event": "combat_ended", "source": "room_5"},
			"do": [{"action": "wait", "seconds": 1.0}, {"action": "wake", "target": "exit"},
				{"action": "complete_objective", "key": "demo_boss"},
				{"action": "give_item", "item": "oro", "amount": 250},
				{"action": "banner", "text": "The exit pad is awake"}]},
	])


# --- Layer 3 -------------------------------------------------------------------------------

func _combat() -> void:
	level.combat.free.append({"id": "hall_hound", "enemy": "grub_hound", "pos": [0, 0, -12], "yaw": 180,
		"wander": true, "wander_radius": 2.0, "limited_chase": true, "chase_radius": 10.0, "aggro": "short"})
	level.combat.rooms.append({"room": "room_2", "start": "enter", "waves": [
		{"enemies": [
			{"id": "arena_hound_a", "enemy": "grub_hound", "pos": [-4, 0, -26]},
			{"id": "arena_hound_b", "enemy": "grub_hound", "pos": [4, 0, -26]}]},
		{"enemies": [
			{"id": "arena_drone", "enemy": "sentry_drone", "pos": [0, 0, -29], "spawn_delay": 0.5},
			{"id": "arena_ooze", "enemy": "caustic_ooze", "pos": [-3, 0, -22], "spawn_delay": 1.25}]},
	]})
	level.combat.rooms.append({"room": "room_5", "start": "event", "waves": [
		{"enemies": [{"id": "boss", "enemy": "umbral_eye", "pos": [0, 0, -98]}]},
		{"enemies": [
			{"id": "sprite_a", "enemy": "lumen_sprite", "pos": [-5, 0, -98], "spawn_delay": 0.5},
			{"id": "sprite_b", "enemy": "lumen_sprite", "pos": [5, 0, -98], "spawn_delay": 0.5}]},
	]})
