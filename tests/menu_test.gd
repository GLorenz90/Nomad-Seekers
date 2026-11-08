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
	await _pad(JOY_BUTTON_DPAD_RIGHT)  # right hand of loadout 1
	await _pad(JOY_BUTTON_A)
	_check("A on a hand opens the weapon picker", _menu._picker.visible and _menu._picker_list.is_ancestor_of(_focused()))
	await _pad(JOY_BUTTON_B)
	_check("B closes only the picker", _menu.visible and not _menu._picker.visible and _focused() == _menu._slot_buttons[0][1])
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_DPAD_DOWN)  # first base weapon: Arbalest (Ranger only)
	_menu._message.text = ""
	await _pad(JOY_BUTTON_A)
	_check("A on a job-locked weapon explains the lock and keeps the picker open (%s)" % _menu._message.text,
		_menu._picker.visible and _menu._message.text.contains("needs"))
	for i in 40:
		if _focused_text().begins_with("Dagger"):
			break
		await _pad(JOY_BUTTON_DPAD_DOWN)
	var picked := _focused_text()
	await _pad(JOY_BUTTON_A)
	var right := _menu._set.loadouts[0].right
	_check("d-pad + A equips a weapon (%s)" % picked, right != null and picked.begins_with(right.display_name)
		and not _menu._picker.visible)

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

	# Levels tab tools.
	while _tab() != "Levels":
		await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(3)
	var oro := _player.save.inventory.oro
	while not _focused_text().begins_with("+1000 Oro"):
		await _pad(JOY_BUTTON_DPAD_DOWN)
		if _focused() is CheckButton:
			break
	if not _focused_text().begins_with("+1000 Oro"):
		await _pad(JOY_BUTTON_DPAD_RIGHT)
		for i in 6:
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
