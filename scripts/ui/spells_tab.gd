class_name SpellsTab
extends HBoxContainer
## Menu tab (Part 6): put learned spells (or a Goluman's traps) into the slots
## of each casting item in your loadouts, and read stored spell discs.
##
## Gamepad: pick a casting hand (A), then one of its slots (A), then a spell
## (A assigns it). X clears the highlighted slot. B steps back a column.

var menu: LoadoutMenu
var _hands: VBoxContainer
var _slots: VBoxContainer
var _spells: VBoxContainer
var _info: Label
var _message: Label
var _slot_title: Label
var _hand := Vector2i(-1, -1)  # (loadout index, hand)
var _slot := -1


func _init(owner_menu: LoadoutMenu) -> void:
	menu = owner_menu
	name = "Spells"
	add_theme_constant_override("separation", 26)


func _ready() -> void:
	var left := _column(300.0)
	left.add_child(_label("Casting items in your loadouts", 18))
	_hands = VBoxContainer.new()
	left.add_child(_hands)
	_info = _label("", 14)
	_info.modulate = Color(0.75, 0.85, 1.0)
	left.add_child(_info)

	var mid := _column(300.0)
	_slot_title = _label("Slots", 18)
	mid.add_child(_slot_title)
	_slots = VBoxContainer.new()
	mid.add_child(_slots)
	mid.add_child(_label("A: pick a spell for the slot   X: clear it   B: back", 13))
	_message = _label("", 15)
	_message.modulate = Color(1.0, 0.85, 0.5)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.x = 290.0
	mid.add_child(_message)

	var right := _column(430.0)
	right.add_child(_label("Learned", 18))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430.0, 560.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_spells = VBoxContainer.new()
	_spells.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_spells)
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


func _character() -> CharacterData:
	var p := _player()
	return p.save.character if p and p.save else null


# --- Refresh ---------------------------------------------------------------------

func refresh() -> void:
	var player := _player()
	var c := _character()
	if player == null or c == null or menu._set == null:
		return
	_info.text = "%s %d (with SyncAIDa)\n%s: %s %s%s" % [
		"DEX" if c.can_use_traps() else "SOL",
		roundi(player.combat.stats.dexterity if c.can_use_traps() else player.combat.stats.soul),
		c.spell_cap_text(), c.race_name(), c.job_name(),
		"\nGoluman can't cast spells: slots hold traps." if c.can_use_traps() else ""]
	_rebuild_hands()
	_rebuild_slots()
	_rebuild_spells()


func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _rebuild_hands() -> void:
	_clear(_hands)
	var any := false
	for i in menu._set.loadouts.size():
		var l := menu._set.loadouts[i]
		for hand in [1, 0]:
			if l.spell_slot_count(hand) == 0:
				continue
			any = true
			var b := Button.new()
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var w := l.get_hand(hand)
			b.text = "%s%d  %s: %s" % ["> " if _hand == Vector2i(i, hand) else "   ", i + 1,
				"Both hands" if w.two_handed else ("Right (%s)" % menu.combat.button_for(1) if hand == 1 else "Left (%s)" % menu.combat.button_for(0)),
				w.display_name]
			b.pressed.connect(_pick_hand.bind(i, hand))
			_hands.add_child(b)
	if not any:
		_hands.add_child(_label("No casting items equipped.\nPut a Wand, Cane, Staff, Talisman\nor Totem in a loadout first.", 15))


func _slot_names(loadout: Loadout, hand: int) -> Array[String]:
	if loadout.get_hand(hand).two_handed:
		return ["X", "Y", "RT + X", "RT + Y"]
	var button := menu.combat.button_for(hand)
	return [button, "RT + " + button]


func _rebuild_slots() -> void:
	_clear(_slots)
	if _hand.x < 0 or _hand.x >= menu._set.loadouts.size():
		_slot_title.text = "Slots"
		_slots.add_child(_label("Pick a casting item.", 15))
		return
	var l := menu._set.loadouts[_hand.x]
	var count := l.spell_slot_count(_hand.y)
	if count == 0:
		_hand = Vector2i(-1, -1)
		_rebuild_slots()
		return
	_slot_title.text = "Slots: loadout %d, %s" % [_hand.x + 1, l.get_hand(_hand.y).display_name]
	var names := _slot_names(l, _hand.y)
	for s in count:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s%s:  %s" % ["> " if s == _slot else "   ", names[s], _spell_text(l.get_spell(_hand.y, s))]
		b.set_meta("slot", s)
		b.pressed.connect(_pick_slot.bind(s))
		_slots.add_child(b)


