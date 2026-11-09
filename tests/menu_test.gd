extends SceneTree
## Automated test: every menu tab works with a gamepad alone (A accepts, B goes
## back or closes, d-pad moves, LB / RB switch tabs, Start opens and closes),
## pairing an already-paired SyncAIDa doesn't error, and the Levels tab's
## tools and level switch work. Sends real joypad button events.
##
## Run from the project folder:
##   godot --headless --path . --script res://tests/menu_test.gd

var _main: Node
var _player: Player
var _menu: LoadoutMenu
var _failures := 0


func _initialize() -> void:
	_main = load("res://scenes/arena.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_run.call_deferred()


func _run() -> void:
	_player = _main.get_node("Player")
	_player.use_save(SaveData.fresh(CombatController.make_default_loadouts()))
	_player.autosave = false
	_menu = _main.loadout_menu
	_menu.save_on_close = false
	await _frames(20)

	# Open with Start: no SyncAIDa yet, so it opens on the SyncAIDa tab.
	await _pad(JOY_BUTTON_START)
	_check("Start opens the menu and pauses", _menu.visible and paused)
	_check("with no SyncAIDa it opens on the SyncAIDa tab, a starter focused (%s)" % _focus_name(),
		_tab() == "SyncAIDa" and _focused_text().begins_with("Aegi"))
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_A)
	_check("d-pad down + A picks Kindle", _player.syncaida.data != null and _player.syncaida.data.display_name == "Kindle")
	await _frames(3)
	_check("focus moves to the paired SyncAIDa (%s)" % _focused_text(), _focused_text().contains("Kindle"))
	# The reported bug: pressing the already-paired SyncAIDa freed a locked button.
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	_check("pressing the paired SyncAIDa again keeps it paired and focused (%s)" % _focused_text(),
		_player.save.paired == 0 and _focused_text().contains("Kindle"))

	# Feed with the gamepad: move right into the feed column.
	var gels := _player.save.inventory.count(&"hp_gel")
	# Right twice: past the burst dropdown into the feed column, then up to HP Gel.
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	_check("d-pad right crosses into the feed column (%s)" % _focused_text(), _focused_text().contains("Lumidium"))
	for i in 12:
		if _focused_text().begins_with("HP Gel"):
			break
		await _pad(JOY_BUTTON_DPAD_UP)
	await _pad(JOY_BUTTON_A)
	_check("d-pad reaches the feed buttons and A feeds (HP Gel %d -> %d)" % [gels, _player.save.inventory.count(&"hp_gel")],
		_player.save.inventory.count(&"hp_gel") == gels - 1)

	# Loadouts: RB from SyncAIDa wraps to Levels, Controls, then Loadouts.
	for i in 10:
		if _tab() == "Loadouts":
			break
		await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(3)
	_check("RB switches tabs and focus follows (Loadouts, %s)" % _focus_name(), _tab() == "Loadouts" and _focused() is Button)
	_check("focus starts on loadout 1's primary hand, the first column", _focused() == _menu._slot_buttons[0][CombatController.PRIMARY])
	await _pad(JOY_BUTTON_A)
	_check("A on a hand opens the weapon picker", _menu._picker.visible and _menu._picker_list.is_ancestor_of(_focused()))
	await _pad(JOY_BUTTON_B)
	_check("B closes only the picker", _menu.visible and not _menu._picker.visible and _focused() == _menu._slot_buttons[0][1])
	await _pad(JOY_BUTTON_A)
	var listed := []
	for child in _menu._picker_list.get_children():
		if child is Button:
			listed.append((child as Button).text.get_slice("  (", 0))
	_check("the picker lists all 41 weapons, Gunblade and Burstbow included (%d)" % (listed.size() - 1),
		listed.size() - 1 == 41 and "Burstbow" in listed and "Gunblade" in listed)
	for i in 30:
		if _focused_text().begins_with("Arbalest"):  # Ranger only
			break
		await _pad(JOY_BUTTON_DPAD_DOWN)
	_menu._message.text = ""
	await _pad(JOY_BUTTON_A)
	_check("A on a job-locked weapon explains the lock and keeps the picker open (%s)" % _menu._message.text,
		_menu._picker.visible and _menu._message.text.contains("needs"))
	for i in 40:
		if _focused_text().begins_with("Dagger"):
			break
		await _pad(JOY_BUTTON_DPAD_UP)
	for i in 40:
		if _focused_text().begins_with("Dagger"):
			break
		await _pad(JOY_BUTTON_DPAD_DOWN)
	var picked := _focused_text()
	await _pad(JOY_BUTTON_A)
	var right := _menu._set.loadouts[0].right
	_check("d-pad + A equips a weapon (%s)" % picked, right != null and picked.begins_with(right.display_name)
		and not _menu._picker.visible)

	# Testing helpers: X unequips the focused hand, Y the whole loadout.
	_menu._set.loadouts[0].left = load("res://data/weapons/sword.tres")
	_menu._refresh()
	_menu._slot_buttons[0][1].grab_focus()
	await _pad(JOY_BUTTON_X)
	_check("X unequips the focused hand only", _menu._set.loadouts[0].right == null and _menu._set.loadouts[0].left != null)
	await _pad(JOY_BUTTON_Y)
	_check("Y clears the whole loadout", _menu._set.loadouts[0].is_empty())
	_menu._clear_all_loadouts()
	var all_empty := true
	for l in _menu._set.loadouts:
		all_empty = all_empty and l.is_empty()
	_check("Clear all loadouts empties every slot", all_empty)
	_menu._set = CombatController.make_default_loadouts()
	_menu._refresh()

	# Every other tab gets focus.
	for name in ["Inventory", "Character", "SyncAIDa", "Levels"]:
		while _tab() != name:
			await _pad(JOY_BUTTON_RIGHT_SHOULDER)
		await _frames(3)
		_check("%s tab: something is focused (%s)" % [name, _focus_name()], _focused() != null and (_menu._tabs.get_current_tab_control() == _focused()
			or _menu._tabs.get_current_tab_control().is_ancestor_of(_focused())))
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	await _frames(3)
	_check("LB goes back (Character)", _tab() == "Character")
	var old_name := _player.save.character.seeker_name
	_check("Character tab starts on the New name button (%s)" % _focused_text(), _focused_text() == "New name")
	await _pad(JOY_BUTTON_A)
	_check("New name changes the name with A (%s -> %s)" % [old_name, _player.save.character.seeker_name],
		_player.save.character.seeker_name != old_name)
	await _pad(JOY_BUTTON_DPAD_DOWN)  # race
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	var popup := (_focused() as OptionButton).get_popup() if _focused() is OptionButton else null
	_check("A opens a dropdown", popup != null and popup.visible)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_A)
	await _frames(3)
	_check("d-pad + A picks from it (race %s)" % CharacterData.Race.keys()[_player.save.character.race],
		_player.save.character.race != CharacterData.Race.HUMAN and not popup.visible)

	# Character reset (testing).
	_player.save.character.experience = 750
	_menu._reset_character()
	_check("Reset character to level 1 sets EXP back to 0", _player.save.character.experience == 0)

	# SyncAIDa reset (testing): Kindle back to STR Lv 5 and nothing else.
	var kindle := _player.syncaida.data
	for i in 40:
		_player.syncaida.feed(&"ice", true)
	var str_before := _player.combat.stats.strength
	var dex_before := _player.combat.stats.dexterity
	_menu._reset_syncaida()
	_check("Reset to base stats: STR Lv 5 only, form Mote, no bursts (Lv %d %s)" % [kindle.level(), kindle.form],
		kindle.level() == 5 and kindle.stat_level(&"str") == 5 and kindle.form == "Mote" and kindle.bursts.is_empty())
	_check("and the Seeker loses the bonus it had gained (DEX %+.0f, STR %+.0f)" % [_player.combat.stats.dexterity - dex_before, _player.combat.stats.strength - str_before],
		_player.combat.stats.dexterity < dex_before)

	# Levels tab tools.
	while _tab() != "Levels":
		await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(3)
	var oro := _player.save.inventory.oro
	await _pad(JOY_BUTTON_DPAD_RIGHT)  # the testing tools column
	for i in 12:
		if _focused_text().begins_with("+1000 Oro"):
			break
		await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_A)
	_check("Levels tab: +1000 Oro with A (%d -> %d)" % [oro, _player.save.inventory.oro], _player.save.inventory.oro == oro + 1000)
	_menu._debug_toggle.button_pressed = true
	_check("the debug readout toggle shows the HUD panel", _main.hud.is_debug_visible())
	_menu._debug_toggle.button_pressed = false

	# B closes the menu.
	await _pad(JOY_BUTTON_B)
	_check("B closes the menu and unpauses", not _menu.visible and not paused)
	_check("no control keeps focus after closing", root.gui_get_focus_owner() == null)

	# Level switch: back to the test room.
	await _pad(JOY_BUTTON_START)
	_menu._on_level("res://scenes/main.tscn")
	await _frames(20)
	_check("level select loads the test room (%s)" % current_scene.scene_file_path,
		current_scene != null and current_scene.scene_file_path == "res://scenes/main.tscn" and not paused)

	# The gym's teleporter goes to the arena, which loads fresh.
	var gym := current_scene
	var gym_player: Player = gym.get_node("Player")
	gym_player.autosave = false
	var pad := gym.get_node("ArenaTeleporter") as Teleporter
	_check("the gym has a teleporter to the arena", pad != null and pad.destination == "res://scenes/arena.tscn")
	gym_player.global_position = pad.global_position + Vector3.UP * 0.1
	await _frames(10)
	_check("standing on it shows the A prompt (%s)" % gym_player.interact_prompt(),
		gym_player.interact_prompt().begins_with("A: To the arena"))
	await _pad(JOY_BUTTON_A)
	await _frames(30)
	_check("A on it loads the arena (%s)" % current_scene.scene_file_path,
		current_scene.scene_file_path == "res://scenes/arena.tscn")
	var arena := current_scene
	var arena_player: Player = arena.get_node("Player")
	arena_player.autosave = false
	var exit := arena.get_node("Gathering/TeleporterExit") as Teleporter
	_check("the arena loads fresh (rooms waiting)",
		(arena.get_node("Rooms/RoomA") as WaveRoom).state == WaveRoom.RoomState.WAITING)
	arena_player.global_position = exit.global_position + Vector3.UP * 0.1
	await _frames(20)
	await _pad(JOY_BUTTON_A)
	await _frames(20)
	_check("the arena's exit stays shut until every room is cleared (%s)" % arena_player.interact_prompt(),
		current_scene == arena and not exit.is_active())
	arena_player.global_position = Vector3(0, 0.1, 20)
	await _frames(10)
	for room in ["Rooms/RoomA", "Rooms/RoomB"]:
		(arena.get_node(room) as WaveRoom).state = WaveRoom.RoomState.CLEARED
	await _frames(5)
	arena_player.global_position = exit.global_position + Vector3.UP * 0.1
	await _frames(10)
	await _pad(JOY_BUTTON_A)
	await _frames(30)
	_check("once cleared it returns to Nomad-2 (%s)" % current_scene.scene_file_path,
		current_scene.scene_file_path == "res://scenes/hub.tscn")

	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _tab() -> String:
	return String(_menu._tabs.get_current_tab_control().name)


func _focused() -> Control:
	return root.gui_get_focus_owner()


func _focus_name() -> String:
	var f := _focused()
	if f == null:
		return "nothing"
	return "%s '%s'" % [f.get_class(), _focused_text()]


func _focused_text() -> String:
	var f := _focused()
	if f is Button:
		return (f as Button).text.strip_edges().trim_prefix("> ").strip_edges()
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


func _check(label: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + label)
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame
