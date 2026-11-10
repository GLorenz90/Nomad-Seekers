class_name Prices
extends RefCounted
## Shop prices and stock (Part 10, Grayson 2026-11-09: "use PSO for a monetary
## base"). 1 Oro = 1 Meseta.
##
## - Curatives use PSO's own tool-shop prices for the matching item: HP Gel =
##   Monomate 50, LP Cell = Monofluid 100, Cure Salt = Sol Atomizer 300 (cures
##   everything), Trap Scanner = Trap Vision 100.
## - Weapons and armor are PSO-shaped (common gear in the hundreds to low
##   thousands), from the item's own numbers; PSO's exact shop formula isn't
##   used. First pass.
## - Shops buy anything back for SELL_RATE of its price (Claude's pick).
## - Stock is rolled each time you arrive in Nomad-2 (PSO rolls the arms
##   shop each time you enter Pioneer 2), and every listing can be bought
##   again and again, like PSO.

const SELL_RATE := 0.125  # 1/8

## Curatives shop: id -> price.
const CURATIVES := {
	&"hp_gel": 50,
	&"lp_cell": 100,
	&"cure_salt": 300,
	&"trap_scanner": 100,
}
## Materials aren't sold in shops; this is what a shop pays for one.
const MATERIAL_SELL := 100
## Spell discs sell for this per level (what an unwanted disc was already
## sold for on pickup, Part 6).
const DISC_SELL_PER_LEVEL := 20

const WEAPON_STOCK := 10
const ARMOR_STOCK := 8
const UNIT_STOCK := 4


# --- Weapons -----------------------------------------------------------------------

## Base weapons: 200 + 25 per point of base damage (Pistol 500, Sword 700,
## Great Sword 1050), x1.3 for two-handed. A special tag adds 50% per tier,
## a monster-type bonus 30 Oro per percent. Rares are worth 10x.
static func weapon_price(w: WeaponData) -> int:
	var price := 200.0 + 25.0 * w.base_damage
	if w.two_handed:
		price *= 1.3
	if w.tag:
		price *= 1.5 + 0.5 * w.tag_tier
	for type in w.type_bonus:
		price += 3000.0 * float(w.type_bonus[type])
	if w.rare:
		price *= 10.0
	return _round(price)


# --- Armor and augments -----------------------------------------------------------------

## Torso: 300 x tier², Heavy +20%; Head and Legs 40%. +15% per slot, and 40
## Oro per point of DEF / EVA bonus. Rares are worth 10x.
static func armor_price(a: ArmorData) -> int:
	var price := 300.0 * a.tier * a.tier
	if a.weight == ArmorData.Weight.HEAVY:
		price *= 1.2
	if a.slot != ArmorData.Slot.TORSO:
		price *= 0.4
	price *= 1.0 + 0.15 * a.slots
	price += 40.0 * (a.def_bonus + a.eva_bonus)
	if a.rare:
		price *= 10.0
	return _round(price)


## Grade I 1,000, II 3,000, III 8,000; Double-Heavy 20,000.
static func unit_price(id: StringName) -> int:
	var u := UnitBook.get_unit(id)
	if u.is_empty():
		return 0
	if u.kind == "special":
		return 20000
	return [1000, 3000, 8000][int(u.grade)]


# --- Selling -------------------------------------------------------------------------

## What a shop pays for one of a stackable item.
static func stack_sell(id: StringName) -> int:
	if CURATIVES.has(id):
		return maxi(_floor(CURATIVES[id] * SELL_RATE), 1)
	if Materials.ALL.has(id):
		return MATERIAL_SELL
	return 1


## What a shop pays for a pack entry (InventoryTab.entries() format).
static func sell_price(entry: Dictionary, save: SaveData) -> int:
	match entry.kind:
		"weapon":
			return maxi(_floor(weapon_price(entry.weapon) * SELL_RATE), 1)
		"armor":
			return maxi(_floor(armor_price(entry.armor) * SELL_RATE), 1)
		"unit":
			return maxi(_floor(unit_price(entry.unit) * SELL_RATE), 1)
		"disc":
			return DISC_SELL_PER_LEVEL * int(save.inventory.discs[entry.index].level)
		"stack":
			return stack_sell(entry.id)
	return 0


