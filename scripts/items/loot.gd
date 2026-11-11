class_name Loot
extends RefCounted
## Drop rolls (North Star §5.2, §7.2).
##
## Weapons drop from the Seeker's emblem pool: every emblem favors two weapon
## families (3x as likely) and has its own rare weapons. A dropped weapon can
## roll a special tag (tier weighted low) and a monster-type damage bonus.
## Loot is instanced per player, so in co-op each Seeker rolls their own.

const WEAPON_DIR := "res://data/weapons/"
const RARE_DIR := "res://data/weapons/rare/"

## Two favored weapon families per emblem (index = emblem).
const FAVORED := [
	[&"sword", &"great_sword"],  # Crimson
	[&"axe", &"great_axe"],  # Orange
	[&"mace", &"maul"],  # Gold
	[&"bow", &"crossbow"],  # Green
	[&"spear", &"halberd"],  # Teal
	[&"cane", &"talisman"],  # Cyan
	[&"pistol", &"rifle"],  # Blue
	[&"shotgun", &"hand_shotgun"],  # Purple
	[&"boomerang", &"cards"],  # Magenta
	[&"bladestaff", &"glove"],  # Pink
	[&"wand", &"staff"],  # White
	[&"dagger", &"thrown_daggers"],  # Black
]

const DROP_CHANCE := 0.6
const WEAPON_SHARE := 0.35
const ORO_SHARE := 0.4
## Armor and augments (Part 7) take their share out of Oro. The Blue emblem
## finds armor twice as often (Grayson: one of the blue emblems).
const ARMOR_SHARE := 0.08
const UNIT_SHARE := 0.04
const ARMOR_EMBLEM := 6  # Blue
## Spell discs (Part 6); the rest of the drops are consumables.
const DISC_SHARE := 0.1
## PSO materials (any of the nine, evenly), taken from the consumable share.
const MATERIAL_SHARE := 0.04
const TAG_CHANCE := 0.35
const BONUS_CHANCE := 0.4
const RARE_CHANCE := 0.04


static func base_weapons() -> Array[WeaponData]:
	var list: Array[WeaponData] = []
	for file in DirAccess.get_files_at(WEAPON_DIR):
		file = file.trim_suffix(".remap")
		if file.ends_with(".tres"):
			var w := load(WEAPON_DIR + file) as WeaponData
			if w:
				list.append(w)
	return list


static func rare_weapons() -> Array[WeaponData]:
	var list: Array[WeaponData] = []
	if not DirAccess.dir_exists_absolute(RARE_DIR):
		return list
	for file in DirAccess.get_files_at(RARE_DIR):
		file = file.trim_suffix(".remap")
		if file.ends_with(".tres"):
			var w := load(RARE_DIR + file) as WeaponData
			if w:
				list.append(w)
	return list


## Rares drop for the emblems listed in their `notes`-style metadata: each rare
## names its emblems in `rare_emblems` meta (set by the builder).
static func rares_for(emblem: int) -> Array[WeaponData]:
	var list: Array[WeaponData] = []
	for w in rare_weapons():
		var emblems: Array = w.get_meta("emblems", [])
		if emblems.has(emblem):
			list.append(w)
	return list


## What an enemy leaves behind: {} (nothing), {"oro": n}, {"consumable": id},
## {"material": id}, {"disc": {...}}, {"armor": ArmorData}, {"unit": id} or
## {"weapon": WeaponData}.
static func roll_drop(enemy: EnemyData, emblem: int, rng: RandomNumberGenerator,
		traps := false) -> Dictionary:
	if rng.randf() > DROP_CHANCE:
		return {}
	var r := rng.randf()
	if r < WEAPON_SHARE:
		return {"weapon": roll_weapon(emblem, rng)}
	var armor_share := armor_share_for(emblem)
	if r < WEAPON_SHARE + armor_share:
		return {"armor": ArmorBook.roll_drop(rng)}
	if r < WEAPON_SHARE + armor_share + UNIT_SHARE:
		return {"unit": UnitBook.roll(rng)}
	if r < WEAPON_SHARE + ORO_SHARE:
		return {"oro": int(round(rng.randf_range(10.0, 30.0) * enemy.max_hp / 100.0))}
	if r < WEAPON_SHARE + ORO_SHARE + DISC_SHARE:
		return {"disc": roll_disc(rng, traps)}
	if r < WEAPON_SHARE + ORO_SHARE + DISC_SHARE + MATERIAL_SHARE:
		var mats := Materials.ALL.keys()
		return {"material": mats[rng.randi() % mats.size()]}
	var ids := Inventory.CONSUMABLES.keys()
	return {"consumable": ids[rng.randi() % ids.size()]}


