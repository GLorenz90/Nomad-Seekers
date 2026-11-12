class_name Maps
extends RefCounted
## Where a teleporter, quest or menu can send a Seeker (Part 13a, for the
## level editor). A map is one of:
## - a scene: "res://scenes/arena.tscn";
## - a data level (a folder made by the level editor): "res://levels/forest_1/glade";
## - an area: "area:forest_1", which becomes this session's pick from
##   res://levels/forest_1/ (Grayson, 2026-11-12: one folder per area,
##   including boss areas; one level per folder is picked when a session
##   starts and kept until the player quits to the title).
## - "hub": Nomad-2.
##
## Every level node has a map id (Maps.id_of): its scene path, or its level
## folder for data levels. Co-op, quests and the debug tab compare map ids.

const DATA_SCENE := "res://scenes/data_level.tscn"
## Official areas live here. Levels in user://levels/ (your own, or the
## workshop's later) can be played from the Debug tab but never enter the
## area rotation.
const AREA_ROOT := "res://levels"
const USER_ROOT := "user://levels"

## This session's pick per area: "forest_1" -> its level folder.
static var picks := {}
## Set by tests so picks repeat.
static var rng := RandomNumberGenerator.new()


static func is_data(path: String) -> bool:
	return not path.ends_with(".tscn") and not path.ends_with(".scn") \
		and not path.begins_with("area:") and path != "hub"


## The concrete map a destination means right now ("area:..." picks).
static func resolve(destination: String) -> String:
	if destination == "hub":
		return Session.HUB_SCENE
	if destination.begins_with("area:"):
		return pick(destination.trim_prefix("area:"))
	return destination


## This session's level for an area (picked the first time it's asked for).
## "" when the area folder has no levels.
static func pick(area: String) -> String:
	if picks.has(area):
		return picks[area]
	var options := levels_in(AREA_ROOT.path_join(area))
	if options.is_empty():
		return ""
	if rng.seed == 0:
		rng.randomize()
	picks[area] = options[rng.randi() % options.size()]
	return picks[area]


## A new session: every area picks again (Session.play, quit to title).
static func new_session() -> void:
	picks.clear()


## Level folders directly inside a folder, sorted.
static func levels_in(folder: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(folder):
		return out
	for sub in DirAccess.get_directories_at(folder):
		var path := folder.path_join(sub)
		if LevelData.is_level_dir(path):
			out.append(path)
	out.sort()
	return out


## Area folders under res://levels.
static func areas() -> PackedStringArray:
	var out := PackedStringArray()
	for sub in DirAccess.get_directories_at(AREA_ROOT):
		if not levels_in(AREA_ROOT.path_join(sub)).is_empty():
			out.append(sub)
	out.sort()
	return out


## Every playable data level: each area's levels, then user://levels/ (any
## depth of one or two folders).
static func all_data_levels() -> PackedStringArray:
	var out := PackedStringArray()
	for area in areas():
		out.append_array(levels_in(AREA_ROOT.path_join(area)))
	if DirAccess.dir_exists_absolute(USER_ROOT):
		out.append_array(levels_in(USER_ROOT))
		for sub in DirAccess.get_directories_at(USER_ROOT):
			out.append_array(levels_in(USER_ROOT.path_join(sub)))
	return out


## A fresh level node for a map (scene or data level).
static func instantiate(path: String) -> Node:
	path = resolve(path)
	if is_data(path):
		var level := (load(DATA_SCENE) as PackedScene).instantiate()
		level.set("level_path", path)
		level.set("map_id", path)
		return level
	return (load(path) as PackedScene).instantiate()


## Changes the window's level (alone, or the window's level in co-op).
static func change_to(tree: SceneTree, path: String) -> void:
	path = resolve(path)
	if is_data(path):
		tree.change_scene_to_node.call_deferred(instantiate(path))
	else:
		tree.change_scene_to_file.call_deferred(path)


## The map id of a level node: its data folder, else its scene path.
static func id_of(level: Node) -> String:
	if level == null:
		return ""
	var id = level.get("map_id")
	if id is String and id != "":
		return id
	return level.scene_file_path


## A short name for a map, for menus and labels.
static func display_name(path: String) -> String:
	if path == "hub" or path == Session.HUB_SCENE:
		return "Nomad-2"
	if path.begins_with("area:"):
		return path.trim_prefix("area:").capitalize()
	if is_data(path):
		var data := LevelData.load_dir(path)
		return String(data.meta.name) if data else path.get_file()
	return path.get_file().get_basename().capitalize()
