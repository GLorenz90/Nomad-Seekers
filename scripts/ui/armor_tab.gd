class_name ArmorTab
extends HBoxContainer
## Menu tab (Part 7): the Seeker's armor (Head, Torso, Legs) and the augments
## in its slots. One set per character, like PSO.
##
## Gamepad: pick a piece (A) to see the armor you could wear there, or one of
## its augment slots (A) to see your augments; A on the right-hand list wears
## or slots it. X takes off the highlighted piece or empties the highlighted
## slot. B steps back a column.

var menu: LoadoutMenu
var _worn: VBoxContainer
var _choices: VBoxContainer
var _choice_title: Label
var _totals: Label
var _message: Label
## What the right-hand list is for: Vector2i(slot, -1) for a piece,
## Vector2i(slot, augment index) for an augment slot, (-1, -1) for nothing.
var _pick := Vector2i(-1, -1)


func _init(owner_menu: LoadoutMenu) -> void:
	menu = owner_menu
	name = "Armor"
	add_theme_constant_override("separation", 30)


func _ready() -> void:
	var left := _column(560.0)
	left.add_child(_label("Worn (one set per character)", 18))
	_worn = VBoxContainer.new()
	left.add_child(_worn)
	left.add_child(_label("A: change   X: take off / empty the slot   B: back", 13))
	_totals = _label("", 15)
	_totals.modulate = Color(0.75, 0.85, 1.0)
	left.add_child(_totals)
	_message = _label("", 15)
	_message.modulate = Color(1.0, 0.85, 0.5)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.x = 540.0
	left.add_child(_message)

	var right := _column(560.0)
	_choice_title = _label("", 18)
	right.add_child(_choice_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560.0, 560.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_choices = VBoxContainer.new()
	_choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_choices)
	right.add_child(scroll)


func _column(width: float) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.custom_minimum_size.x = width
	c.add_theme_constant_override("separation", 6)
	add_child(c)
	return c


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _player() -> Player:
	return menu.combat.get_parent() as Player if menu and menu.combat else null


func _save() -> SaveData:
	var p := _player()
	return p.save if p else null


# --- Refresh ---------------------------------------------------------------------

func refresh() -> void:
	var save := _save()
	if save == null or _worn == null:
		return
	_rebuild_worn(save)
	_rebuild_choices(save)
	_totals.text = _totals_text(save.character)


func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _rebuild_worn(save: SaveData) -> void:
	_clear(_worn)
	for slot in [ArmorData.Slot.HEAD, ArmorData.Slot.TORSO, ArmorData.Slot.LEGS]:
		var a := ArmorBook.piece(save.character, slot)
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s%s:  %s" % ["> " if _pick == Vector2i(slot, -1) else "   ", ArmorData.SLOT_NAMES[slot],
			("%s  (%s, DEF %d EVA %d)" % [a.display_name, a.weight_name(), roundi(a.total_defense()), roundi(a.total_evasion())]) if a else "(none)"]
		if a and a.rare:
			b.modulate = Color(1.0, 0.7, 1.0)
		b.set_meta("piece", slot)
		b.set_meta("unit", -1)
		b.pressed.connect(_pick_piece.bind(slot))
		_worn.add_child(b)
		if a == null:
			continue
		a.ensure_units()
		for i in a.slots:
			var u := Button.new()
			u.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var id := a.units[i]
			u.text = "%s      Slot %d:  %s" % ["> " if _pick == Vector2i(slot, i) else "   ", i + 1,
				"%s  (%s)" % [UnitBook.display_name(id), UnitBook.describe(id)] if id != &"" else "(empty)"]
			u.set_meta("piece", slot)
			u.set_meta("unit", i)
			u.pressed.connect(_pick_unit_slot.bind(slot, i))
			_worn.add_child(u)


func _rebuild_choices(save: SaveData) -> void:
	_clear(_choices)
	if _pick.x < 0:
		_choice_title.text = "Pick a piece or an augment slot"
		_choices.add_child(_label("Armor and augments drop from enemies\n(the Blue emblem finds armor twice as often).\nDebug tab: one of every piece and augment.", 15))
		return
	var slot := _pick.x as ArmorData.Slot
	if _pick.y < 0:
		_choice_title.text = "%s armor you own" % ArmorData.SLOT_NAMES[slot]
		var any := false
		for a in save.inventory.armors:
			if a.slot != slot:
				continue
			any = true
			var b := Button.new()
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var error := ArmorBook.equip_error(save.character, a)
			b.text = "%s%s\n      %s" % [a.display_name, "  (RARE)" if a.rare else "", a.summary()]
			if error != "":
				b.text += "\n      Can't wear: " + error
				b.modulate = Color(1, 1, 1, 0.5)
			elif a.rare:
				b.modulate = Color(1.0, 0.7, 1.0)
			b.pressed.connect(_wear.bind(a))
			_choices.add_child(b)
		if not any:
			_choices.add_child(_label("No other %s armor yet." % ArmorData.SLOT_NAMES[slot].to_lower(), 15))
		return
	_choice_title.text = "Augments you own"
	var ids := save.inventory.units.keys()
	ids.sort()
	if ids.is_empty():
		_choices.add_child(_label("No augments yet.", 15))
	for id in ids:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s x%d   %s" % [UnitBook.display_name(id), save.inventory.unit_count(id), UnitBook.describe(id)]
		b.pressed.connect(_slot_unit.bind(id))
		_choices.add_child(b)