func _spell_text(id: StringName) -> String:
	if id == &"":
		return "(empty)"
	var spell := SpellBook.get_spell(id)
	var c := _character()
	if spell == null:
		return "?"
	var level := c.spell_level(id) if c else 0
	if level <= 0:
		return "%s (not learned)" % spell.display_name
	return "%s %d  (%s LP)" % [spell.display_name, level, str(spell.lp_cost(level))]


func _rebuild_spells() -> void:
	_clear(_spells)
	var c := _character()
	if c == null:
		return
	var traps := c.can_use_traps()
	var known: Array[SpellDef] = []
	for spell in (SpellBook.traps_only() if traps else SpellBook.spells_only()):
		if c.spell_level(spell.id) > 0:
			known.append(spell)
	if known.is_empty():
		_spells.add_child(_label("Nothing learned yet. Spell discs drop from enemies\n(Levels tab can teach any spell for testing).", 15))
	var group := ""
	for spell in known:
		if spell.element_name() != group:
			group = spell.element_name()
			var header := _label(group, 14)
			header.modulate = SpellCaster._color(spell).lightened(0.2)
			_spells.add_child(header)
		var level := c.spell_level(spell.id)
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s %d   %s   %s LP" % [spell.display_name, level, spell.kind_name(), str(spell.lp_cost(level))]
		b.tooltip_text = spell.notes
		b.pressed.connect(_assign.bind(spell.id))
		_spells.add_child(b)
	# Stored discs: readable once SOL (or DEX) and the level cap allow.
	var player := _player()
	var discs: Array = player.save.inventory.discs if player and player.save else []
	if not discs.is_empty():
		_spells.add_child(_label("Stored discs", 14))
	for i in discs.size():
		var disc: Dictionary = discs[i]
		var spell := SpellBook.get_spell(StringName(disc.id))
		if spell == null:
			continue
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "Read disc: %s %d  (needs %s %d)" % [spell.display_name, int(disc.level),
			spell.requirement_stat(), spell.requirement(int(disc.level))]
		b.pressed.connect(_read_disc.bind(i))
		_spells.add_child(b)


# --- Actions ---------------------------------------------------------------------

func _pick_hand(index: int, hand: int) -> void:
	_hand = Vector2i(index, hand)
	_slot = -1
	refresh()
	_focus_first(_slots)


func _pick_slot(slot: int) -> void:
	_slot = slot
	refresh()
	if not _focus_first(_spells):
		_focus_slot()


func _assign(id: StringName) -> void:
	if _hand.x < 0:
		_message.text = "Pick a casting item and a slot first."
		_focus_first(_hands)
		return
	if _slot < 0:
		_message.text = "Pick a slot first."
		_focus_first(_slots)
		return
	menu._set.loadouts[_hand.x].set_spell(_hand.y, _slot, id)
	_message.text = "%s set." % SpellBook.get_spell(id).display_name
	refresh()
	_focus_slot()


func clear_focused_slot() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not _slots.is_ancestor_of(focus) or _hand.x < 0:
		return false
	var s: int = focus.get_meta("slot", -1)
	if s < 0:
		return false
	_slot = s
	menu._set.loadouts[_hand.x].set_spell(_hand.y, s, &"")
	_message.text = "Slot cleared."
	refresh()
	_focus_slot()
	return true


func _read_disc(index: int) -> void:
	var player := _player()
	if player == null:
		return
	_message.text = player.read_stored_disc(index)
	refresh()
	_focus_first(_spells)


## B: one column back. Returns false when already at the first column.
func back() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	if focus and _spells.is_ancestor_of(focus):
		_focus_slot()
		return true
	if focus and _slots.is_ancestor_of(focus):
		_slot = -1
		refresh()
		_focus_hand()
		return true
	return false


func focus_default() -> void:
	if _hand.x >= 0:
		_focus_hand()
	elif not _focus_first(_hands):
		menu.get_viewport().gui_release_focus()


func _focus_hand() -> void:
	for b in _hands.get_children():
		if b is Button and (b as Button).text.begins_with("> "):
			(b as Button).grab_focus.call_deferred()
			return
	_focus_first(_hands)


func _focus_slot() -> void:
	for b in _slots.get_children():
		if b is Button and int(b.get_meta("slot", -1)) == maxi(_slot, 0):
			(b as Button).grab_focus.call_deferred()
			return
	_focus_first(_slots)


func _focus_first(box: Container) -> bool:
	for child in box.get_children():
		if child is Button and not child.is_queued_for_deletion():
			(child as Button).grab_focus.call_deferred()
			return true
	return false
