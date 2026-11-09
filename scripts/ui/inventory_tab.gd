class_name InventoryTab
extends HBoxContainer
## Menu tab (Part 9): PSO's item pack, plus the satchel (Grayson, 2026-11-09).
##
## Left: the pack's slots (every item and piece of gear, worn and palette ones
## included) and the satchel (Oro, carried Lumidium). The focused entry is
## described on the right. A opens what you can do with it: equip it to the
## current palette, wear it, slot it, use it, read it, or drop it. Stacks, Oro
## and Lumidium can be dropped in part (pick the amount) and lie on the ground
## as one stack for someone to pick up.
##
## Gamepad: d-pad moves, A opens the actions / confirms, B steps back.

var menu: LoadoutMenu
var _header: Label
var _list: VBoxContainer
var _satchel: VBoxContainer
var _detail: Label
var _actions_title: Label
var _actions: VBoxContainer
var _message: Label
## The entry whose actions are open ({} when none).
var _open: Dictionary = {}
## Drop amount being picked (stacks, Oro, Lumidium).
var _amount := 1
var _amount_label: Label
## Index into the pack list to refocus after a rebuild.
var _focus_index := 0

const USE_TEXT := {
	&"hp_gel": "Restores 30% of your HP.",
	&"lp_cell": "Restores 50% of your LP.",
	&"cure_salt": "Clears every status effect.",
	&"trap_scanner": "Reveals the traps in the room you're in (15 m outside rooms).",
}


func _init(owner_menu: LoadoutMenu) -> void:
	menu = owner_menu
	name = "Inventory"
	add_theme_constant_override("separation", 26)


func _ready() -> void:
	var left := _column(500.0)
	_header = _label("", 20)
	left.add_child(_header)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500.0, 430.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 1)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	left.add_child(scroll)
	left.add_child(_label("Satchel (outside the pack)", 18))
	_satchel = VBoxContainer.new()
	_satchel.add_theme_constant_override("separation", 1)
	left.add_child(_satchel)

	var right := _column(560.0)
	_detail = _label("", 16)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(560.0, 170.0)
	right.add_child(_detail)
	_actions_title = _label("", 18)
	right.add_child(_actions_title)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 3)
	right.add_child(_actions)
	_message = _label("", 16)
	_message.modulate = Color(1.0, 0.85, 0.5)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.x = 560.0
	right.add_child(_message)
	right.add_child(_label("A: actions   B: back   LB/RB: tabs", 13))


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


# --- Entries --------------------------------------------------------------------

## Every pack slot, in PSO-ish order: weapons, armor, augments, discs, stacks.
## Each entry: {"kind": ..., plus what it refers to}.
func entries() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var save := _save()
	if save == null:
		return list
	var inv := save.inventory
	for w in inv.weapons:
		list.append({"kind": "weapon", "weapon": w})
	for a in ArmorBook.equipped(save.character):
		list.append({"kind": "armor", "armor": a, "worn": true})
	for a in inv.armors:
		list.append({"kind": "armor", "armor": a, "worn": false})
	var unit_ids := inv.units.keys()
	unit_ids.sort()
	for id in unit_ids:
		for i in inv.unit_count(id):
			list.append({"kind": "unit", "unit": id})
	for i in inv.discs.size():
		list.append({"kind": "disc", "index": i})
	for id in Inventory.CONSUMABLES.keys() + Materials.ALL.keys():
		if inv.count(id) > 0:
			list.append({"kind": "stack", "id": id})
	# Anything else stacked (older saves): keep it visible so it can be dropped.
	for id in inv.consumables:
		if inv.count(id) > 0 and not Inventory.CONSUMABLES.has(id) and not Materials.ALL.has(id):
			list.append({"kind": "stack", "id": id})
	return list


func _satchel_entries() -> Array[Dictionary]:
	var list: Array[Dictionary] = [{"kind": "oro"}]
	var p := _player()
	if p:
		for color in Inventory.LUMIDIUM:
			if int(p.carried_lumidium.get(color, 0)) > 0:
				list.append({"kind": "lumidium", "color": color})
	return list