# --- Stock ------------------------------------------------------------------------------

## Part 11: shop tiers go up with the character's level (Grayson).
## Weapons: the best tag tier on offer is 0 below level 50, then +1 per 50
## levels; monster bonuses grow too. Armor: tiers whose level requirement is
## within 5 levels of yours. Augments: grade II from level 40, III from 100.
## (Claude's steps.)
static func max_tag_tier(level: int) -> int:
	return clampi(level / 50, 0, 3)


static func max_unit_grade(level: int) -> int:
	return 2 if level >= 100 else (1 if level >= 40 else 0)


static func max_armor_tier(level: int) -> int:
	var tier := 1
	for t in ArmorData.TIER_LEVELS.size():
		if ArmorData.TIER_LEVELS[t] <= level + 5:
			tier = t + 1
	return tier


## The weapons shop: common weapons, some tagged or with a monster bonus
## (tiers by level). Never rares.
static func roll_weapon_stock(rng: RandomNumberGenerator, level: int = 1) -> Array[WeaponData]:
	var stock: Array[WeaponData] = []
	var bases := Loot.base_weapons()
	for i in WEAPON_STOCK:
		var base: WeaponData = bases[rng.randi() % bases.size()]
		var w := base.duplicate() as WeaponData
		w.base_name = base.display_name
		w.type_bonus = {}
		if not base.casting and not base.is_shield and rng.randf() < 0.35:
			var lines := SpecialTag.all_lines()
			var line: SpecialTag = lines[rng.randi() % lines.size()]
			Loot.apply_tag(w, line, rng.randi_range(0, mini(max_tag_tier(level) + 1, line.tier_count() - 1)))
		if rng.randf() < 0.2:
			var types := EnemyData.EnemyType.values()
			var top := 0.15 + 0.05 * max_tag_tier(level)
			w.type_bonus[types[rng.randi() % types.size()]] = snappedf(rng.randf_range(0.05, top), 0.05)
		stock.append(w)
	stock.sort_custom(func(a: WeaponData, b: WeaponData) -> bool: return a.display_name < b.display_name)
	return stock


## The armor shop: pieces up to the tier for your level, rolled like drops,
## never rares.
static func roll_armor_stock(rng: RandomNumberGenerator, level: int = 1) -> Array[ArmorData]:
	var ids: Array = []
	var top := max_armor_tier(level)
	for id in ArmorBook.all():
		var t := ArmorBook.template(id)
		if not t.rare and t.tier <= top and t.tier >= top - 1:
			ids.append(id)
	var stock: Array[ArmorData] = []
	for i in ARMOR_STOCK:
		stock.append(ArmorBook.roll(ids[rng.randi() % ids.size()], rng))
	stock.sort_custom(func(a: ArmorData, b: ArmorData) -> bool:
		return a.slot < b.slot or (a.slot == b.slot and a.display_name < b.display_name))
	return stock


## Stat augments and element wards up to the grade for your level.
static func roll_unit_stock(rng: RandomNumberGenerator, level: int = 1) -> Array[StringName]:
	var pool: Array[StringName] = []
	var top := max_unit_grade(level)
	for id in UnitBook.ids():
		var u := UnitBook.get_unit(id)
		if int(u.grade) <= top and (u.kind == "stat" or u.kind == "element"):
			pool.append(id)
	var stock: Array[StringName] = []
	while stock.size() < UNIT_STOCK and stock.size() < pool.size():
		var id: StringName = pool[rng.randi() % pool.size()]
		if not id in stock:
			stock.append(id)
	stock.sort()
	return stock


static func _round(price: float) -> int:
	return maxi(roundi(price / 10.0) * 10, 10)


static func _floor(price: float) -> int:
	return floori(price)
