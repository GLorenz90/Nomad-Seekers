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
## The bank (Part 10, PSO's Check Room): BANK_SLOTS items and up to
## BANK_ORO_MAX Oro (bank.oro). Banked Lumidium stays in inventory.lumidium.
@export var bank: Inventory
## The Guild quest in progress: {"id": String, "progress": int}, or {}.
@export var quest: Dictionary = {}
## Quest id -> times completed.
@export var quests_cleared: Dictionary = {}
## The d-pad item palette (Grayson, 2026-11-09): 8 slots. 0-3 are d-pad left
## / up / right / down, 4-7 the same with RT held. Each holds a consumable id
## or, for Goluman, a trap's id; &"" is empty. See quick() / set_quick().
@export var quick_slots: Array[StringName] = []
## Lumidium carried in the satchel (color -> count), kept across maps (Grayson,
## 2026-11-10); lost on death, banked at a Lumidium depot.
@export var satchel_lumidium: Dictionary = {}
## How much Lumidium the satchel holds, all colors together. 15 to start;
## quests will raise it later (Grayson).
@export var satchel_size := Inventory.SATCHEL_LUMIDIUM

## PSO's bank: 200 items and up to 999,999,999 Meseta (Ephinea's numbers).
const BANK_SLOTS := 200
const BANK_ORO_MAX := 999999999
## A bank stack holds up to this many of one item (Claude's pick).
const BANK_STACK := 99


static func fresh(default_loadouts: LoadoutSet) -> SaveData:
	var s := SaveData.new()
	s.character = CharacterData.new()
	s.loadouts = default_loadouts
	s.inventory = Inventory.new()
	s.bank = Inventory.new()
	s.inventory.add_consumable(&"hp_gel", 3)
	s.inventory.add_consumable(&"lp_cell", 2)
	s.inventory.add_consumable(&"cure_salt", 1)
	s.inventory.add_consumable(&"trap_scanner", 2)
	# First spells (Part 6): level 1 Fajro, Glacio and Fulmo (SOL 40 each).
	for id in STARTING_SPELLS:
		s.character.spells[id] = 1
	s.give_starter_armor()
	s.pack_palette_weapons()
	s.ensure_quick_slots()
	return s


# --- D-pad palette ------------------------------------------------------------------

const QUICK_SLOTS := 8
## What the d-pad held before it became a palette (left, up, right, down).
const DEFAULT_QUICK: Array[StringName] = [&"hp_gel", &"lp_cell", &"cure_salt", &"trap_scanner"]
## Slot names, in slot order.
const QUICK_NAMES: Array[String] = ["Left", "Up", "Right", "Down",
	"RT + Left", "RT + Up", "RT + Right", "RT + Down"]


func ensure_quick_slots() -> void:
	if quick_slots.is_empty():
		quick_slots.assign(DEFAULT_QUICK)
	while quick_slots.size() < QUICK_SLOTS:
		quick_slots.append(&"")


func quick(index: int) -> StringName:
	ensure_quick_slots()
	return quick_slots[index] if index >= 0 and index < QUICK_SLOTS else &""


## Puts an item or trap in a d-pad slot (&"" empties it). Anything already in
## another slot moves here, so each item sits in one slot.
func set_quick(index: int, id: StringName) -> void:
	ensure_quick_slots()
	if index < 0 or index >= QUICK_SLOTS:
		return
	if id != &"":
		for i in QUICK_SLOTS:
			if quick_slots[i] == id:
				quick_slots[i] = &""
	quick_slots[index] = id


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
	if bank == null:
		bank = Inventory.new()
	loadouts.ensure_slots()
	give_starter_armor()
	pack_palette_weapons()
	ensure_quick_slots()



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


## Every pack slot, in PSO-ish order: weapons, worn then spare armor,
## augments, discs, stacks. Each: {"kind": ..., plus what it refers to}.
func pack_entries() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var inv := inventory
	for w in inv.weapons:
		list.append({"kind": "weapon", "weapon": w})
	for a in ArmorBook.equipped(character):
		list.append({"kind": "armor", "armor": a, "worn": true})
	for a in inv.armors:
		list.append({"kind": "armor", "armor": a, "worn": false})
	var unit_ids := inv.units.keys()
	unit_ids.sort()
	for id in unit_ids:
		for i in inv.unit_count(id):
			list.append({"kind": "unit", "unit": id})
	for i in inv.discs.size():
		list.append({"kind": "disc", "index": i})
	for id in Inventory.CONSUMABLES.keys() + Materials.ALL.keys():
		if inv.count(id) > 0:
			list.append({"kind": "stack", "id": id})
	# Anything else stacked (older saves): keep it visible so it can be dropped.
	for id in inv.consumables:
		if inv.count(id) > 0 and not Inventory.CONSUMABLES.has(id) and not Materials.ALL.has(id):
			list.append({"kind": "stack", "id": id})
	return list


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


# --- The bank (Part 10) ------------------------------------------------------------

func bank_used() -> int:
	return bank.pack_items()


