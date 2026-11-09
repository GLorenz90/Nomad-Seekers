class_name ArmorBook
extends RefCounted
## Armor (Part 7, Grayson 2026-11-08): PSO's frames and barriers as Head,
## Torso and Legs pieces, each Light or Heavy. One set per character.
##
## Rules:
## - Invokers wear Light pieces only; Strikers and Rangers wear either.
## - Some sets are job-locked (Core: Ranger, Titan: Striker, Aether: Invoker).
## - Rares may lock to a race or gender, carry built-in bonuses, and break the
##   slot rule (a Head or Legs piece with 2 augment slots).
## - Drops roll a DEF / EVA bonus and, for non-rares, the number of augment
##   slots: Torso 0-4, Head and Legs 0-1, like PSO frames.
##
## Numbers are first-pass, shaped like PSO's (Frame 5 / 5 up to the late
## frames in the 30s); Head and Legs are about 40% of a Torso of the same tier.

const TIER_NAMES := ["Plate", "Bastion", "Core", "Titan"]
const LIGHT_TIER_NAMES := ["Field", "Weave", "Lumen", "Aether"]
const TORSO_WORDS := {ArmorData.Weight.LIGHT: "Frame", ArmorData.Weight.HEAVY: "Armor"}
const HEAD_WORDS := {ArmorData.Weight.LIGHT: "Hood", ArmorData.Weight.HEAVY: "Helm"}
const LEGS_WORDS := {ArmorData.Weight.LIGHT: "Treads", ArmorData.Weight.HEAVY: "Greaves"}
const TORSO_SLOT_WEIGHTS := [25.0, 30.0, 25.0, 15.0, 5.0]  # 0..4 slots
const SMALL_SLOT_CHANCE := 0.5  # Head / Legs: 1 slot this often
const TIER_WEIGHTS := [50.0, 30.0, 15.0, 5.0]
const RARE_CHANCE := 0.04
## The starter piece every new Seeker wears.
const STARTER := &"field_frame"

static var _templates := {}


static func all() -> Dictionary:
	if _templates.is_empty():
		_build()
	return _templates


static func template(id: StringName) -> ArmorData:
	return all().get(id)


## A wearable copy of a template with no rolls (slots at their max).
static func make(id: StringName) -> ArmorData:
	var t := template(id)
	if t == null:
		return null
	var a := t.duplicate(true) as ArmorData
	a.slots = a.max_slots
	a.ensure_units()
	return a


## A dropped copy: DEF / EVA bonus and slot count rolled (rares keep theirs).
static func roll(id: StringName, rng: RandomNumberGenerator) -> ArmorData:
	var a := template(id).duplicate(true) as ArmorData
	a.def_bonus = rng.randi_range(0, a.max_def_bonus)
	a.eva_bonus = rng.randi_range(0, a.max_eva_bonus)
	if a.rare:
		a.slots = a.max_slots
	elif a.slot == ArmorData.Slot.TORSO:
		a.slots = _weighted(TORSO_SLOT_WEIGHTS, rng)
	else:
		a.slots = 1 if rng.randf() < SMALL_SLOT_CHANCE else 0
	a.ensure_units()
	return a


## A random drop: a rare 4% of the time, otherwise tier-weighted.
static func roll_drop(rng: RandomNumberGenerator) -> ArmorData:
	var rares: Array = []
	var by_tier := [[], [], [], []]
	for id in all():
		var t: ArmorData = all()[id]
		if t.rare:
			rares.append(id)
		else:
			by_tier[t.tier - 1].append(id)
	if rng.randf() < RARE_CHANCE:
		return roll(rares[rng.randi() % rares.size()], rng)
	var pool: Array = by_tier[_weighted(TIER_WEIGHTS, rng)]
	return roll(pool[rng.randi() % pool.size()], rng)


# --- Who can wear what ------------------------------------------------------------

