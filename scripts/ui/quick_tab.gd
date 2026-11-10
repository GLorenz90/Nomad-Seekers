class_name QuickTab
extends HBoxContainer
## Equip section (Grayson, 2026-11-09): the d-pad palette. Eight slots: d-pad
## left / up / right / down, and the same four with RT held. Each holds a
## consumable, or for Goluman a trap (set at your feet for its LP, like an
## item). Goluman see this section as "Traps", in place of Spells.
##
## Gamepad: A on a slot opens its choices, A on a choice puts it there, X
## clears the slot, B steps back. Up from the top goes to the section buttons.

var menu: LoadoutMenu
var _slots: VBoxContainer
var _choices: VBoxContainer
var _choice_title: Label
var _info: Label
var _message: Label
var _slot := -1


func _init(owner_menu: LoadoutMenu) -> void:
	menu = owner_menu
	name = "Quick"
	add_theme_constant_override("separation", 30)


func _ready() -> void:
	var left := _column(380.0)
	left.add_child(_label("D-pad palette", 18))
	_slots = VBoxContainer.new()
	_slots.add_theme_constant_override("separation", 4)
	left.add_child(_slots)
	left.add_child(_label("A: choose   X: clear   B: back\nIn play: d-pad uses a slot, hold RT for the second four.", 13))
	_message = _label("", 15)
	_message.modulate = Color(1.0, 0.85, 0.5)
	left.add_child(_message)

	var right := _column(460.0)
	_choice_title = _label("Choices", 18)
	right.add_child(_choice_title)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 4)
	right.add_child(_choices)
	_info = _label("", 14)
	_info.modulate = Color(0.75, 0.85, 1.0)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size.x = 440.0
	right.add_child(_info)


func _column(width: float) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.custom_minimum_size.x = width
	c.add_theme_constant_override("separation", 8)
	add_child(c)
	return c


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _save() -> SaveData:
	var p := menu.combat.get_parent() as Player if menu and menu.combat else null
	return p.save if p else null


func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


# --- Refresh ---------------------------------------------------------------------

func refresh() -> void:
	var save := _save()
	if save == null or _slots == null:
		return
	var c := save.character
	_clear(_slots)
	for i in SaveData.QUICK_SLOTS:
		if i == 4:
			_slots.add_child(_label("Hold RT", 14))
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s%s:  %s" % ["> " if i == _slot else "   ", SaveData.QUICK_NAMES[i],
			DebugHud.quick_label(save, save.quick(i))]
		b.set_meta("slot", i)
		b.pressed.connect(_pick_slot.bind(i))
		_slots.add_child(b)
	menu._equip_tab.link_up(_first_button(_slots))
	_rebuild_choices(save)
	if c.can_use_traps():
		_info.text = "Traps are set at your feet for their LP. Learn them from trap discs (needs DEX %d now).\nUp to %d set at once." % [
			roundi(menu.combat.stats.dexterity), SpellCaster.MAX_TRAPS]
	else:
		_info.text = ""


func _rebuild_choices(save: SaveData) -> void:
	_clear(_choices)
	_choice_title.text = "Put on %s" % SaveData.QUICK_NAMES[_slot] if _slot >= 0 else "Choices (pick a slot)"
	_choices.add_child(_choice_button("(empty)", &""))
	for id in Inventory.CONSUMABLES:
		_choices.add_child(_choice_button("%s  x%d" % [Inventory.CONSUMABLES[id], save.inventory.count(id)], id))
	var c := save.character
	if not c.can_use_traps():
		return
	var header := _label("Traps", 14)
	header.modulate = Color(0.9, 0.7, 1.0)
	_choices.add_child(header)
	var any := false
	for spell in SpellBook.traps_only():
		var level := c.spell_level(spell.id)
		if level <= 0:
			continue
		any = true
		_choices.add_child(_choice_button("%s %d   %s LP" % [spell.display_name, level, str(spell.lp_cost(level))], spell.id))
	if not any:
		_choices.add_child(_label("No traps learned yet (trap discs drop from enemies;\nthe Debug tab can teach them).", 14))


func _choice_button(text: String, id: StringName) -> Button:
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = text
	b.set_meta("id", id)
	b.pressed.connect(_assign.bind(id))
	return b


# --- Actions ---------------------------------------------------------------------

func _pick_slot(index: int) -> void:
	_slot = index
	refresh()
	_focus_choice(_save().quick(index))


func _assign(id: StringName) -> void:
	var save := _save()
	if save == null:
		return
	if _slot < 0:
		_message.text = "Pick a slot first."
		_focus_slot(0)
		return
	save.set_quick(_slot, id)
	_message.text = "%s: %s" % [SaveData.QUICK_NAMES[_slot], DebugHud.quick_label(save, id) if id != &"" else "empty"]
	var done := _slot
	_slot = -1
	refresh()
	_focus_slot(done)


## X on a slot empties it. True when a slot was focused.
func clear_focused() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not _slots.is_ancestor_of(focus):
		return false
	var index: int = focus.get_meta("slot", -1)
	if index < 0:
		return false
	_save().set_quick(index, &"")
	_message.text = "%s cleared." % SaveData.QUICK_NAMES[index]
	refresh()
	_focus_slot(index)
	return true


## B: from the choices back to the slot. False when already on the slots.
func back() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	if focus and _choices.is_ancestor_of(focus):
		var index := maxi(_slot, 0)
		_slot = -1
		refresh()
		_focus_slot(index)
		return true
	return false


func focus_default() -> void:
	_focus_slot(maxi(_slot, 0))


func _focus_slot(index: int) -> void:
	for b in _slots.get_children():
		if b is Button and int(b.get_meta("slot", -1)) == index:
			(b as Button).grab_focus.call_deferred()
			return


func _focus_choice(id: StringName) -> void:
	for b in _choices.get_children():
		if b is Button and StringName(b.get_meta("id", &"?")) == id:
			(b as Button).grab_focus.call_deferred()
			return
	var first := _first_button(_choices)
	if first:
		first.grab_focus.call_deferred()


func _first_button(box: Container) -> Button:
	for child in box.get_children():
		if child is Button and not child.is_queued_for_deletion():
			return child
	return null


## Slot buttons, for tests: [text, ...].
func slot_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for b in _slots.get_children():
		if b is Button:
			out.append((b as Button).text)
	return out
