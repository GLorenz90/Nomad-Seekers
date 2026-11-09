class_name UnitBook
extends RefCounted
## Augments (Part 7): PSO's units, slotted into armor. Each is one of:
## - a flat stat bonus (three grades),
## - an element resistance (two grades),
## - a monster-type resistance (damage from that type of enemy),
## - the Double-Heavy augment: two Heavy one-handed items per loadout.
## Augments are items: they drop, sit in the inventory (Inventory.units), and
## go in and out of armor slots freely.

const DOUBLE_HEAVY := &"double_heavy"

## Stats property -> [short label, amount per grade].
const STAT_UNITS := {
	&"strength": ["STR", [5, 10, 15]],
	&"dexterity": ["DEX", [5, 10, 15]],
	&"soul": ["SOL", [5, 10, 15]],
	&"defense": ["DEF", [5, 10, 15]],
	&"resolve": ["RES", [5, 10, 15]],
	&"evasion": ["EVA", [5, 10, 15]],
	&"accuracy": ["ATA", [5, 10, 15]],
	&"luck": ["LCK", [5, 10, 15]],
	&"max_hp": ["HP", [20, 40, 60]],
	&"max_lp": ["LP", [10, 20, 30]],
}
const GRADES := ["I", "II", "III"]
const ELEMENT_GRADES := [0.1, 0.2]
const MONSTER_RESIST := 0.15

static var _all := {}


## Every augment id -> {name, kind, grade, and stat/amount, element/amount or
## monster/amount}.
static func all() -> Dictionary:
	if _all.is_empty():
		_build()
	return _all


static func get_unit(id: StringName) -> Dictionary:
	if id == &"":
		return {}
	return all().get(id, {})


static func display_name(id: StringName) -> String:
	return String(get_unit(id).get("name", id))


static func describe(id: StringName) -> String:
	var u := get_unit(id)
	if u.is_empty():
		return ""
	if u.has("stat"):
		return "%s +%d" % [stat_label(u.stat), int(u.amount)]
	if u.has("element"):
		return "%s damage -%d%%" % [Element.Type.keys()[u.element].capitalize(), roundi(u.amount * 100.0)]
	if u.has("monster"):
		return "Damage from %s-type enemies -%d%%" % [EnemyData.EnemyType.keys()[u.monster].capitalize(), roundi(u.amount * 100.0)]
	return "Two Heavy one-handed items per loadout"


static func stat_label(stat: StringName) -> String:
	if STAT_UNITS.has(stat):
		return STAT_UNITS[stat][0]
	return String(stat).capitalize()


static func ids() -> Array:
	return all().keys()


## Drop roll: grade weights 6 / 3 / 1 for stat augments; Double-Heavy is rare.
static func roll(rng: RandomNumberGenerator) -> StringName:
	if rng.randf() < 0.03:
		return DOUBLE_HEAVY
	var pool: Array[StringName] = []
	var weights: Array[float] = []
	for id in all():
		var u: Dictionary = all()[id]
		if u.kind == "special":
			continue
		pool.append(id)
		weights.append([6.0, 3.0, 1.0][int(u.grade)])
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	for i in pool.size():
		r -= weights[i]
		if r <= 0.0:
			return pool[i]
	return pool[-1]


static func _build() -> void:
	for stat in STAT_UNITS:
		var spec: Array = STAT_UNITS[stat]
		for g in 3:
			var id := StringName("%s_%d" % [String(spec[0]).to_lower(), g + 1])
			_all[id] = {"name": "%s Augment %s" % [spec[0], GRADES[g]], "kind": "stat", "grade": g,
				"stat": stat, "amount": spec[1][g]}
	for element in range(1, Element.Type.size()):
		var element_name := String(Element.Type.keys()[element]).capitalize()
		for g in ELEMENT_GRADES.size():
			var id := StringName("%s_ward_%d" % [element_name.to_lower(), g + 1])
			_all[id] = {"name": "%s Ward %s" % [element_name, GRADES[g]], "kind": "element", "grade": g,
				"element": element, "amount": ELEMENT_GRADES[g]}
	for t in EnemyData.EnemyType.size():
		var type_name := String(EnemyData.EnemyType.keys()[t]).capitalize()
		_all[StringName("%s_guard" % type_name.to_lower())] = {"name": "%s Guard" % type_name, "kind": "monster",
			"grade": 1, "monster": t, "amount": MONSTER_RESIST}
	_all[DOUBLE_HEAVY] = {"name": "Double-Heavy Augment", "kind": "special", "grade": 2}
