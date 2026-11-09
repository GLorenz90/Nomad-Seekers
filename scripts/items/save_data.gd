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
	s.inventory.add_consumable(&"trap_scanner", 2)
	# First spells (Part 6): level 1 Fajro, Glacio and Fulmo (SOL 40 each).
	for id in STARTING_SPELLS:
		s.character.spells[id] = 1
	s.give_starter_armor()
	return s


## Every Seeker starts in a Field Frame with one augment slot (PSO's Frame).
func give_starter_armor() -> void:
	if character.armor_granted:
		return
	character.armor_granted = true
	if character.torso == null:
		var frame := ArmorBook.make(ArmorBook.STARTER)
		frame.slots = 1
		frame.ensure_units()
		character.torso = frame


const STARTING_SPELLS: Array[StringName] = [&"fajro", &"glacio", &"fulmo"]
const STARTER_WEAPONS: Array[String] = ["sword", "pistol", "wand"]


## Character creation (Part 8): a new Seeker with the choices made on the
## creation screen, their starter SyncAIDa paired, and the starter armor.
static func create(seeker_name: String, race: CharacterData.Race, gender: CharacterData.Gender,
		job: CharacterData.Job, starter: int) -> SaveData:
	var s := fresh(CombatController.make_starter_loadouts())
	# Starter kit: a Sword, a Pistol and a Wand to carry (the palette only
	# uses the Pistol and Sword).
	for id in STARTER_WEAPONS:
		s.inventory.weapons.append(CombatController.load_weapon(id).duplicate())
	s.character.seeker_name = seeker_name.strip_edges() if seeker_name.strip_edges() != "" else "Seeker"
	s.character.race = race
	s.character.gender = gender
	s.character.job = job
	s.choose_starter(starter)
	return s


## Gives the Seeker their starting SyncAIDa (SyncAIDaData.STARTERS index).
## Until one is chosen, they have none; the menu's SyncAIDa tab offers the four.
func choose_starter(index: int) -> SyncAIDaData:
	var s := SyncAIDaData.starter(index)
	syncaida.append(s)
	paired = syncaida.size() - 1
	return s


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


## Where save() writes: a character slot (Session) or, before Part 8, the
## single save file.
var save_path := SAVE_PATH


func save() -> void:
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	ResourceSaver.save(self, save_path)


func _fill_missing(default_loadouts: LoadoutSet) -> void:
	if character == null:
		character = CharacterData.new()
	if loadouts == null:
		loadouts = default_loadouts
	if inventory == null:
		inventory = Inventory.new()
	loadouts.ensure_slots()
	give_starter_armor()
