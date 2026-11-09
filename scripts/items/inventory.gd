class_name Inventory
extends Resource
## Everything the Seeker owns: found weapons, consumables, Oro and banked
## Lumidium. Carried (not yet deposited) Lumidium lives on the Player and is
## lost on death.

## Consumable ids -> display names. SyncAIDa eat these too (Part 6).
const CONSUMABLES := {
	&"hp_gel": "HP Gel", &"lp_cell": "LP Cell", &"cure_salt": "Cure Salt",
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


func add_weapon(w: WeaponData) -> void:
	weapons.append(w)


func add_consumable(id: StringName, count: int = 1) -> void:
	consumables[id] = int(consumables.get(id, 0)) + count


func use_consumable(id: StringName) -> bool:
	var have := int(consumables.get(id, 0))
	if have <= 0:
		return false
	consumables[id] = have - 1
	return true


## Display name for anything kept in `consumables` (consumables and materials).
static func item_name(id: StringName) -> String:
	if CONSUMABLES.has(id):
		return CONSUMABLES[id]
	return Materials.display_name(id)


func count(id: StringName) -> int:
	return int(consumables.get(id, 0))


func bank_lumidium(carried: Dictionary) -> int:
	var total := 0
	for color in carried:
		lumidium[color] = int(lumidium.get(color, 0)) + int(carried[color])
		total += int(carried[color])
	return total


func lumidium_total() -> int:
	var total := 0
	for color in lumidium:
		total += int(lumidium[color])
	return total
