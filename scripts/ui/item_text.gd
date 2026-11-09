class_name ItemText
extends RefCounted
## Names, colors and descriptions for pack and bank entries (Part 10: shared
## by the Inventory tab and the counters). An entry is {"kind": "weapon" |
## "armor" | "unit" | "disc" | "stack", plus what it refers to}; discs and
## stacks are read from `inv` (the pack's or the bank's Inventory).

const USE_TEXT := {
	&"hp_gel": "Restores 30% of your HP.",
	&"lp_cell": "Restores 50% of your LP.",
	&"cure_salt": "Clears every status effect.",
	&"trap_scanner": "Reveals the traps in the room you're in (15 m outside rooms).",
}


static func label(e: Dictionary, save: SaveData, inv: Inventory) -> String:
	match e.kind:
		"weapon":
			var w: WeaponData = e.weapon
			var on := save.palettes_with(w)
			var tag := ""
			if not on.is_empty():
				tag = "  [P%s]" % ",".join(Array(on).map(func(n: int) -> String: return str(n)))
			return "%s%s" % [w.display_name, tag]
		"armor":
			var a: ArmorData = e.armor
			return "%s%s  (%s %s)" % ["[W] " if e.get("worn", false) else "", a.display_name,
				ArmorData.SLOT_NAMES[a.slot], a.weight_name()]
		"unit":
			return "Augment: %s" % UnitBook.display_name(e.unit)
		"disc":
			return "Disc: %s" % disc_name(inv.discs[e.index])
		"stack":
			return "%s x%d" % [Inventory.item_name(e.id), inv.count(e.id)]
	return "?"


static func disc_name(d: Dictionary) -> String:
	var spell := SpellBook.get_spell(StringName(d.id))
	return "%s %d" % [spell.display_name if spell else String(d.id), int(d.level)]


static func color(e: Dictionary) -> Color:
	match e.kind:
		"weapon":
			return Color(1.0, 0.65, 1.0) if (e.weapon as WeaponData).rare else Color(0.8, 0.9, 1.0)
		"armor":
			return Color(1.0, 0.65, 1.0) if (e.armor as ArmorData).rare else Color(0.85, 0.85, 0.95)
		"unit":
			return Color(0.95, 0.95, 0.6)
		"disc":
			return Color(0.6, 0.95, 1.0)
		"stack":
			return Color(1.0, 0.75, 0.45) if Materials.ALL.has(e.id) else Color(0.6, 1.0, 0.7)
	return Color.WHITE


static func weapon_detail(w: WeaponData, job_code: String) -> String:
	var lines := PackedStringArray([w.display_name + ("  (RARE)" if w.rare else "")])
	var tags := Loot.describe(w)
	if tags != "":
		lines.append(tags)
	lines.append("Jobs: %s   %s%s   Base damage %d" % [w.jobs_text(), "Heavy" if w.is_heavy() else "Light",
		", two-handed" if w.two_handed else "", roundi(w.base_damage)])
	if not w.can_be_used_by(job_code):
		lines.append("Your job can't use it.")
	return "\n".join(lines)


static func armor_detail(a: ArmorData, c: CharacterData, worn: bool) -> String:
	var text := "%s%s\n%s" % [a.display_name, "  (RARE)" if a.rare else "", a.summary()]
	if worn:
		text += "\nWorn."
	else:
		var error := ArmorBook.equip_error(c, a)
		if error != "":
			text += "\nCan't wear: " + error
	return text


static func detail(e: Dictionary, player: Player, inv: Inventory) -> String:
	var save := player.save
	match e.kind:
		"weapon":
			var w: WeaponData = e.weapon
			var on := save.palettes_with(w)
			return weapon_detail(w, player.combat.job_code) + "\n" + (
				"On palette %s." % ", ".join(Array(on).map(func(n: int) -> String: return str(n))) if not on.is_empty() else "Not on a palette.")
		"armor":
			return armor_detail(e.armor, save.character, e.get("worn", false))
		"unit":
			return "%s\n%s\nGoes in an augment slot of worn armor." % [UnitBook.display_name(e.unit), UnitBook.describe(e.unit)]
		"disc":
			var d: Dictionary = inv.discs[e.index]
			var spell := SpellBook.get_spell(StringName(d.id))
			if spell == null:
				return "Unknown disc"
			var error := save.character.learn_error(spell, int(d.level), player.learning_stat(spell))
			return "%s (%s)\n%s" % [disc_name(d), spell.element_name(), "Can be read now." if error == "" else error]
		"stack":
			return stack_detail(e.id, save) + "\nYou have %d here (one slot per stack)." % inv.count(e.id)
	return ""


static func stack_detail(id: StringName, save: SaveData) -> String:
	if Materials.ALL.has(id):
		return "%s\n+%d %s, permanently. Used: %s." % [Materials.display_name(id), int(Materials.PER_USE),
			Materials.stat_label(id), Materials.limit_text(save.character, Materials.pool_of(id))]
	return "%s\n%s" % [Inventory.item_name(id), USE_TEXT.get(id, "")]
