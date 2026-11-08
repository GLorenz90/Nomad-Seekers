class_name Materials
extends RefCounted
## PSO materials: single-use items that permanently raise one stat by 2.
## PSO's seven (Power, Mind, Def, Evade, Luck, HP, TP as LP) plus two new ones
## for stats PSO didn't have: Dex (DEX) and Accuracy (ATA).
##
## Usage limits follow PSO:
## - Stat materials share one limit: humans 250, everyone else 150, each
##   raised by 25 here to make room for Dex and Accuracy (Grayson, 2026-11-08).
## - HP and LP materials have their own limit of 125 each, outside the shared one.
## - Goluman are PSO's androids: no Mind (SOL) or LP materials, like androids
##   had no MST or TP materials.
##
## Used counts live on CharacterData.materials (id -> count); the items
## themselves sit in Inventory.consumables like any other item.

const PER_USE := 2.0
const EXTRA_LIMIT := 25  # Grayson: compensates for Dex and Accuracy materials
const HP_LP_LIMIT := 125

## id -> [display name, Stats property, short stat name, pool]
## pool: &"stat" counts toward the shared limit, &"hp" / &"lp" have their own.
const ALL := {
	&"power_material": ["Power Material", &"strength", "STR", &"stat"],
	&"dex_material": ["Dex Material", &"dexterity", "DEX", &"stat"],
	&"mind_material": ["Mind Material", &"soul", "SOL", &"stat"],
	&"def_material": ["Def Material", &"defense", "DEF", &"stat"],
	&"evade_material": ["Evade Material", &"evasion", "EVA", &"stat"],
	&"accuracy_material": ["Accuracy Material", &"accuracy", "ATA", &"stat"],
	&"luck_material": ["Luck Material", &"luck", "LCK", &"stat"],
	&"hp_material": ["HP Material", &"max_hp", "HP", &"hp"],
	&"lp_material": ["LP Material", &"max_lp", "LP", &"lp"],
}


static func is_material(id: StringName) -> bool:
	return ALL.has(id)


static func display_name(id: StringName) -> String:
	return ALL[id][0] if ALL.has(id) else String(id)


static func stat_of(id: StringName) -> StringName:
	return ALL[id][1]


static func stat_label(id: StringName) -> String:
	return ALL[id][2]


static func pool_of(id: StringName) -> StringName:
	return ALL[id][3]


## The shared stat-material limit for a race: PSO's 250 for humans and 150 for
## everyone else, +25 each.
static func stat_limit(race: CharacterData.Race) -> int:
	return (250 if race == CharacterData.Race.HUMAN else 150) + EXTRA_LIMIT


static func pool_limit(character: CharacterData, pool: StringName) -> int:
	match pool:
		&"hp":
			return HP_LP_LIMIT
		&"lp":
			return 0 if character.race == CharacterData.Race.GOLUMAN else HP_LP_LIMIT
		_:
			return stat_limit(character.race)


## How many of a pool's materials the character has used.
static func pool_used(character: CharacterData, pool: StringName) -> int:
	var total := 0
	for id in character.materials:
		if ALL.has(id) and pool_of(id) == pool:
			total += int(character.materials[id])
	return total


## Why this character can't use the material, or "" if they can.
static func use_error(character: CharacterData, id: StringName) -> String:
	if not ALL.has(id):
		return "That isn't a material"
	if character.race == CharacterData.Race.GOLUMAN and (id == &"mind_material" or id == &"lp_material"):
		return "Goluman can't use %s" % display_name(id)
	var pool := pool_of(id)
	if pool_used(character, pool) >= pool_limit(character, pool):
		return "Material limit reached (%s)" % limit_text(character, pool)
	return ""


static func limit_text(character: CharacterData, pool: StringName) -> String:
	return "%d / %d" % [pool_used(character, pool), pool_limit(character, pool)]


## Stat bonuses from every material used: Stats property -> amount.
static func bonuses(character: CharacterData) -> Dictionary:
	var out := {}
	for id in ALL:
		out[stat_of(id)] = float(character.materials.get(id, 0)) * PER_USE
	return out