func entry_text(e: Dictionary) -> String:
	var save := _save()
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
			return "%s%s  (%s %s)" % ["[W] " if e.worn else "", a.display_name, ArmorData.SLOT_NAMES[a.slot], a.weight_name()]
		"unit":
			return "Augment: %s" % UnitBook.display_name(e.unit)
		"disc":
			var d: Dictionary = save.inventory.discs[e.index]
			var spell := SpellBook.get_spell(StringName(d.id))
			return "Disc: %s %d" % [spell.display_name if spell else String(d.id), int(d.level)]
		"stack":
			return "%s x%d" % [Inventory.item_name(e.id), save.inventory.count(e.id)]
		"oro":
			return "Oro  %d" % save.inventory.oro
		"lumidium":
			return "%s Lumidium x%d" % [String(e.color).capitalize(), int(_player().carried_lumidium.get(e.color, 0))]
	return "?"


func _entry_color(e: Dictionary) -> Color:
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
		"oro":
			return Color(1.0, 0.85, 0.35)
		"lumidium":
			return Inventory.LUMIDIUM_COLORS.get(e.color, Color.WHITE)
	return Color.WHITE


func describe(e: Dictionary) -> String:
	var save := _save()
	var p := _player()
	match e.kind:
		"weapon":
			var w: WeaponData = e.weapon
			var on := save.palettes_with(w)
			var lines := PackedStringArray([w.display_name + ("  (RARE)" if w.rare else ""), Loot.describe(w),
				"Jobs: %s   %s%s" % [w.jobs_text(), "Heavy" if w.is_heavy() else "Light", ", two-handed" if w.two_handed else ""]])
			lines.append("On palette %s." % ", ".join(Array(on).map(func(n: int) -> String: return str(n))) if not on.is_empty() else "Not on a palette.")
			if not w.can_be_used_by(menu.combat.job_code):
				lines.append("Your job can't use it.")
			return "\n".join(lines)
		"armor":
			var a: ArmorData = e.armor
			var text := "%s%s\n%s" % [a.display_name, "  (RARE)" if a.rare else "", a.summary()]
			if e.worn:
				text += "\nWorn."
			else:
				var error := ArmorBook.equip_error(save.character, a)
				if error != "":
					text += "\nCan't wear: " + error
			return text
		"unit":
			return "%s\n%s\nGoes in an augment slot of worn armor." % [UnitBook.display_name(e.unit), UnitBook.describe(e.unit)]
		"disc":
			var d: Dictionary = save.inventory.discs[e.index]
			var spell := SpellBook.get_spell(StringName(d.id))
			if spell == null:
				return "Unknown disc"
			var error := save.character.learn_error(spell, int(d.level), p.learning_stat(spell))
			return "%s %d (%s)\n%s" % [spell.display_name, int(d.level), spell.element_name(),
				"Can be read now." if error == "" else error]
		"stack":
			var id: StringName = e.id
			var have := "You have %d (stacks of %d take one slot)." % [save.inventory.count(id), Inventory.STACK_MAX]
			if Materials.ALL.has(id):
				return "%s\n+%d %s, permanently. Used: %s.\n%s" % [Materials.display_name(id), int(Materials.PER_USE),
					Materials.stat_label(id), Materials.limit_text(save.character, Materials.pool_of(id)), have]
			return "%s\n%s\n%s" % [Inventory.item_name(id), USE_TEXT.get(id, ""), have]
		"oro":
			return "Oro: %d (up to %d). In the satchel: it never fills your pack." % [save.inventory.oro, Inventory.ORO_MAX]
		"lumidium":
			return "Carried Lumidium: %d / %d (all colors together), lost if you fall.\nTeleporters bank it. Banked: %d." % [
				p.carried_lumidium_total(), Inventory.SATCHEL_LUMIDIUM, save.inventory.lumidium_total()]
	return ""


# --- Refresh ---------------------------------------------------------------------