## "" when the character can wear this piece, otherwise why not.
static func equip_error(c: CharacterData, a: ArmorData) -> String:
	if a.weight == ArmorData.Weight.HEAVY and c.job == CharacterData.Job.INVOKER:
		return "Invokers wear Light armor only"
	if a.jobs != "" and not c.job_code() in a.jobs:
		return "%s can't wear %s (jobs %s)" % [c.job_name(), a.display_name, a.jobs]
	if a.race_only >= 0 and c.race != a.race_only:
		return "%s only" % CharacterData.Race.keys()[a.race_only].capitalize()
	if a.gender_only >= 0 and c.gender != a.gender_only:
		return "%s only" % ("Female" if a.gender_only == CharacterData.Gender.FEMALE else "Male")
	return ""


static func equipped(c: CharacterData) -> Array[ArmorData]:
	var out: Array[ArmorData] = []
	for a in [c.head, c.torso, c.legs]:
		if a:
			out.append(a)
	return out


static func piece(c: CharacterData, slot: ArmorData.Slot) -> ArmorData:
	match slot:
		ArmorData.Slot.HEAD:
			return c.head
		ArmorData.Slot.LEGS:
			return c.legs
	return c.torso


static func set_piece(c: CharacterData, slot: ArmorData.Slot, a: ArmorData) -> void:
	match slot:
		ArmorData.Slot.HEAD:
			c.head = a
		ArmorData.Slot.LEGS:
			c.legs = a
		_:
			c.torso = a


# --- Totals ----------------------------------------------------------------------

## Stats property -> amount, over every equipped piece and its augments.
static func bonuses(c: CharacterData) -> Dictionary:
	var out := {}
	for a in equipped(c):
		var b := a.stat_bonuses()
		for stat in b:
			out[stat] = float(out.get(stat, 0.0)) + float(b[stat])
	return out


## Fraction of an element's damage the armor takes away (capped at 75%).
static func resist(c: CharacterData, element: int) -> float:
	var total := 0.0
	for a in equipped(c):
		total += a.resist(element)
	return minf(total, 0.75)


static func monster_resist(c: CharacterData, enemy_type: int) -> float:
	var total := 0.0
	for a in equipped(c):
		total += a.monster_resist(enemy_type)
	return minf(total, 0.75)


static func has_double_heavy(c: CharacterData) -> bool:
	for a in equipped(c):
		if a.has_double_heavy():
			return true
	return false


# --- Equipping and augments (operate on the save) -----------------------------------

## Wears a piece from the inventory; the piece it replaces goes back, augments
## and all. Returns "" or why not.
static func equip(save: SaveData, a: ArmorData) -> String:
	var error := equip_error(save.character, a)
	if error != "":
		return error
	var old := piece(save.character, a.slot)
	save.inventory.armors.erase(a)
	if old:
		save.inventory.armors.append(old)
	set_piece(save.character, a.slot, a)
	return ""


## Takes off anything the character can no longer wear (after a race, gender
## or job change). Returns the names of what came off.
static func strip_unwearable(save: SaveData) -> PackedStringArray:
	var removed := PackedStringArray()
	for a in equipped(save.character):
		if equip_error(save.character, a) != "":
			removed.append(a.display_name)
			unequip(save, a.slot)
	return removed


static func unequip(save: SaveData, slot: ArmorData.Slot) -> void:
	var old := piece(save.character, slot)
	if old:
		save.inventory.armors.append(old)
		set_piece(save.character, slot, null)


## Puts an augment from the inventory into a slot; whatever was there goes back.
static func insert_unit(save: SaveData, a: ArmorData, index: int, unit_id: StringName) -> String:
	if index < 0 or index >= a.slots:
		return "No such slot"
	if save.inventory.unit_count(unit_id) <= 0:
		return "No %s left" % UnitBook.display_name(unit_id)
	a.ensure_units()
	remove_unit(save, a, index)
	save.inventory.take_unit(unit_id)
	a.units[index] = unit_id
	return ""


static func remove_unit(save: SaveData, a: ArmorData, index: int) -> void:
	a.ensure_units()
	if index < a.units.size() and a.units[index] != &"":
		save.inventory.add_unit(a.units[index])
		a.units[index] = &""


# --- Templates -------------------------------------------------------------------

static func _build() -> void:
	for tier in range(1, 5):
		for weight in [ArmorData.Weight.LIGHT, ArmorData.Weight.HEAVY]:
			for slot in [ArmorData.Slot.HEAD, ArmorData.Slot.TORSO, ArmorData.Slot.LEGS]:
				_add(_tiered(tier, weight, slot))
	_rares()