func bank_free() -> int:
	return maxi(BANK_SLOTS - bank_used(), 0)


## Puts `count` of a pack entry (InventoryTab.entries() format) in the bank.
## Returns "" or why not.
func deposit(entry: Dictionary, count: int = 1) -> String:
	match entry.kind:
		"weapon":
			var w: WeaponData = entry.weapon
			if not palettes_with(w).is_empty():
				return "%s is on a palette: take it off first." % w.display_name
			if bank_free() <= 0:
				return "The bank is full."
			inventory.weapons.erase(w)
			bank.weapons.append(w)
		"armor":
			if entry.get("worn", false):
				return "You're wearing it: take it off first."
			if bank_free() <= 0:
				return "The bank is full."
			inventory.armors.erase(entry.armor)
			bank.armors.append(entry.armor)
		"unit":
			if bank_free() <= 0:
				return "The bank is full."
			inventory.take_unit(entry.unit)
			bank.add_unit(entry.unit)
		"disc":
			if bank_free() <= 0:
				return "The bank is full."
			bank.discs.append(inventory.discs[entry.index])
			inventory.discs.remove_at(entry.index)
		"stack":
			var id: StringName = entry.id
			var room := BANK_STACK - bank.count(id) if bank.count(id) > 0 else (BANK_STACK if bank_free() > 0 else 0)
			var n := mini(mini(count, inventory.count(id)), room)
			if n <= 0:
				return "The bank can't hold more %s." % Inventory.item_name(id)
			inventory.remove_consumable(id, n)
			bank.add_consumable(id, n)
	return ""


## Takes `count` of a bank entry (bank_entries() format) into the pack.
## Returns "" or why not.
func withdraw(entry: Dictionary, count: int = 1) -> String:
	match entry.kind:
		"weapon":
			if not take_weapon(entry.weapon):
				return "Your pack is full."
			bank.weapons.erase(entry.weapon)
		"armor":
			if not take_armor(entry.armor):
				return "Your pack is full."
			bank.armors.erase(entry.armor)
		"unit":
			if not take_unit(entry.unit):
				return "Your pack is full."
			bank.take_unit(entry.unit)
		"disc":
			var d: Dictionary = bank.discs[entry.index]
			if not take_disc(d):
				return "Your pack is full."
			bank.discs.remove_at(entry.index)
		"stack":
			var id: StringName = entry.id
			var n := take_stack(id, mini(count, bank.count(id)))
			if n <= 0:
				return "No room for %s (%d per stack)." % [Inventory.item_name(id), Inventory.STACK_MAX]
			bank.remove_consumable(id, n)
	return ""


## The bank's items, in the pack's order.
func bank_entries() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for w in bank.weapons:
		list.append({"kind": "weapon", "weapon": w})
	for a in bank.armors:
		list.append({"kind": "armor", "armor": a, "worn": false})
	var unit_ids := bank.units.keys()
	unit_ids.sort()
	for id in unit_ids:
		for i in bank.unit_count(id):
			list.append({"kind": "unit", "unit": id})
	for i in bank.discs.size():
		list.append({"kind": "disc", "index": i})
	var ids := bank.consumables.keys()
	ids.sort()
	for id in ids:
		if bank.count(id) > 0:
			list.append({"kind": "stack", "id": id})
	return list


## Oro between the satchel and the bank. Return how much moved.
func deposit_oro(amount: int) -> int:
	var n := clampi(amount, 0, mini(inventory.oro, BANK_ORO_MAX - bank.oro))
	inventory.oro -= n
	bank.oro += n
	return n


## Bank Resources (Grayson, 2026-11-10): Lumidium from the bank into the
## satchel, to trade. Returns how many moved (up to the satchel's room).
func withdraw_lumidium(color: StringName, amount: int) -> int:
	var room := satchel_size - satchel_total()
	var n := clampi(amount, 0, mini(int(inventory.lumidium.get(color, 0)), room))
	if n <= 0:
		return 0
	inventory.lumidium[color] = int(inventory.lumidium[color]) - n
	if int(inventory.lumidium[color]) <= 0:
		inventory.lumidium.erase(color)
	satchel_lumidium[color] = int(satchel_lumidium.get(color, 0)) + n
	return n


## Satchel Lumidium into the bank (one color). Returns how many moved.
func deposit_lumidium(color: StringName, amount: int) -> int:
	var one := {color: mini(amount, int(satchel_lumidium.get(color, 0)))}
	var n := inventory.bank_lumidium(one)
	satchel_lumidium[color] = int(satchel_lumidium.get(color, 0)) - n
	if int(satchel_lumidium[color]) <= 0:
		satchel_lumidium.erase(color)
	return n


func satchel_total() -> int:
	var total := 0
	for color in satchel_lumidium:
		total += int(satchel_lumidium[color])
	return total


func withdraw_oro(amount: int) -> int:
	var n := clampi(amount, 0, mini(bank.oro, Inventory.ORO_MAX - inventory.oro))
	bank.oro -= n
	inventory.oro += n
	return n