func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func refresh() -> void:
	var save := _save()
	if save == null or _list == null:
		return
	_header.text = "Pack  %d / %d%s" % [save.pack_used(), Inventory.PACK_SLOTS, "  (no limit: debug)" if Inventory.unlimited else ""]
	_clear(_list)
	var list := entries()
	for i in list.size():
		_list.add_child(_entry_button(list[i], i))
	if list.is_empty():
		_list.add_child(_label("Empty.", 15))
	_clear(_satchel)
	var satchel := _satchel_entries()
	for e in satchel:
		_satchel.add_child(_entry_button(e, -1))
	var p := _player()
	_satchel.add_child(_label("Lumidium carried %d / %d   banked %d" % [p.carried_lumidium_total(),
		Inventory.SATCHEL_LUMIDIUM, save.inventory.lumidium_total()], 14))
	if _open.is_empty():
		_close_actions()


func _entry_button(e: Dictionary, index: int) -> Button:
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = entry_text(e)
	b.modulate = _entry_color(e)
	b.set_meta("entry", e)
	b.set_meta("index", index)
	b.focus_entered.connect(func():
		if index >= 0:
			_focus_index = index
		if _open.is_empty():
			_detail.text = describe(e))
	b.pressed.connect(_open_actions.bind(e, b))
	return b


# --- Actions ----------------------------------------------------------------------

func _close_actions() -> void:
	_open = {}
	_clear(_actions)
	_actions_title.text = ""


