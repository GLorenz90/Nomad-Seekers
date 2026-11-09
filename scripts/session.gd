class_name Session
extends RefCounted
## Session (Part 8): which character is being played, and the
## character slots on disk. Like PSO, there are 4 slots; each is a whole
## SaveData (character, loadouts, inventory, SyncAIDa) in its own file.
##
## The title screen picks or creates a character and calls play(); levels then
## use Session.save, so the same SaveData carries across scene changes. A level
## started straight from the editor (F6) still works: current_save() loads the
## last played slot, or the Part 5-7 single save, or starts fresh.

const SLOT_COUNT := 4
const TITLE_SCENE := "res://scenes/title.tscn"
const HUB_SCENE := "res://scenes/hub.tscn"

## Where slot files live, the Part 5-7 single save, and the file that
## remembers the last slot played. Tests point these somewhere else.
static var slot_dir := "user://characters/"
static var legacy_save := "user://save.tres"
static var settings_path := "user://session.cfg"
## The slot being played (-1 = none yet).
static var slot := -1
static var save: SaveData


static func slot_path(index: int) -> String:
	return slot_dir.path_join("slot_%d.tres" % (index + 1))


static func has_slot(index: int) -> bool:
	return ResourceLoader.exists(slot_path(index))


## The saved character in a slot, or null if empty.
static func load_slot(index: int) -> SaveData:
	if not has_slot(index):
		return null
	var data := ResourceLoader.load(slot_path(index), "", ResourceLoader.CACHE_MODE_IGNORE) as SaveData
	if data:
		data._fill_missing(CombatController.make_default_loadouts())
		data.save_path = slot_path(index)
	return data


static func write_slot(index: int, data: SaveData) -> Error:
	DirAccess.make_dir_recursive_absolute(slot_dir)
	data.save_path = slot_path(index)
	return ResourceSaver.save(data, data.save_path)


static func delete_slot(index: int) -> void:
	if has_slot(index):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(index)))
	if slot == index:
		slot = -1
		save = null
	if last_slot() == index:
		_set_last(-1)


static func first_empty_slot() -> int:
	for i in SLOT_COUNT:
		if not has_slot(i):
			return i
	return -1


## The single save from Parts 5-7 becomes slot 1 the first time the title
## screen runs, so nobody loses their character.
static func migrate_legacy() -> bool:
	if not ResourceLoader.exists(legacy_save) or has_slot(0):
		return false
	var old := ResourceLoader.load(legacy_save, "", ResourceLoader.CACHE_MODE_IGNORE) as SaveData
	if old == null:
		return false
	old._fill_missing(CombatController.make_default_loadouts())
	write_slot(0, old)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(legacy_save),
		ProjectSettings.globalize_path(legacy_save + ".migrated"))
	return true


## Makes a slot the one being played and saves which it was (for Continue).
static func use_slot(index: int, data: SaveData) -> void:
	slot = index
	save = data
	_set_last(index)


## Loads a slot and goes to Nomad-2.
static func play(index: int) -> bool:
	var data := load_slot(index)
	if data == null:
		return false
	use_slot(index, data)
	_tree().change_scene_to_file.call_deferred(HUB_SCENE)
	return true


## Saves the current character and goes back to the title screen.
static func quit_to_title() -> void:
	for p in _tree().get_nodes_in_group("player"):
		(p as Player).save_game()
	_tree().paused = false
	_tree().change_scene_to_file.call_deferred(TITLE_SCENE)


## The save levels should use: the session's, else the last played slot, else
## the legacy single save, else a fresh character (not written until saved).
static func current_save(default_loadouts: LoadoutSet) -> SaveData:
	if save:
		return save
	var last := last_slot()
	if last >= 0 and has_slot(last):
		use_slot(last, load_slot(last))
		return save
	return SaveData.load_or_new(default_loadouts)


static func last_slot() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return -1
	return int(cfg.get_value("session", "last_slot", -1))


static func _set_last(index: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)
	cfg.set_value("session", "last_slot", index)
	cfg.save(settings_path)


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree
