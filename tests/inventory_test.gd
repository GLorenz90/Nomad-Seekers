extends SceneTree
## Automated test for Part 9: the pack and the satchel (Grayson, 2026-11-09).
##
## - A new Seeker's pack: Sword, Pistol and Wand, palette 1 holding the pack's
##   own Pistol and Sword.
## - Stacks hold 10 and take one slot; picking up a stack takes only what
##   fits and leaves the rest lying.
## - The pack holds 30 slots (worn armor and palette weapons included); a full
##   pack refuses items but never Oro or Lumidium (the satchel).
## - The satchel carries up to 15 Lumidium, all colors together.
## - The Inventory tab with a gamepad: equip, use, wear, drop (stacks, Oro and
##   Lumidium in part, as one stack on the ground), and the PSO rule that
##   equipped and worn gear can't be dropped.
## - Dropped items wait for A, Oro and Lumidium included.
##
## Runs in scenes/arena.tscn with its rooms switched off.
##   godot --headless --path . --script res://tests/inventory_test.gd

const SPOT := Vector3(0.0, 0.1, 4.0)

var _main: Node
var _player: Player
var _menu: LoadoutMenu
var _tab: InventoryTab
var _failures := 0
var _messages: Array[String] = []


func _initialize() -> void:
	_main = load("res://scenes/arena.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_run.call_deferred()


func _run() -> void:
	_player = _main.get_node("Player")
	var save := SaveData.create("Tester", CharacterData.Race.HUMAN, CharacterData.Gender.FEMALE,
		CharacterData.Job.STRIKER, 1)
	_player.use_save(save)
	_player.autosave = false
	_menu = _main.loadout_menu
	_menu.save_on_close = false
	_tab = _menu._inventory_tab
	_player.item_collected.connect(func(t: String): _messages.append(t))
	for room in ["Rooms/RoomA", "Rooms/RoomB"]:
		(_main.get_node(room) as WaveRoom).state = WaveRoom.RoomState.CLEARED
	await _frames(20)
	var inv := save.inventory

	# --- A new Seeker's pack ----------------------------------------------------
	var names := inv.weapons.map(func(w: WeaponData) -> String: return w.display_name)
	_check("the pack starts with a Sword, a Pistol and a Wand (%s)" % ", ".join(names),
		names == ["Sword", "Pistol", "Wand"])
	var p1 := save.loadouts.loadouts[0]
	_check("palette 1 holds the pack's own Pistol (X) and Sword (Y)",
		p1.primary == inv.weapons[1] and p1.off_hand == inv.weapons[0])
	# 3 weapons + the worn Field Frame + 4 stacks (gel, cell, salt, scanner).
	_check("worn armor and palette weapons take slots (%d / %d used)" % [save.pack_used(), Inventory.PACK_SLOTS],
		save.pack_used() == 8)

	# --- Stacks: 10 at most; a pickup takes what fits ------------------------------
	inv.add_consumable(&"hp_gel", 7 - inv.count(&"hp_gel"))
	var gels: ItemPickup = _main.spawn_drop({"consumable": &"hp_gel", "count": 4}, SPOT + Vector3(0, 0, -2))
	await _place(SPOT + Vector3(0, 0, -2))
	await _tap("jump")
	await _frames(3)
	_check("7 HP Gels + a stack of 4: takes 3, up to 10 (%d)" % inv.count(&"hp_gel"), inv.count(&"hp_gel") == 10)
	_check("and 1 stays on the ground (%s)" % (gels.describe() if is_instance_valid(gels) else "gone"),
		is_instance_valid(gels) and not gels.is_queued_for_deletion() and gels.amount() == 1 and gels.describe() == "HP Gel")
	_check("the prompt says why (%s)" % _player.interact_prompt(), _player.interact_prompt().contains("10 max"))
	_check("one stack is one slot (still %d used)" % save.pack_used(), save.pack_used() == 8)
	gels.queue_free()

	# --- A full pack ---------------------------------------------------------------
	var filler: Array[WeaponData] = []
	while save.take_weapon(load("res://data/weapons/dagger.tres").duplicate()):
		filler.append(inv.weapons[-1])
	_check("the pack stops at 30 slots (%d)" % save.pack_used(), save.pack_used() == Inventory.PACK_SLOTS)
	var spear := load("res://data/weapons/spear.tres").duplicate() as WeaponData
	var lying: ItemPickup = _main.spawn_drop({"weapon": spear}, SPOT + Vector3(0, 0, -2))
	_main.spawn_drop({"oro": 40}, SPOT + Vector3(0.6, 0, -2))
	_main.spawn_drop({"material": &"power_material"}, SPOT + Vector3(-0.6, 0, -2))
	var oro := inv.oro
	await _place(SPOT + Vector3(0, 0, -2))
	await _frames(10)
	_check("Oro still goes in the satchel with the pack full (+%d)" % (inv.oro - oro), inv.oro == oro + 40)
	for i in 2:
		await _tap("jump")
		await _frames(3)
	_check("a full pack leaves the weapon and a new stack lying",
		not spear in inv.weapons and is_instance_valid(lying) and inv.count(&"power_material") == 0)
	_check("and says so (%s)" % _messages[-1], _messages[-1].contains("pack full"))
	inv.add_consumable(&"lp_cell", 1 - inv.count(&"lp_cell"))
	_main.spawn_drop({"consumable": &"lp_cell", "count": 2}, SPOT + Vector3(0, 0, -4))
	await _place(SPOT + Vector3(0, 0, -4))
	await _tap("jump")
	await _frames(3)
	_check("an existing stack still fills up with the pack full (LP Cell %d)" % inv.count(&"lp_cell"), inv.count(&"lp_cell") == 3)
	for w in filler:
		inv.weapons.erase(w)
	await _place(SPOT + Vector3(0, 0, -2))
	for i in 2:
		await _tap("jump")
		await _frames(3)
	_check("with room again, A picks them up", spear in inv.weapons and inv.count(&"power_material") == 1)

	# --- The satchel: 15 Lumidium, all colors together ------------------------------
	_main.spawn_drop({"lumidium": &"fire", "count": 10}, SPOT + Vector3(2, 0, -2))
	var ice: ItemPickup = _main.spawn_drop({"lumidium": &"ice", "count": 8}, SPOT + Vector3(2.4, 0, -2))
	await _place(SPOT + Vector3(2.2, 0, -2))
	await _frames(20)
	_check("walking over Lumidium fills the satchel to 15 (%d)" % _player.carried_lumidium_total(),
		_player.carried_lumidium_total() == Inventory.SATCHEL_LUMIDIUM)
	_check("the rest stays as one stack (%s)" % (ice.describe() if is_instance_valid(ice) else "gone"),
		is_instance_valid(ice) and ice.amount() == 3 and ice.describe() == "3 Ice Lumidium")
	_check("a full satchel doesn't stop pack pickups (%d / %d)" % [save.pack_used(), Inventory.PACK_SLOTS], save.pack_free() > 0)
	ice.queue_free()

	# --- The Inventory tab with a gamepad ----------------------------------------------
	await _place(SPOT)
	await _pad(JOY_BUTTON_START)
	await _frames(3)
	_check("the menu opens on the Inventory tab (%s)" % _focused_text(),
		_menu._tab_name() == "Inventory" and _tab._list.is_ancestor_of(_focused()))
	_check("the header counts the pack (%s)" % _tab._header.text, _tab._header.text.begins_with("Pack  %d / 30" % save.pack_used()))

	# Equip the Wand from the pack to palette 1's off hand.
	_player.combat.loadout_index = 0
	await _focus_entry("Wand")
	await _pad(JOY_BUTTON_A)
	_check("A opens the item's actions (%s)" % _focused_text(), _focused_text().begins_with("Equip to palette 1, primary"))
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	var wand := inv.weapons[2]
	_check("Equip to palette 1, off hand puts the Wand there (%s)" % _tab._message.text,
		save.loadouts.loadouts[0].off_hand == wand and save.loadouts.loadouts[0].primary.display_name == "Pistol")
	_check("the list marks it [P1] (%s)" % _focused_text(), _focused_text() == "Wand  [P1]")

	# Equipped gear can't be dropped (PSO).
	await _pad(JOY_BUTTON_A)
	await _focus_action("Drop")
	await _pad(JOY_BUTTON_A)
	_check("dropping an equipped weapon is refused (%s)" % _tab._message.text,
		wand in inv.weapons and _tab._message.text.contains("take it off first"))
	await _focus_action("Take it off every palette")
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	_check("Take it off every palette empties its hand", save.loadouts.loadouts[0].off_hand == null)
	var before := _pickups().size()
	await _pad(JOY_BUTTON_A)
	await _focus_action("Drop")
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	var new_pickups := _pickups().slice(before)
	_check("then it drops in front of the Seeker (%s)" % _tab._message.text,
		not wand in inv.weapons and new_pickups.size() == 1 and new_pickups[0].contents.get("weapon") == wand)

	# Use an HP Gel from the stack.
	_player.health.hp = _player.health.max_hp * 0.5
	await _focus_entry("HP Gel")
	await _pad(JOY_BUTTON_A)
	_check("a consumable's first action is Use (%s)" % _focused_text(), _focused_text() == "Use")
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	_check("Use heals and takes one (HP %d%%, %d left)" % [roundi(_player.health.hp / _player.health.max_hp * 100.0), inv.count(&"hp_gel")],
		_player.health.hp > _player.health.max_hp * 0.75 and inv.count(&"hp_gel") == 9)

	# Drop 3 of the stack with the d-pad alone: down to the amount row (+),
	# A twice, right and left along the row, down to Drop this many.
	await _focus_entry("HP Gel")
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	_check("d-pad down from Use reaches + (%s)" % _focused_text(), _focused_text() == "+")
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_A)
	_check("the amount goes up with + (%s)" % _tab._picker.label_text(), _tab._picker.label_text() == "3")
	await _pad(JOY_BUTTON_DPAD_LEFT)
	_check("d-pad left along the row reaches - (%s)" % _focused_text(), _focused_text() == "-")
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	_check("and right goes back past + to All, not up to Use (%s)" % _focused_text(), _focused_text() == "All")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	_check("down reaches Drop this many (%s)" % _focused_text(), _focused_text() == "Drop this many")
	before = _pickups().size()
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	new_pickups = _pickups().slice(before)
	_check("Drop this many leaves 6 and drops one stack of 3 (%s)" % (new_pickups[0].describe() if new_pickups.size() == 1 else "?"),
		inv.count(&"hp_gel") == 6 and new_pickups.size() == 1 and new_pickups[0].amount() == 3 and new_pickups[0].dropped)

	# Wear armor from the pack; worn armor can't be dropped.
	save.character.experience = Leveling.exp_for(60)  # the Lumen Hood needs level 60 (Part 11)
	_player.apply_bonuses()
	var hood := ArmorBook.make(&"lumen_hood")
	save.take_armor(hood)
	_menu._refresh()
	await _focus_entry("Lumen Hood")
	await _pad(JOY_BUTTON_A)
	_check("armor offers Wear (%s)" % _focused_text(), _focused_text().begins_with("Wear (Head)"))
	var used := save.pack_used()
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	_check("Wear puts it on, still in the pack's count (%d)" % save.pack_used(),
		save.character.head == hood and save.pack_used() == used)
	await _focus_entry("[W] Lumen Hood")
	await _pad(JOY_BUTTON_A)
	await _focus_action("Drop")
	await _pad(JOY_BUTTON_A)
	_check("worn armor can't be dropped (%s)" % _tab._message.text, save.character.head == hood)

	# Use a material from the pack.
	var str_before := _player.combat.stats.strength
	await _focus_entry("Power Material")
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	_check("Use on a material: STR +2 (%s)" % _tab._message.text,
		_player.combat.stats.strength == str_before + 2.0 and inv.count(&"power_material") == 0)

	# Oro: drop part of it, in one stack.
	inv.oro = 250
	_menu._refresh()
	var oro_button := _find_in(_tab._satchel, "Oro")
	oro_button.grab_focus()
	await _frames(2)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("Oro opens straight on Drop with 100 picked (%s, %s)" % [_focused_text(), _tab._picker.label_text()],
		_focused_text() == "Drop this many" and _tab._picker.label_text() == "100")
	before = _pickups().size()
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	new_pickups = _pickups().slice(before)
	var dropped_oro: ItemPickup = new_pickups[0] if new_pickups.size() == 1 else null
	_check("dropping Oro leaves 150 and one pile of 100", inv.oro == 150 and dropped_oro != null and int(dropped_oro.contents.oro) == 100)

	# Lumidium: drop 4 Fire.
	var lum_button := _find_in(_tab._satchel, "Fire Lumidium")
	lum_button.grab_focus()
	await _frames(2)
	await _pad(JOY_BUTTON_A)
	await _focus_action("+")
	for i in 3:
		await _pad(JOY_BUTTON_A)
	await _focus_action("Drop this many")
	before = _pickups().size()
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	new_pickups = _pickups().slice(before)
	var dropped_lum: ItemPickup = new_pickups[0] if new_pickups.size() == 1 else null
	_check("dropping 4 Fire Lumidium makes one stack (%s)" % (dropped_lum.describe() if dropped_lum else "?"),
		dropped_lum != null and dropped_lum.describe() == "4 Fire Lumidium" and _player.carried_lumidium_total() == 11)
	await _pad(JOY_BUTTON_B)
	await _pad(JOY_BUTTON_B)
	await _frames(3)
	_check("B backs out of the actions, then closes the menu", not _menu.visible)

	# Dropped Oro and Lumidium wait for A.
	await _frames(5)
	dropped_lum.global_position = _player.global_position
	dropped_oro.global_position = _player.global_position + Vector3(0.3, 0, 0)
	await _frames(20)
	_check("walking over what you dropped doesn't take it back",
		inv.oro == 150 and _player.carried_lumidium_total() == 11 and is_instance_valid(dropped_lum))
	_player.hold_input(0.0)
	for i in 2:
		await _tap("jump")
		await _frames(3)
	_check("A picks it up again (Oro %d, Lumidium %d)" % [inv.oro, _player.carried_lumidium_total()],
		inv.oro == 250 and _player.carried_lumidium_total() == 15)

	# --- Palettes only take weapons from the pack ----------------------------------------
	_menu.open()
	_menu.show_tab("Palette")
	await _frames(3)
	_menu._on_slot_pressed(1, CombatController.Hand.PRIMARY)
	var listed := []
	for child in _menu._picker_list.get_children():
		if child is Button:
			listed.append((child as Button).text.get_slice("  (", 0))
	_check("the palette picker lists the pack's weapons (%s)" % ", ".join(listed),
		listed.size() == inv.weapons.size() + 1 and "Spear" in listed and not "Wand" in listed)
	_menu.close()

	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- Helpers ---------------------------------------------------------------------------