func _action(text: String, callback: Callable, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if not enabled:
		b.modulate = Color(1, 1, 1, 0.5)  # still focusable: A explains
	b.pressed.connect(callback)
	_actions.add_child(b)
	return b


## Lists what can be done with an entry, PSO-style.
func _open_actions(e: Dictionary, _from: Button) -> void:
	_close_actions()
	_open = e
	_detail.text = describe(e)
	_actions_title.text = entry_text(e)
	var save := _save()
	var palette := menu.combat.loadout_index
	match e.kind:
		"weapon":
			var w: WeaponData = e.weapon
			if w.two_handed:
				_action("Equip to palette %d (both hands)" % (palette + 1), _equip_weapon.bind(w, CombatController.Hand.PRIMARY))
			else:
				_action("Equip to palette %d, primary (X)" % (palette + 1), _equip_weapon.bind(w, CombatController.Hand.PRIMARY))
				_action("Equip to palette %d, off hand (Y)" % (palette + 1), _equip_weapon.bind(w, CombatController.Hand.OFF))
			if not save.palettes_with(w).is_empty():
				_action("Take it off every palette", _unequip_weapon.bind(w))
			_action("Drop", _drop.bind(e, 1), save.palettes_with(w).is_empty())
		"armor":
			var a: ArmorData = e.armor
			if e.worn:
				_action("Take off", _take_off.bind(a))
			else:
				_action("Wear (%s)" % ArmorData.SLOT_NAMES[a.slot], _wear.bind(a), ArmorBook.equip_error(save.character, a) == "")
			_action("Drop", _drop.bind(e, 1), not e.worn)
		"unit":
			var any := false
			for piece in ArmorBook.equipped(save.character):
				piece.ensure_units()
				var free := piece.units.find(&"")
				if free >= 0:
					any = true
					_action("Slot into %s (slot %d)" % [piece.display_name, free + 1], _slot_unit.bind(e.unit, piece, free))
			if not any:
				_action("No free augment slot (Equip > Armor to swap one)", func(): _message.text = "Every slot in your worn armor is full.", false)
			_action("Drop", _drop.bind(e, 1))
		"disc":
			_action("Read", _read_disc.bind(e.index))
			_action("Drop", _drop.bind(e, 1))
		"stack":
			var id: StringName = e.id
			if Materials.ALL.has(id):
				_action("Use (+%d %s)" % [int(Materials.PER_USE), Materials.stat_label(id)], _use_material.bind(id),
					Materials.use_error(save.character, id) == "")
			elif USE_TEXT.has(id):
				_action("Use", _use_item.bind(id))
			_amount_actions(e, save.inventory.count(id))
		"oro":
			_amount_actions(e, save.inventory.oro)
		"lumidium":
			_amount_actions(e, int(_player().carried_lumidium.get(e.color, 0)))
	if e.kind == "oro" or e.kind == "lumidium":
		_focus_last(_actions)  # straight to "Drop"
	else:
		_focus_first(_actions)


## Drop with an amount: - / + buttons (Oro also gets bigger steps), All, then
## Drop. The row's focus neighbors are set by hand: the full-width buttons
## above and below would otherwise catch d-pad left / right.
func _amount_actions(e: Dictionary, have: int) -> void:
	if have <= 0:
		_action("Nothing to drop", func(): pass, false)
		return
	_amount = 1 if e.kind != "oro" else mini(have, 100)
	if have == 1:
		_action("Drop", _drop.bind(e, 1))
		return
	var above: Button = null
	for child in _actions.get_children():
		if child is Button:
			above = child
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var steps := [-100, -10, -1, 1, 10, 100] if e.kind == "oro" else [-1, 1]
	_amount_label = _label("", 18)
	_amount_label.custom_minimum_size.x = 70.0
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var buttons: Array[Button] = []
	for step in steps:
		if step > 0 and _amount_label.get_parent() == null:
			row.add_child(_amount_label)
		var b := Button.new()
		b.text = ("-" if step < 0 else "+") + (str(absi(step)) if absi(step) > 1 else "")
		b.custom_minimum_size.x = 44.0
		b.pressed.connect(func(): _set_amount(_amount + step, have))
		row.add_child(b)
		buttons.append(b)
	var all := Button.new()
	all.text = "All"
	all.pressed.connect(func(): _set_amount(have, have))
	row.add_child(all)
	buttons.append(all)
	_actions.add_child(row)
	_set_amount(_amount, have)
	var drop := _action("Drop this many", func(): _drop(e, _amount))
	var plus: Button = buttons[steps.find(1)]
	for i in buttons.size():
		var b := buttons[i]
		b.focus_neighbor_left = b.get_path_to(buttons[maxi(i - 1, 0)])
		b.focus_neighbor_right = b.get_path_to(buttons[mini(i + 1, buttons.size() - 1)])
		b.focus_neighbor_top = b.get_path_to(above if above else b)
		b.focus_neighbor_bottom = b.get_path_to(drop)
	drop.focus_neighbor_top = drop.get_path_to(plus)
	if above:
		above.focus_neighbor_bottom = above.get_path_to(plus)


func _set_amount(value: int, have: int) -> void:
	_amount = clampi(value, 1, have)
	if _amount_label:
		_amount_label.text = str(_amount)


## B: closes the actions (back to the list). False when they weren't open.
func back() -> bool:
	if _open.is_empty():
		return false
	var e := _open
	_close_actions()
	_detail.text = describe(e)
	_refocus(e)
	return true


func _after(text: String, refocus: Dictionary = {}) -> void:
	_message.text = text
	var p := _player()
	if p:
		p.apply_bonuses()
	_close_actions()
	menu._refresh()
	_refocus(refocus)


func _refocus(e: Dictionary) -> void:
	if not e.is_empty() and (e.kind == "oro" or e.kind == "lumidium"):
		for b in _satchel.get_children():
			if b is Button and not b.is_queued_for_deletion() and (b.get_meta("entry") as Dictionary).kind == e.kind \
					and (e.kind == "oro" or (b.get_meta("entry") as Dictionary).color == e.color):
				_grab.call_deferred(b)
				return
		_focus_first(_satchel)
		return
	focus_default()


func _equip_weapon(w: WeaponData, hand: int) -> void:
	if not w.can_be_used_by(menu.combat.job_code):
		_message.text = "%s needs %s." % [w.display_name, w.jobs_text()]
		return
	var index := menu.combat.loadout_index
	var error := menu.equip(index, hand, w)
	if error == "":
		error = menu.combat.job_error(menu._set.loadouts[index])
	_after(error if error != "" else "%s is on palette %d (%s)." % [w.display_name, index + 1,
		"both hands" if w.two_handed else CombatController.hand_name(hand).to_lower()], _open)


func _unequip_weapon(w: WeaponData) -> void:
	_save().unequip_weapon(w)
	_after("%s is off every palette." % w.display_name, _open)


func _wear(a: ArmorData) -> void:
	var error := ArmorBook.equip(_save(), a)
	_after(error if error != "" else "Wearing %s." % a.display_name)


func _take_off(a: ArmorData) -> void:
	ArmorBook.unequip(_save(), a.slot)
	_after("Took off %s (it stays in your pack)." % a.display_name)


func _slot_unit(id: StringName, piece: ArmorData, index: int) -> void:
	var error := ArmorBook.insert_unit(_save(), piece, index, id)
	_after(error if error != "" else "%s slotted into %s." % [UnitBook.display_name(id), piece.display_name])


func _read_disc(index: int) -> void:
	_after(_player().read_stored_disc(index))


func _use_material(id: StringName) -> void:
	_after(_player().use_material(id), _open if _save().inventory.count(id) > 1 else {})


func _use_item(id: StringName) -> void:
	var p := _player()
	var ok := p.use_consumable(id)
	var text := "Used %s." % Inventory.item_name(id) if ok else "No %s left." % Inventory.item_name(id)
	if ok and id == &"trap_scanner":
		text = "Trap Scanner used: traps in this room are visible."
	_after(text, _open if _save().inventory.count(id) > 0 else {})


## Drops `count` of an entry on the ground in front of the Seeker, as one
## stack (PSO-style).
func _drop(e: Dictionary, count: int) -> void:
	var p := _player()
	var save := _save()
	var inv := save.inventory
	var text := ""
	match e.kind:
		"weapon":
			var w: WeaponData = e.weapon
			if not save.palettes_with(w).is_empty():
				_message.text = "%s is on a palette: take it off first." % w.display_name
				return
			inv.weapons.erase(w)
			ItemPickup.drop_from(p, {"weapon": w})
			text = w.display_name
		"armor":
			var a: ArmorData = e.armor
			if e.worn:
				_message.text = "You're wearing it: take it off first."
				return
			inv.armors.erase(a)
			ItemPickup.drop_from(p, {"armor": a})
			text = a.display_name
		"unit":
			inv.take_unit(e.unit)
			ItemPickup.drop_from(p, {"unit": e.unit})
			text = UnitBook.display_name(e.unit)
		"disc":
			var d: Dictionary = inv.discs[e.index]
			inv.discs.remove_at(e.index)
			ItemPickup.drop_from(p, {"disc": d})
			text = "the disc"
		"stack":
			var id: StringName = e.id
			var n := inv.remove_consumable(id, count)
			ItemPickup.drop_from(p, {("material" if Materials.ALL.has(id) else "consumable"): id, "count": n})
			text = "%d %s" % [n, Inventory.item_name(id)]
		"oro":
			var n := mini(count, inv.oro)
			inv.oro -= n
			ItemPickup.drop_from(p, {"oro": n})
			text = "%d Oro" % n
		"lumidium":
			var n := p.remove_lumidium(e.color, count)
			ItemPickup.drop_from(p, {"lumidium": e.color, "count": n})
			text = "%d %s Lumidium" % [n, String(e.color).capitalize()]
	var keep := e if e.kind == "oro" or e.kind == "lumidium" or (e.kind == "stack" and inv.count(e.id) > 0) else {}
	_after("Dropped %s." % text, keep)


# --- Focus ------------------------------------------------------------------------

func focus_default() -> void:
	var buttons: Array = []
	for b in _list.get_children():
		if b is Button and not b.is_queued_for_deletion():
			buttons.append(b)
	if buttons.is_empty():
		_focus_first(_satchel)
		return
	_grab.call_deferred(buttons[clampi(_focus_index, 0, buttons.size() - 1)])


func _focus_first(box: Container) -> bool:
	for child in box.get_children():
		if child is Button and not child.is_queued_for_deletion():
			_grab.call_deferred(child)
			return true
		if child is HBoxContainer and _focus_first(child):
			return true
	return false


func _focus_last(box: Container) -> void:
	for i in range(box.get_child_count() - 1, -1, -1):
		var child := box.get_child(i)
		if child is Button and not child.is_queued_for_deletion():
			_grab.call_deferred(child)
			return


## Deferred focus that survives the list being rebuilt in the meantime.
func _grab(control: Control) -> void:
	if is_instance_valid(control) and control.is_inside_tree() and not control.is_queued_for_deletion():
		control.grab_focus()
