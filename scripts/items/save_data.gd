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
	s.pack_palette_weapons()
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
	var empty := LoadoutSet.new()
	empty.ensure_slots()
	var s := fresh(empty)
	# Starter kit: a Sword, a Pistol and a Wand in the pack. Palette 1 holds
	# the pack's own Pistol (X) and Sword (Y); the Wand waits in the pack.
	var kit := {}
	for id in STARTER_WEAPONS:
		kit[id] = CombatController.load_weapon(id).duplicate()
		s.inventory.weapons.append(kit[id])
	s.loadouts.loadouts[0] = Loadout.make(kit["pistol"], kit["sword"])
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
	pack_palette_weapons()



# --- The pack (Part 9) -------------------------------------------------------------

## Slots in use: everything in the inventory plus the worn armor pieces.
func pack_used() -> int:
	return inventory.pack_items() + ArmorBook.equipped(character).size()


## Free slots (effectively unlimited with the Debug tab's switch on).
func pack_free() -> int:
	if Inventory.unlimited:
		return 9999
	return maxi(Inventory.PACK_SLOTS - pack_used(), 0)


## How many more of a stackable item (consumable or material) fit: the rest
## of its stack, or a new stack if a slot is free.
func stack_room(id: StringName) -> int:
	var have := inventory.count(id)
	if have > 0:
		return maxi(Inventory.STACK_MAX - have, 0)
	return Inventory.STACK_MAX if pack_free() > 0 else 0


## Adds up to `count` to a stack; returns how many fit (PSO: the rest stays
## on the ground).
func take_stack(id: StringName, count: int) -> int:
	var n := mini(count, stack_room(id))
	if n > 0:
		inventory.add_consumable(id, n)
	return n


## Puts one non-stacking item in the pack. Returns false when it's full.
func take_weapon(w: WeaponData) -> bool:
	if pack_free() <= 0:
		return false
	inventory.add_weapon(w)
	return true


func take_armor(a: ArmorData) -> bool:
	if pack_free() <= 0:
		return false
	inventory.armors.append(a)
	return true


func take_unit(id: StringName) -> bool:
	if pack_free() <= 0:
		return false
	inventory.add_unit(id)
	return true


func take_disc(disc: Dictionary) -> bool:
	if pack_free() <= 0:
		return false
	inventory.discs.append({"id": String(disc.id), "level": int(disc.level)})
	return true


## Palettes (PSU-style loadouts) hold weapons from the pack. Older saves and
## tests could hold weapons that never went in it: those are added now.
func pack_palette_weapons() -> void:
	if loadouts == null:
		return
	for l in loadouts.loadouts:
		for w in [l.primary, l.off_hand]:
			if w and not inventory.weapons.has(w):
				inventory.weapons.append(w)


## Palette numbers (1-based) holding this weapon.
func palettes_with(w: WeaponData) -> PackedInt32Array:
	var found := PackedInt32Array()
	for i in loadouts.loadouts.size():
		var l := loadouts.loadouts[i]
		if l.primary == w or l.off_hand == w:
			found.append(i + 1)
	return found


## Takes a weapon off every palette it's on.
func unequip_weapon(w: WeaponData) -> void:
	for l in loadouts.loadouts:
		if l.primary == w:
			l.primary = null
		if l.off_hand == w:
			l.off_hand = null