func _pickups() -> Array[ItemPickup]:
	var list: Array[ItemPickup] = []
	for child in _main.get_children():
		if child is ItemPickup and not child.is_queued_for_deletion():
			list.append(child)
	return list


## Moves focus through the pack list with the d-pad until an entry starts with `prefix`.
func _focus_entry(prefix: String) -> void:
	_tab.focus_default()
	await _frames(2)
	for dir in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]:
		for i in 40:
			if _focused_text().begins_with(prefix):
				return
			await _pad(dir)


func _focus_action(prefix: String) -> void:
	var b := _find_in(_tab._actions, prefix)
	if b:
		b.grab_focus()
	await _frames(2)


func _find_in(node: Node, prefix: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text.begins_with(prefix):
			return child
		var inner := _find_in(child, prefix)
		if inner:
			return inner
	return null


func _place(at: Vector3) -> void:
	_player.global_position = at
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _frames(10)


func _focused() -> Control:
	return root.gui_get_focus_owner()


func _focused_text() -> String:
	var f := _focused()
	if f is Button:
		return (f as Button).text.strip_edges()
	return ""


## A real joypad button press and release.
func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		e.device = 0
		Input.parse_input_event(e)
		await process_frame
		await process_frame


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await physics_frame
	await physics_frame
	Input.action_release(action)
	await physics_frame
	await physics_frame


func _check(label: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + label)
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
