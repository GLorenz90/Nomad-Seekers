class_name ArmorData
extends Resource
## One piece of armor (Part 7): a Head, Torso or Legs piece, Light or Heavy,
## like PSO's frames and barriers (Head and Legs take the barrier's place).
##
## A template comes from ArmorBook; a dropped piece is a duplicate with its
## own rolls (DEF / EVA bonus and, for non-rares, how many augment slots it
## has). Augments sit in `units`, one entry per slot (&"" = empty), and stay
## in the piece when it's unequipped, like PSO units in a frame.

enum Slot { HEAD, TORSO, LEGS }
enum Weight { LIGHT, HEAVY }

const SLOT_NAMES := ["Head", "Torso", "Legs"]

@export var id: StringName = &""
@export var display_name := ""
@export var slot: Slot = Slot.TORSO
@export var weight: Weight = Weight.LIGHT
@export var tier := 1
@export var defense := 0.0
@export var evasion := 0.0
@export var resolve := 0.0
## Rolled on drop, PSO-style: 0..max added to DEF and EVA.
@export var max_def_bonus := 0
@export var max_eva_bonus := 0
@export var def_bonus := 0
@export var eva_bonus := 0
## Element.Type (int) -> fraction of that element's damage resisted.
@export var resists: Dictionary = {}
## "" = any job (Invokers are still limited to Light); otherwise e.g. "S".
@export var jobs := ""
## Rare restrictions, like PSO's "Casts only" / "Females only" armor.
@export var rare := false
@export var race_only := -1  # CharacterData.Race, -1 = any
@export var gender_only := -1  # CharacterData.Gender, -1 = any
## Built-in stat bonuses on rares: Stats property -> amount.
@export var bonuses: Dictionary = {}
## Augment slots: the most this piece can roll (Torso 4, Head / Legs 1; rares
## may break that), and the rolled count.
@export var max_slots := 0
@export var slots := 0
@export var units: Array[StringName] = []


func slot_name() -> String:
	return SLOT_NAMES[slot]


func weight_name() -> String:
	return "Heavy" if weight == Weight.HEAVY else "Light"


func total_defense() -> float:
	return defense + def_bonus


func total_evasion() -> float:
	return evasion + eva_bonus


## Makes `units` match `slots` (empty slots are &"").
func ensure_units() -> void:
	while units.size() < slots:
		units.append(&"")
	while units.size() > slots:
		units.pop_back()


## Stat bonuses from this piece: its own DEF / EVA / RES, rare bonuses, and
## every augment in it. Stats property -> amount.
func stat_bonuses() -> Dictionary:
	var out := {&"defense": total_defense(), &"evasion": total_evasion(), &"resolve": resolve}
	for stat in bonuses:
		out[stat] = float(out.get(stat, 0.0)) + float(bonuses[stat])
	for u in units:
		var unit := UnitBook.get_unit(u)
		if unit and unit.has("stat"):
			out[unit.stat] = float(out.get(unit.stat, 0.0)) + float(unit.amount)
	return out


## Element resistance from this piece and its augments (fraction).
func resist(element: int) -> float:
	var total := float(resists.get(element, 0.0))
	for u in units:
		var unit := UnitBook.get_unit(u)
		if unit and unit.has("element") and int(unit.element) == element:
			total += float(unit.amount)
	return total


## Resistance against one monster type, from augments (fraction).
func monster_resist(enemy_type: int) -> float:
	var total := 0.0
	for u in units:
		var unit := UnitBook.get_unit(u)
		if unit and unit.has("monster") and int(unit.monster) == enemy_type:
			total += float(unit.amount)
	return total


## Overrides the level requirement when above 0 (rares).
@export var required_level := 0
## Level needed by tier (Part 11, Grayson: "armor should have level
## requirements"; Claude's levels, first pass).
const TIER_LEVELS := [1, 25, 60, 100]


func level_req() -> int:
	if required_level > 0:
		return required_level
	return TIER_LEVELS[clampi(tier, 1, TIER_LEVELS.size()) - 1]


func has_double_heavy() -> bool:
	return UnitBook.DOUBLE_HEAVY in units


## "Torso · Light · DEF 9 EVA 11 RES 8 · 2 slots" and the like.
func summary() -> String:
	var parts := PackedStringArray([slot_name(), weight_name(), "Lv %d" % level_req(),
		"DEF %d  EVA %d%s" % [roundi(total_defense()), roundi(total_evasion()),
			"  RES %d" % roundi(resolve) if resolve > 0.0 else ""]])
	for stat in bonuses:
		parts.append("%s +%d" % [UnitBook.stat_label(stat), roundi(float(bonuses[stat]))])
	for element in resists:
		parts.append("%s res %d%%" % [Element.Type.keys()[element].capitalize(), roundi(float(resists[element]) * 100.0)])
	parts.append("%d slot%s" % [slots, "" if slots == 1 else "s"])
	if jobs != "":
		parts.append("jobs " + jobs)
	if race_only >= 0:
		parts.append(CharacterData.Race.keys()[race_only].capitalize() + " only")
	if gender_only >= 0:
		parts.append(CharacterData.Gender.keys()[gender_only].capitalize() + " only")
	return "  ·  ".join(parts)