func _totals_text(c: CharacterData) -> String:
	var b := ArmorBook.bonuses(c)
	var lines := PackedStringArray()
	var stats := PackedStringArray()
	for stat in b:
		if float(b[stat]) != 0.0:
			stats.append("%s +%d" % [UnitBook.stat_label(stat), roundi(float(b[stat]))])
	lines.append("From armor: " + (", ".join(stats) if not stats.is_empty() else "nothing"))
	var res := PackedStringArray()
	for element in range(1, Element.Type.size()):
		var r := ArmorBook.resist(c, element)
		if r > 0.0:
			res.append("%s %d%%" % [String(Element.Type.keys()[element]).capitalize(), roundi(r * 100.0)])
	for t in EnemyData.EnemyType.size():
		var r := ArmorBook.monster_resist(c, t)
		if r > 0.0:
			res.append("%s-type %d%%" % [String(EnemyData.EnemyType.keys()[t]).capitalize(), roundi(r * 100.0)])
	if not res.is_empty():
		lines.append("Resists: " + ", ".join(res))
	lines.append("Double-Heavy: %s" % ("on (two Heavy one-handed items allowed)" if ArmorBook.has_double_heavy(c) else "off"))
	if c.job == CharacterData.Job.INVOKER:
		lines.append("Invokers wear Light armor only.")
	return "\n".join(lines)


# --- Actions ---------------------------------------------------------------------

func _pick_piece(slot: int) -> void:
	_pick = Vector2i(slot, -1)
	refresh()
	if not _focus_first(_choices):
		_focus_pick()


func _pick_unit_slot(slot: int, index: int) -> void:
	_pick = Vector2i(slot, index)
	refresh()
	if not _focus_first(_choices):
		_focus_pick()


func _wear(a: ArmorData) -> void:
	var save := _save()
	var error := ArmorBook.equip(save, a)
	_message.text = error if error != "" else "Wearing %s." % a.display_name
	_after_change()


func _slot_unit(id: StringName) -> void:
	var save := _save()
	var a := ArmorBook.piece(save.character, _pick.x as ArmorData.Slot)
	if a == null:
		return
	var error := ArmorBook.insert_unit(save, a, _pick.y, id)
	_message.text = error if error != "" else "%s slotted into %s." % [UnitBook.display_name(id), a.display_name]
	_after_change()


## X: takes off the highlighted piece or empties the highlighted augment slot.
func clear_focused() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not _worn.is_ancestor_of(focus):
		return false
	var save := _save()
	var slot := int(focus.get_meta("piece", -1)) as ArmorData.Slot
	var index := int(focus.get_meta("unit", -1))
	var a := ArmorBook.piece(save.character, slot)
	if a == null:
		return true
	if index < 0:
		ArmorBook.unequip(save, slot)
		_message.text = "Took off %s (its augments stay in it)." % a.display_name
		_pick = Vector2i(slot, -1)
	else:
		ArmorBook.remove_unit(save, a, index)
		_message.text = "Slot emptied."
		_pick = Vector2i(slot, index)
	_after_change()
	return true


func _after_change() -> void:
	var p := _player()
	if p:
		p.apply_bonuses()
	menu._refresh()
	_focus_pick()


## B: back to the worn list. Returns false when already there.
func back() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	if focus and _choices.is_ancestor_of(focus):
		_focus_pick()
		return true
	if _pick.x >= 0 and focus and _worn.is_ancestor_of(focus) and _pick != Vector2i(-1, -1):
		_pick = Vector2i(-1, -1)
		refresh()
		return false
	return false


func focus_default() -> void:
	if not _focus_pick():
		_focus_first(_worn)


func _focus_pick() -> bool:
	for b in _worn.get_children():
		if b is Button and int(b.get_meta("piece", -2)) == _pick.x and int(b.get_meta("unit", -2)) == _pick.y:
			(b as Button).grab_focus.call_deferred()
			return true
	return _focus_first(_worn)


func _focus_first(box: Container) -> bool:
	for child in box.get_children():
		if child is Button and not child.is_queued_for_deletion():
			(child as Button).grab_focus.call_deferred()
			return true
	return false