static func _tiered(tier: int, weight: ArmorData.Weight, slot: ArmorData.Slot) -> ArmorData:
	var a := ArmorData.new()
	a.tier = tier
	a.weight = weight
	a.slot = slot
	var t := tier - 1
	var prefix: String = (LIGHT_TIER_NAMES if weight == ArmorData.Weight.LIGHT else TIER_NAMES)[t]
	var words: Dictionary = {ArmorData.Slot.HEAD: HEAD_WORDS, ArmorData.Slot.TORSO: TORSO_WORDS,
		ArmorData.Slot.LEGS: LEGS_WORDS}[slot]
	a.display_name = "%s %s" % [prefix, words[weight]]
	a.id = StringName(a.display_name.to_lower().replace(" ", "_"))
	var def := 4.0 + 5.0 * t if weight == ArmorData.Weight.LIGHT else 8.0 + 8.0 * t
	var eva := 6.0 + 5.0 * t if weight == ArmorData.Weight.LIGHT else 2.0 + 3.0 * t
	var res := 4.0 + 4.0 * t if weight == ArmorData.Weight.LIGHT else 2.0 + 2.0 * t
	var scale := 1.0 if slot == ArmorData.Slot.TORSO else 0.4
	a.defense = roundf(def * scale)
	a.evasion = roundf(eva * scale)
	a.resolve = roundf(res * scale)
	a.max_def_bonus = roundi((2 + tier) * scale)
	a.max_eva_bonus = roundi((2 + tier) * scale)
	a.max_slots = 4 if slot == ArmorData.Slot.TORSO else 1
	# Job-locked sets (Grayson: some armor is job locked).
	if prefix == "Core":
		a.jobs = "R"
	elif prefix == "Titan":
		a.jobs = "S"
	elif prefix == "Aether":
		a.jobs = "I"
		a.resolve += roundf(4.0 * scale)
	return a


static func _rares() -> void:
	var shell := _rare("Ironclad Shell", ArmorData.Slot.TORSO, ArmorData.Weight.HEAVY, 40, 4, 10, 4)
	shell.race_only = CharacterData.Race.GOLUMAN
	shell.resists = {Element.Type.LIGHTNING: 0.2}
	var veil := _rare("Veil of the Nomad", ArmorData.Slot.HEAD, ArmorData.Weight.LIGHT, 6, 6, 18, 1)
	veil.jobs = "I"
	veil.bonuses = {&"soul": 10.0}
	veil.resists = {Element.Type.LIGHT: 0.15, Element.Type.DARK: 0.15}
	var greaves := _rare("Huntress Treads", ArmorData.Slot.LEGS, ArmorData.Weight.LIGHT, 6, 16, 4, 1)
	greaves.gender_only = CharacterData.Gender.FEMALE
	greaves.bonuses = {&"dexterity": 8.0}
	var crown := _rare("Warden's Crown", ArmorData.Slot.HEAD, ArmorData.Weight.HEAVY, 14, 3, 4, 2)
	crown.jobs = "S"
	crown.bonuses = {&"strength": 10.0}
	var treads := _rare("Pathfinder Treads", ArmorData.Slot.LEGS, ArmorData.Weight.LIGHT, 5, 10, 4, 2)
	treads.bonuses = {&"accuracy": 5.0}
	for a in [shell, veil, greaves, crown, treads]:
		_add(a)


static func _rare(display: String, slot: ArmorData.Slot, weight: ArmorData.Weight,
		def: float, eva: float, res: float, slot_count: int) -> ArmorData:
	var a := ArmorData.new()
	a.display_name = display
	a.id = StringName(display.to_lower().replace("'", "").replace(" ", "_"))
	a.slot = slot
	a.weight = weight
	a.tier = 4
	a.rare = true
	a.defense = def
	a.evasion = eva
	a.resolve = res
	a.max_def_bonus = 3
	a.max_eva_bonus = 3
	a.max_slots = slot_count
	return a


static func _add(a: ArmorData) -> void:
	_templates[a.id] = a


static func _weighted(weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	var r := rng.randf() * total
	for i in weights.size():
		r -= float(weights[i])
		if r <= 0.0:
			return i
	return weights.size() - 1
