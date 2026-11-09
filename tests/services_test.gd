extends SceneTree
## Automated test for Part 10: Nomad-2's counters (Grayson, 2026-11-09).
##
## - Five clerks in the hub: Guild and bank (west), weapons, armor and
##   curatives shops (east), each opened with A.
## - Shops: PSO's tool prices for curatives, stock rolled per visit (no
##   rares), buying gear and stacks (with an amount) with a gamepad, not
##   enough Oro, a full pack, selling back at 1/8 (palette weapons and worn
##   armor refused).
## - Bank: 200 slots, deposit and withdraw items and stacks, Oro both ways,
##   kept in the save.
## - Guild: accept, one quest at a time, the teleporter listing the quest
##   first, progress from defeats, room clears and banked Lumidium, report
##   for the reward, abandon.
## - Start doesn't open the pause menu over a counter; B backs out.
##   godot --headless --path . --script res://tests/services_test.gd

const TEST_SAVE := "user://services_test_save.tres"

var _main: Node
var _player: Player
var _save: SaveData
var _failures := 0


func _initialize() -> void:
	_main = load("res://scenes/hub.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_run.call_deferred()


func _run() -> void:
	_player = _main.get_node("Player")
	_save = SaveData.create("Tester", CharacterData.Race.HUMAN, CharacterData.Gender.MALE,
		CharacterData.Job.RANGER, 0)
	_player.use_save(_save)
	_player.autosave = false
	await _frames(20)
	var inv := _save.inventory

	# --- The hub's clerks -----------------------------------------------------------
	var clerks := {}
	for node in get_nodes_in_group("service_counters"):
		clerks[(node as ServiceCounter).service] = node
	_check("Nomad-2 has five clerks (%d)" % clerks.size(), clerks.size() == 5)
	var weapons: ServiceCounter = clerks[ServiceCounter.Service.WEAPONS]
	var armor: ServiceCounter = clerks[ServiceCounter.Service.ARMOR]
	var curatives: ServiceCounter = clerks[ServiceCounter.Service.CURATIVES]
	var bank: ServiceCounter = clerks[ServiceCounter.Service.BANK]
	var guild: ServiceCounter = clerks[ServiceCounter.Service.GUILD]
	weapons.roll_stock(1)  # shops roll on first open, for the Seeker's level (Part 11)
	armor.roll_stock(1)
	await _place(curatives.global_position)
	_check("standing at a counter shows the A prompt (%s)" % _player.interact_prompt(),
		_player.interact_prompt() == "A: Shop: Curatives")

	# --- Prices ---------------------------------------------------------------------------
	_check("curatives use PSO's tool prices (Monomate 50, Monofluid 100, Sol Atomizer 300, Trap Vision 100)",
		Prices.CURATIVES == {&"hp_gel": 50, &"lp_cell": 100, &"cure_salt": 300, &"trap_scanner": 100})
	var pistol := load("res://data/weapons/pistol.tres") as WeaponData
	var great := load("res://data/weapons/great_sword.tres") as WeaponData
	_check("weapon prices: Pistol %d, Great Sword %d (two-handed costs more)" % [Prices.weapon_price(pistol), Prices.weapon_price(great)],
		Prices.weapon_price(pistol) == 500 and Prices.weapon_price(great) > Prices.weapon_price(pistol))
	var rare_count := 0
	for w in weapons.stock_weapons:
		if w.rare:
			rare_count += 1
	var tiers_ok := true
	for a in armor.stock_armor:
		tiers_ok = tiers_ok and a.tier == 1 and not a.rare
	_check("stock: %d weapons, %d armor, %d augments, no rares, armor tier 1 at level 1" % [weapons.stock_weapons.size(),
		armor.stock_armor.size(), armor.stock_units.size()],
		weapons.stock_weapons.size() == Prices.WEAPON_STOCK and rare_count == 0 and tiers_ok
		and armor.stock_armor.size() == Prices.ARMOR_STOCK and armor.stock_units.size() == Prices.UNIT_STOCK)
	var first_roll := weapons.stock_weapons.map(func(w: WeaponData) -> String: return w.display_name)
	weapons.roll_stock()
	_check("a new visit rolls new stock", weapons.stock_weapons.map(func(w: WeaponData) -> String: return w.display_name) != first_roll)

	# --- Curatives with a gamepad ----------------------------------------------------------------
	inv.oro = 1000
	_player.hold_input(0.0)
	await _tap("jump")
	await _frames(3)
	var menu := curatives.menu
	_check("A opens the counter and pauses (%s)" % _focused_text(), is_instance_valid(menu) and paused and _focused_text() == "Buy")
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("A on Buy lists the stock, first item focused (%s)" % _focused_text(), _focused_text().begins_with("HP Gel   50 Oro"))
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("A on HP Gel offers to buy one (%s)" % _focused_text(), _focused_text() == "Buy 1 for 50 Oro")
	await _pad(JOY_BUTTON_DPAD_UP)
	_check("up reaches the amount's + (%s)" % _focused_text(), _focused_text() == "+")
	for i in 3:
		await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	_check("+ three times: Buy 4 for 200 Oro (%s)" % _focused_text(), _focused_text() == "Buy 4 for 200 Oro")
	var gels := inv.count(&"hp_gel")
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("buying 4 HP Gels costs 200 Oro (%d -> %d gels, %d Oro)" % [gels, inv.count(&"hp_gel"), inv.oro],
		inv.count(&"hp_gel") == gels + 4 and inv.oro == 800)
	_check("the amount stops at what fits in the stack (%d more)" % _save.stack_room(&"hp_gel"), _save.stack_room(&"hp_gel") == Inventory.STACK_MAX - gels - 4)
	# Not enough Oro.
	inv.oro = 100
	menu.show_command("buy")
	await _frames(2)
	var salt := menu.list_buttons()[2]
	salt.grab_focus()
	await _frames(2)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("not enough Oro: A explains (%s)" % menu._message.text, menu._message.text.begins_with("You don't have enough Oro"))
	# Start leaves the counter, and doesn't open the pause menu.
	await _pad(JOY_BUTTON_START)
	await _frames(3)
	_check("Start leaves the counter without opening the pause menu",
		not is_instance_valid(curatives.menu) and not paused and not _main.loadout_menu.visible)

	# --- Weapons: buy and sell ------------------------------------------------------------------
	inv.oro = 5000
	menu = weapons.open_menu(_player)
	await _frames(2)
	menu.show_command("buy")
	await _frames(2)
	var stock_w: WeaponData = weapons.stock_weapons[0]
	var price := Prices.weapon_price(stock_w)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("a weapon's offer shows its price (%s)" % _focused_text(), _focused_text() == "Buy for %s Oro" % CounterMenu._num(price))
	var weapons_before := inv.weapons.size()
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	var bought := inv.weapons[-1]
	_check("buying puts a copy in the pack and costs its price (%d Oro left)" % inv.oro,
		inv.weapons.size() == weapons_before + 1 and bought != stock_w and bought.display_name == stock_w.display_name
		and inv.oro == 5000 - price)
	_check("the stock can be bought again (still %d listed)" % weapons.stock_weapons.size(), weapons.stock_weapons.size() == Prices.WEAPON_STOCK)
	# Sell: the Wand (not on a palette) and the Pistol (on palette 1).
	menu.show_command("sell")
	await _frames(2)
	var pistol_button: Button = null
	for b in menu.list_buttons():
		if b.text.begins_with("Pistol"):
			pistol_button = b
	pistol_button.grab_focus()
	await _frames(2)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("a palette weapon can't be sold (%s)" % menu._message.text, menu._message.text.contains("palette"))
	var wand: WeaponData = inv.weapons[2]
	var oro := inv.oro
	for b in menu.list_buttons():
		if b.text.begins_with("Wand"):
			b.grab_focus()
	await _frames(2)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("selling the Wand pays 1/8 of its price (+%d Oro)" % (inv.oro - oro),
		not wand in inv.weapons and inv.oro - oro == floori(Prices.weapon_price(wand) / 8.0))
	# Sell 2 HP Gels from the stack.
	gels = inv.count(&"hp_gel")
	oro = inv.oro
	menu.show_command("sell")
	await _frames(2)
	for b in menu.list_buttons():
		if b.text.begins_with("HP Gel"):
			b.grab_focus()
	await _frames(2)
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_DPAD_UP)
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	_check("selling a stack picks an amount (%s)" % _focused_text(), _focused_text() == "Sell 2 for 12 Oro")
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("selling 2 HP Gels pays 6 each (+%d)" % (inv.oro - oro), inv.count(&"hp_gel") == gels - 2 and inv.oro == oro + 12)
	await _pad(JOY_BUTTON_B)
	await _pad(JOY_BUTTON_B)
	await _pad(JOY_BUTTON_B)
	await _frames(3)
	_check("B backs out: list -> commands -> leave", not is_instance_valid(weapons.menu) and not paused)

	# --- Armor shop: a piece and an augment ----------------------------------------------------------
	inv.oro = 20000
	menu = armor.open_menu(_player)
	menu.show_command("buy")
	await _frames(2)
	var piece: ArmorData = armor.stock_armor[0]
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("buying armor puts a copy in the pack (%s)" % piece.display_name,
		inv.armors.size() == 1 and inv.armors[0].display_name == piece.display_name and inv.armors[0] != piece
		and inv.oro == 20000 - Prices.armor_price(piece))
	var unit_id: StringName = armor.stock_units[0]
	var buttons := menu.list_buttons()
	buttons[armor.stock_armor.size()].grab_focus()
	await _frames(2)
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("buying an augment (%s, %d Oro)" % [UnitBook.display_name(unit_id), Prices.unit_price(unit_id)], inv.unit_count(unit_id) == 1)
	# A full pack refuses gear.
	var filler: Array[WeaponData] = []
	while _save.take_weapon(pistol.duplicate()):
		filler.append(inv.weapons[-1])
	menu.show_command("buy")
	await _frames(2)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("a full pack: A explains (%s)" % menu._message.text, menu._message.text == "Your pack is full.")
	for w in filler:
		inv.weapons.erase(w)
	menu.close()
	await _frames(3)

	# --- Bank ---------------------------------------------------------------------------------------------
	menu = bank.open_menu(_player)
	await _frames(2)
	_check("the bank shows 200 slots (%s)" % menu._header.text.replace("\n", " / "), menu._header.text.contains("Bank 0 / 200"))
	menu.show_command("deposit")
	await _frames(2)
	for b in menu.list_buttons():
		if b.text.begins_with(bought.display_name):
			b.grab_focus()
	await _frames(2)
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("deposit a weapon: out of the pack, into the bank", not bought in inv.weapons and bought in _save.bank.weapons)
	for b in menu.list_buttons():
		if b.text.begins_with("HP Gel"):
			b.grab_focus()
	gels = inv.count(&"hp_gel")
	await _frames(2)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("a stack deposits all of it by default (%s)" % _focused_text(), _focused_text() == "Deposit %d" % gels)
	await _pad(JOY_BUTTON_DPAD_UP)
	await _pad(JOY_BUTTON_DPAD_LEFT)
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("deposit all but one HP Gel (%d in the bank, %d carried)" % [_save.bank.count(&"hp_gel"), inv.count(&"hp_gel")],
		_save.bank.count(&"hp_gel") == gels - 1 and inv.count(&"hp_gel") == 1)
	# Oro.
	inv.oro = 3000
	menu.show_command("oro")
	await _frames(2)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("Deposit Oro starts at everything you carry (%s)" % _focused_text(), _focused_text() == "Deposit 3,000 Oro")
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("deposit 3,000 Oro", inv.oro == 0 and _save.bank.oro == 3000)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("withdraw 1,000 Oro (carrying %d, banked %d)" % [inv.oro, _save.bank.oro], inv.oro == 1000 and _save.bank.oro == 2000)
	# Withdraw the weapon.
	menu.show_command("withdraw")
	await _frames(2)
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("withdraw the weapon back into the pack", bought in inv.weapons and not bought in _save.bank.weapons)
	menu.close()
	await _frames(3)
	ResourceSaver.save(_save, TEST_SAVE)
	var loaded := ResourceLoader.load(TEST_SAVE, "", ResourceLoader.CACHE_MODE_IGNORE) as SaveData
	_check("the bank is kept in the save (%d Oro, %d HP Gels)" % [loaded.bank.oro, loaded.bank.count(&"hp_gel")],
		loaded.bank.oro == 2000 and loaded.bank.count(&"hp_gel") == gels - 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

	# --- Guild ---------------------------------------------------------------------------------------------
	menu = guild.open_menu(_player)
	menu.show_command("quests")
	await _frames(2)
	_check("the Guild lists three quests (%s)" % _focused_text(), menu.list_buttons().size() == 3 and _focused_text().begins_with("Arena Trial"))
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("A on Hound Cull offers to accept it (%s)" % _focused_text(), _focused_text() == "Accept Hound Cull")
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("accepted (%s)" % menu._message.text, QuestBook.active(_save).get("id") == &"hound_cull")
	menu.list_buttons()[0].grab_focus()
	await _frames(2)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("one quest at a time (%s)" % menu._message.text, menu._message.text.begins_with("You're already on Hound Cull"))
	menu.show_command("report")
	await _frames(2)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("reporting early says what's left (%s)" % menu._message.text, menu._message.text.contains("0 / 6 Grub Hounds"))
	menu.close()
	await _frames(3)
	# The hub teleporter lists the quest first.
	var pad := _main.get_node("Teleporter") as Teleporter
	await _place(pad.global_position)
	_player.hold_input(0.0)
	await _tap("jump")
	await _frames(3)
	var listed := pad.picker.button_names() if pad.picker else PackedStringArray()
	_check("the teleporter lists the quest first (%s)" % ", ".join(listed), listed.size() > 0 and listed[0] == "Quest: Hound Cull (the test arena)")
	await _pad(JOY_BUTTON_B)
	await _frames(3)
	# Progress: defeats of the right enemy only.
	QuestBook.record(_save, "defeat", "sentry_drone")
	for i in 5:
		QuestBook.record(_save, "defeat", "grub_hound")
	_check("defeats count for the quest's enemy only (%s)" % QuestBook.progress_text(_save), QuestBook.progress(_save) == 5)
	_check("the sixth completes it", QuestBook.record(_save, "defeat", "grub_hound") and QuestBook.is_complete(_save))
	inv.oro = 0
	menu = guild.open_menu(_player)
	menu.show_command("report")
	await _frames(2)
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("Report pays the reward (%s)" % menu._message.text, inv.oro == 300 and QuestBook.active(_save).is_empty()
		and int(_save.quests_cleared.get("hound_cull", 0)) == 1)
	# Abandon.
	QuestBook.accept(_save, &"crystal_survey")
	menu.show_command("abandon")
	await _frames(2)
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check("Abandon quest drops it", QuestBook.active(_save).is_empty())
	menu.close()
	await _frames(3)

	# --- Quest progress in the arena ----------------------------------------------------------------------
	_main.queue_free()
	await _frames(3)
	_main = load("res://scenes/arena.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await _frames(10)
	_player = _main.get_node("Player")
	_player.use_save(_save)
	_player.autosave = false
	await _frames(10)
	QuestBook.accept(_save, &"arena_trial")
	for room in get_nodes_in_group("wave_rooms"):
		(room as WaveRoom).state = WaveRoom.RoomState.CLEARED
	_main._check_all_rooms_cleared()
	_check("clearing every arena room completes Arena Trial", QuestBook.is_complete(_save))
	QuestBook.report(_save)
	QuestBook.accept(_save, &"crystal_survey")
	_player.add_lumidium(&"fire", 6)
	_player.deposit_lumidium()
	_check("banking Lumidium counts (%s)" % QuestBook.progress_text(_save), QuestBook.progress(_save) == 6)
	_player.add_lumidium(&"ice", 5)
	_player.deposit_lumidium()
	_check("and 10 completes Crystal Survey", QuestBook.is_complete(_save))

	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- Helpers ---------------------------------------------------------------------------

func _place(at: Vector3) -> void:
	_player.global_position = at + Vector3(0, 0.1, 0)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _frames(10)


func _focused() -> Control:
	return root.gui_get_focus_owner()


func _focused_text() -> String:
	var f := _focused()
	if f is Button:
		return (f as Button).text.strip_edges().trim_prefix("> ")
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
		await process_frame
