class_name SaveData
extends Resource
## One save file for everything the Seeker keeps between sessions: character,
## loadouts, inventory (and SyncAIDa from Part 6). Saved to user://save.tres
## when the loadout menu closes and when the game window closes.
##
## Loadouts reference weapons inside the inventory, so they must live in the
## same file to stay the same objects after loading.

const SAVE_PATH := "user://save.tres"
## Part 3's loadout-only save, imported once if no save.tres exists yet.
const OLD_LOADOUTS_PATH := "user://loadouts.tres"

@export var character: CharacterData
@export var loadouts: LoadoutSet
@export var inventory: Inventory
## Every SyncAIDa the Seeker owns; `paired` is the one in the field.
@export var syncaida: Array[SyncAIDaData] = []
@export var paired := 0


static func fresh(default_loadouts: LoadoutSet) -> SaveData:
	var s := SaveData.new()
	s.character = CharacterData.new()
	s.loadouts = default_loadouts
	s.inventory = Inventory.new()
	s.inventory.add_consumable(&"hp_gel", 3)
	s.inventory.add_consumable(&"lp_cell", 2)
	s.inventory.add_consumable(&"cure_salt", 1)
	s._add_starters()
	return s


## New Seekers start with two SyncAIDa so pairing can be tried right away.
func _add_starters() -> void:
	syncaida.append(SyncAIDaData.create("Pip"))
	syncaida.append(SyncAIDaData.create("Nyx"))
	paired = 0


func paired_syncaida() -> SyncAIDaData:
	if syncaida.is_empty():
		return null
	return syncaida[clampi(paired, 0, syncaida.size() - 1)]


static func load_or_new(default_loadouts: LoadoutSet) -> SaveData:
	if ResourceLoader.exists(SAVE_PATH):
		var saved := ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as SaveData
		if saved:
			saved._fill_missing(default_loadouts)
			return saved
	var s := fresh(default_loadouts)
	if ResourceLoader.exists(OLD_LOADOUTS_PATH):
		var old := ResourceLoader.load(OLD_LOADOUTS_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as LoadoutSet
		if old:
			old.ensure_slots()
			s.loadouts = old
	return s


func save() -> void:
	ResourceSaver.save(self, SAVE_PATH)


func _fill_missing(default_loadouts: LoadoutSet) -> void:
	if character == null:
		character = CharacterData.new()
	if loadouts == null:
		loadouts = default_loadouts
	if inventory == null:
		inventory = Inventory.new()
	if syncaida.is_empty():
		_add_starters()
	loadouts.ensure_slots()
