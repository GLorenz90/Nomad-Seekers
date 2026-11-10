class_name Inventory
extends Resource
## Everything the Seeker owns (Part 9, PSO-style; Grayson, 2026-11-09):
##
## - The **pack** holds every item and piece of gear: weapons (palette weapons
##   included), armor (worn pieces included), augments, spell discs and stacks
##   of consumables and materials. PACK_SLOTS slots, like PSO's 30; a stack of
##   the same item is one slot and holds up to STACK_MAX.
## - The **satchel** holds Oro and carried Lumidium, so a full satchel never
##   stops you picking up a rare. Carried Lumidium is capped at
##   SATCHEL_LUMIDIUM (SaveData.satchel_size), all colors together. It's kept
##   in the save across maps (SaveData.satchel_lumidium) and lost on death
##   until the Seeker banks it at a Lumidium depot (Grayson, 2026-11-10).
##
## Banked Lumidium (`lumidium`) is the bank, not the pack. Slot counts and
## pickups that need the worn armor go through SaveData (pack_used, take_*).

const PACK_SLOTS := 30
const STACK_MAX := 10
## The satchel's starting size; quests will grow it (SaveData.satchel_size).
const SATCHEL_LUMIDIUM := 15
## The most Lumidium the bank holds, all colors together (Grayson, 2026-11-10).
const BANK_LUMIDIUM_MAX := 99999
const ORO_MAX := 999999
## Debug tab: lift the pack's slot limit (stacks still stop at STACK_MAX).
static var unlimited := false

## Consumable ids -> display names. SyncAIDa eat these too (Part 6).
const CONSUMABLES := {
	&"hp_gel": "HP Gel", &"lp_cell": "LP Cell", &"cure_salt": "Cure Salt",
	&"trap_scanner": "Trap Scanner",
}
## Lumidium colors: one per element plus rare Raw (typeless).
const LUMIDIUM := [&"fire", &"ice", &"lightning", &"nature", &"light", &"dark", &"raw"]
const LUMIDIUM_COLORS := {
	&"fire": Color(1.0, 0.45, 0.15), &"ice": Color(0.55, 0.85, 1.0),
	&"lightning": Color(1.0, 0.95, 0.3), &"nature": Color(0.45, 0.9, 0.35),
	&"light": Color(1.0, 1.0, 0.8), &"dark": Color(0.6, 0.35, 0.95),
	&"raw": Color(0.95, 0.95, 0.95),
}

@export var weapons: Array[WeaponData] = []
@export var consumables: Dictionary = {}  # StringName -> int
@export var oro := 0
@export var lumidium: Dictionary = {}  # StringName -> int (banked)
## Spell / trap discs kept to read later: [{"id": "gifoie", "level": 4}, ...].
@export var discs: Array = []
## Armor not being worn (Part 7), and augments not in a slot (id -> count).
@export var armors: Array[ArmorData] = []
@export var units: Dictionary = {}


func add_unit(id: StringName, count: int = 1) -> void:
	units[id] = int(units.get(id, 0)) + count


func unit_count(id: StringName) -> int:
	return int(units.get(id, 0))


func take_unit(id: StringName) -> bool:
	if unit_count(id) <= 0:
		return false
	units[id] = unit_count(id) - 1
	if units[id] == 0:
		units.erase(id)
	return true


func add_weapon(w: WeaponData) -> void:
	weapons.append(w)


## Adds to a stack without checking room (SaveData.take_stack checks).
func add_consumable(id: StringName, count: int = 1) -> void:
	consumables[id] = int(consumables.get(id, 0)) + count
	if int(consumables[id]) <= 0:
		consumables.erase(id)


## Removes up to `count` from a stack. Returns how many were removed.
func remove_consumable(id: StringName, count: int) -> int:
	var n := mini(count, self.count(id))
	if n > 0:
		add_consumable(id, -n)
	return n


## Adds Oro up to ORO_MAX. Returns how much was taken.
func add_oro(amount: int) -> int:
	var n := clampi(amount, 0, ORO_MAX - oro)
	oro += n
	return n


## Slots used by what's in here. Worn armor isn't in here (it's on the
## character) but still takes slots: SaveData.pack_used adds it.
func pack_items() -> int:
	var n := weapons.size() + armors.size() + discs.size()
	for id in units:
		n += int(units[id])
	for id in consumables:
		if int(consumables[id]) > 0:
			n += 1
	return n


func use_consumable(id: StringName) -> bool:
	var have := int(consumables.get(id, 0))
	if have <= 0:
		return false
	add_consumable(id, -1)
	return true


## Display name for anything kept in `consumables` (consumables and materials).
static func item_name(id: StringName) -> String:
	if CONSUMABLES.has(id):
		return CONSUMABLES[id]
	return Materials.display_name(id)


func count(id: StringName) -> int:
	return int(consumables.get(id, 0))


## Moves carried Lumidium into the bank, up to BANK_LUMIDIUM_MAX in all.
## What fits leaves `carried`; returns how much was banked.
func bank_lumidium(carried: Dictionary) -> int:
	var total := 0
	for color in carried.keys():
		var n := mini(int(carried[color]), BANK_LUMIDIUM_MAX - lumidium_total())
		if n <= 0:
			break
		lumidium[color] = int(lumidium.get(color, 0)) + n
		carried[color] = int(carried[color]) - n
		if int(carried[color]) <= 0:
			carried.erase(color)
		total += n
	return total


func lumidium_total() -> int:
	var total := 0
	for color in lumidium:
		total += int(lumidium[color])
	return total