static func armor_share_for(emblem: int) -> float:
	return ARMOR_SHARE * (2.0 if emblem == ARMOR_EMBLEM else 1.0)


## A spell disc (or a trap disc for Goluman): any spell, low levels most often
## (PSO-style; the level will follow area difficulty once there are areas).
static func roll_disc(rng: RandomNumberGenerator, traps := false) -> Dictionary:
	var pool := SpellBook.traps_only() if traps else SpellBook.spells_only()
	var spell: SpellDef = pool[rng.randi() % pool.size()]
	var roll := rng.randf()
	var level := 1
	if roll > 0.95:
		level = rng.randi_range(4, 5)
	elif roll > 0.85:
		level = 3
	elif roll > 0.6:
		level = 2
	return {"id": String(spell.id), "level": mini(level, spell.max_level)}


static func roll_weapon(emblem: int, rng: RandomNumberGenerator) -> WeaponData:
	var rares := rares_for(emblem)
	if not rares.is_empty() and rng.randf() < RARE_CHANCE:
		return (rares[rng.randi() % rares.size()] as WeaponData).duplicate() as WeaponData

	var bases := base_weapons()
	var favored: Array = FAVORED[emblem % FAVORED.size()]
	var weights: Array[float] = []
	var total := 0.0
	for w in bases:
		var weight := 3.0 if favored.has(w.weapon_type) else 1.0
		weights.append(weight)
		total += weight
	var pick := rng.randf() * total
	var base: WeaponData = bases[0]
	for i in bases.size():
		pick -= weights[i]
		if pick <= 0.0:
			base = bases[i]
			break
	return make_item(base, rng)


## A found copy of a base weapon, maybe with a tag and a monster-type bonus.
static func make_item(base: WeaponData, rng: RandomNumberGenerator) -> WeaponData:
	var w := base.duplicate() as WeaponData
	w.base_name = base.display_name
	w.type_bonus = {}
	if not base.casting and not base.is_shield and rng.randf() < TAG_CHANCE:
		var lines := SpecialTag.all_lines()
		var line: SpecialTag = lines[rng.randi() % lines.size()]
		apply_tag(w, line, roll_tier(line.tier_count(), rng))
	if rng.randf() < BONUS_CHANCE:
		var types := EnemyData.EnemyType.values()
		var type: int = types[rng.randi() % types.size()]
		w.type_bonus[type] = snappedf(rng.randf_range(0.05, 0.3), 0.05)
	return w


## Lower tiers are more common: weights 8, 4, 2, 1.
static func roll_tier(tiers: int, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for t in tiers:
		total += 8.0 / pow(2.0, t)
	var roll := rng.randf() * total
	for t in tiers:
		roll -= 8.0 / pow(2.0, t)
		if roll <= 0.0:
			return t
	return tiers - 1


static func apply_tag(w: WeaponData, line: SpecialTag, tier: int) -> void:
	w.tag = line
	w.tag_tier = clampi(tier, 0, line.tier_count() - 1)
	if line.sets_weapon_element():
		w.damage_type = line.element
	if not w.rare:
		w.display_name = "%s %s" % [line.name_for(w.tag_tier), w.base_name if w.base_name != "" else w.display_name]


## "Flame Sword  [Burning: Fire damage...]  +15% vs Beast"
static func describe(w: WeaponData) -> String:
	var parts := PackedStringArray()
	if w.tag:
		parts.append("RT: " + w.tag.describe(w.tag_tier))
	for type in w.type_bonus:
		parts.append("+%d%% vs %s" % [roundi(float(w.type_bonus[type]) * 100.0),
			String(EnemyData.EnemyType.keys()[type]).capitalize()])
	return "  ".join(parts)
