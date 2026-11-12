extends SceneTree
## Automated test for Part 8 game flow: the old single save moving into slot
## 1, the title screen (main menu, character select, creation) driven with a
## gamepad, the new character saved to its slot, Nomad-2 (the hub) and its
## teleporter picker (gym, test arena, stay), the gym's pad back, Continue,
## quitting to the title, deleting a character, and full slots.
##
## Uses its own folder for slots, so real characters are never touched.
##
## Run from the project folder:
##   godot --headless --path . --script res://tests/flow_test.gd

const DIR := "user://flow_test/"

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_wipe()
	Session.slot_dir = DIR + "characters/"
	Session.legacy_save = DIR + "save.tres"
	Session.settings_path = DIR + "session.cfg"
	Session.slot = -1
	Session.save = null

	# --- The old single save becomes slot 1 ------------------------------------------------
	DirAccess.make_dir_recursive_absolute(DIR)
	var old := SaveData.fresh(CombatController.make_default_loadouts())
	old.character.seeker_name = "Veteran"
	old.inventory.oro = 1234
	ResourceSaver.save(old, Session.legacy_save)
	await _scene("res://scenes/title.tscn")
	var title := current_scene as TitleScreen
	_check("the Part 5-7 save moved into slot 1 (Oro kept)",
		Session.has_slot(0) and Session.load_slot(0).character.seeker_name == "Veteran"
		and Session.load_slot(0).inventory.oro == 1234 and not FileAccess.file_exists(Session.legacy_save))
	_check("the title screen opens on the main menu", title.current_page() == "main")
	_check("Continue is greyed with no character played yet; focus on Character select (%s)" % _focused_text(),
		title._continue.disabled and _focused_text() == "Character select")

	# --- Focus safety net: a click on empty space, then the controller ---------------------
	await _click(Vector2(40, 40))
	_check("a mouse click on the background doesn't clear focus (%s)" % _focused_text(), _focused_text() == "Character select")
	root.gui_release_focus()
	await _pad(JOY_BUTTON_A)
	_check("with nothing focused, A refocuses the menu instead of being lost (%s)" % _focused_text(),
		_focused_text() == "Character select" and title.current_page() == "main")
	root.gui_release_focus()
	await _pad(JOY_BUTTON_DPAD_DOWN)
	_check("so does the d-pad (%s)" % _focused_text(), _focused_text() == "Character select")

	# --- Character select ------------------------------------------------------------------
	await _pad(JOY_BUTTON_A)
	_check("A opens character select with 4 slots", title.current_page() == "select" and title._slot_box.get_child_count() == 4)
	_check("slot 1 shows the character (%s)" % _focused_text(), _focused_text().begins_with("1   Veteran"))
	await _pad(JOY_BUTTON_DPAD_DOWN)
	_check("slot 2 is empty (%s)" % _focused_text(), _focused_text().contains("empty"))
	await _pad(JOY_BUTTON_B)
	_check("B goes back to the main menu, on Character select (%s)" % _focused_text(),
		title.current_page() == "main" and _focused_text() == "Character select")
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_A)
	_check("A on an empty slot opens character creation", title.current_page() == "create" and title._create_slot == 1)
	_check("creation starts on Race, not the name box (%s)" % root.gui_get_focus_owner(), root.gui_get_focus_owner() == title._race)
	await _pad(JOY_BUTTON_DPAD_UP)
	_check("up reaches the name row", root.gui_get_focus_owner() == title._name or root.gui_get_focus_owner().get_parent() == title._name.get_parent())
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	_check("and the d-pad gets back out of it (%s)" % root.gui_get_focus_owner(),
		root.gui_get_focus_owner() is OptionButton)

	# --- Creation ----------------------------------------------------------------------------
	title._race.select(CharacterData.Race.GOLUMAN)
	title._job.select(CharacterData.Job.INVOKER)
	title._update_preview()
	_check("Goluman can't pick Invoker (greyed, switched to Ranger)",
		title._job.is_item_disabled(CharacterData.Job.INVOKER) and title._job.selected == CharacterData.Job.RANGER)
	title._race.select(CharacterData.Race.LUMERA)
	title._update_preview()
	_check("other races can", not title._job.is_item_disabled(CharacterData.Job.INVOKER))
	title._name.text = "Lirael"
	title._gender.select(CharacterData.Gender.FEMALE)
	title._job.select(CharacterData.Job.INVOKER)
	title._starter.select(3)
	title._hand.select(1)  # left-handed
	title._update_preview()
	_check("the preview shows race, job, handedness and emblem (%s)" % title._preview.text.get_slice("\n", 2),
		title._preview.text.contains("+10 SOL") and title._preview.text.contains("Emblem:")
		and title._preview.text.contains("Left-handed: primary weapon (X) in the left hand"))
	title._create_button.grab_focus()
	await _frames(2)
	await _pad(JOY_BUTTON_A)
	await _frames(20)
	_check("Create goes to Nomad-2 (%s)" % current_scene.scene_file_path, current_scene.scene_file_path == Session.HUB_SCENE)
	var player := current_scene.get_node("Player") as Player
	var c := player.save.character
	_check("playing the new character: Lirael, Lumera, female, Invoker",
		c.seeker_name == "Lirael" and c.race == CharacterData.Race.LUMERA and c.gender == CharacterData.Gender.FEMALE
		and c.job == CharacterData.Job.INVOKER and player.combat.job_code == "I")
	_check("with the chosen SyncAIDa paired (Lumi) and the Field Frame on",
		player.save.paired_syncaida() != null and player.save.paired_syncaida().display_name == "Lumi"
		and c.torso != null)
	await _frames(3)
	var wallet: String = (current_scene.get_node("HUD") as DebugHud)._wallet.text
	_check("the HUD wallet is filled in (%s)" % wallet.get_slice("\n", 0), wallet.begins_with("Lirael") and not "%" in wallet
		and wallet.contains("Trap Scanner 2"))
	var pivots: Array = player.combat._pivots
	_check("left-handed: the primary weapon (X) is drawn on the left side (x %.1f), the off hand on the right" % pivots[CombatController.Hand.PRIMARY].position.x,
		c.left_handed and player.combat.left_handed and pivots[CombatController.Hand.PRIMARY].position.x < 0.0
		and pivots[CombatController.Hand.OFF].position.x > 0.0 and player.combat.button_for(CombatController.Hand.PRIMARY) == "X")
	var names := player.save.inventory.weapons.map(func(w: WeaponData) -> String: return w.display_name)
	_check("starter kit: a Sword, a Pistol and a Wand to carry (%s), and 2 Trap Scanners" % [names],
		names == ["Sword", "Pistol", "Wand"] and player.save.inventory.count(&"trap_scanner") == 2)
	var used := 0
	for lo in player.save.loadouts.loadouts:
		if not lo.is_empty():
			used += 1
	var first: Loadout = player.save.loadouts.loadouts[0]
	_check("only loadout 1 is filled: X Pistol, Y Sword (%d in use)" % used, used == 1
		and first.primary.display_name == "Pistol" and first.off_hand.display_name == "Sword")
	_check("saved to slot 2 straight away, and remembered for Continue",
		Session.has_slot(1) and Session.load_slot(1).character.seeker_name == "Lirael" and Session.last_slot() == 1)

	# --- Hub teleporter ----------------------------------------------------------------------
	var pad := current_scene.get_node("Teleporter") as Teleporter
	await _stand_on(player, pad)
	_check("the hub teleporter asks where to go (no pause; the Seeker waits)",
		pad.picker != null and not paused and (current_scene.get_node("Player") as Player).input_locked)
	_check("choices: the gym, the test arena, the demo data level, stay (%s)" % [pad.picker.button_names()],
		pad.picker.button_names().size() == 4 and pad.picker.button_names()[0].contains("gym")
		and pad.picker.button_names()[1].contains("arena") and pad.picker.button_names()[2].contains("data"))
	root.gui_release_focus()
	await _pad(JOY_BUTTON_A)
	_check("the picker refocuses after a lost focus instead of teleporting", pad.picker != null
		and _focused_text() == "The gym (test room)" and current_scene.scene_file_path == Session.HUB_SCENE)
	await _pad(JOY_BUTTON_B)
	_check("B stays in Nomad-2", pad.picker == null and not paused and current_scene.scene_file_path == Session.HUB_SCENE)
	await _frames(10)
	_check("and the B that closed the picker didn't also dash", player.dash_cooldown_left() == 0.0 and player.state != Player.State.DASH)
	var menu := current_scene.loadout_menu as LoadoutMenu
	menu.save_on_close = false
	menu.open()
	await _frames(3)
	var header_row: Array = []
	for child in menu._slot_buttons[0][CombatController.Hand.PRIMARY].get_parent().get_children().slice(0, 4):
		header_row.append((child as Label).text if child is Label else "")
	_check("the Palette section reads Primary (X) first, then Off hand (Y) (%s)" % [header_row],
		header_row[1] == "Primary (X)" and header_row[2] == "Off hand (Y)"
		and menu._slot_buttons[0][CombatController.Hand.PRIMARY].get_index() < menu._slot_buttons[0][CombatController.Hand.OFF].get_index())
	_check("and the primary slot of loadout 1 shows the Pistol (%s)" % menu._slot_buttons[0][CombatController.Hand.PRIMARY].text,
		menu._slot_buttons[0][CombatController.Hand.PRIMARY].text.contains("Pistol"))
	root.gui_release_focus()
	await _pad(JOY_BUTTON_A)
	_check("the pause menu refocuses after a lost focus too", root.gui_get_focus_owner() != null and menu.is_ancestor_of(root.gui_get_focus_owner()))
	menu.close()
	await _frames(3)
	player.save.inventory.oro = 777
	await _step_off(player, pad)
	await _stand_on(player, pad)
	await _pad(JOY_BUTTON_A)
	await _frames(20)
	_check("picking the gym goes there (%s)" % current_scene.scene_file_path, current_scene.scene_file_path == "res://scenes/main.tscn")
	_check("the trip saved the character (Oro 777 on disk)", Session.load_slot(1).inventory.oro == 777)
	player = current_scene.get_node("Player") as Player
	_check("the same character carries over", player.save.character.seeker_name == "Lirael" and player.save.inventory.oro == 777)
	var back := current_scene.get_node("NomadTeleporter") as Teleporter
	await _stand_on(player, back)
	await _frames(20)
	_check("the gym's pad goes back to Nomad-2", current_scene.scene_file_path == Session.HUB_SCENE)
	player = current_scene.get_node("Player") as Player
	pad = current_scene.get_node("Teleporter") as Teleporter
	await _stand_on(player, pad)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_A)
	await _frames(20)
	_check("and the hub reaches the test arena", current_scene.scene_file_path == "res://scenes/arena.tscn")

	# --- Quit to title, Continue ----------------------------------------------------------------
	player = current_scene.get_node("Player") as Player
	player.save.inventory.oro = 4321
	Session.quit_to_title()
	await _frames(10)
	title = current_scene as TitleScreen
	_check("quit to title saves and returns (%s)" % current_scene.scene_file_path,
		title != null and Session.load_slot(1).inventory.oro == 4321)
	_check("Continue now names the last character (%s)" % title._continue.text,
		not title._continue.disabled and title._continue.text.contains("Lirael") and _focused_text().begins_with("Continue"))
	await _pad(JOY_BUTTON_START)  # Start works like A on the title screen
	await _frames(20)
	player = current_scene.get_node("Player") as Player
	_check("Start on Continue goes to Nomad-2 as Lirael", current_scene.scene_file_path == Session.HUB_SCENE
		and player.save.character.seeker_name == "Lirael" and player.save.inventory.oro == 4321)

	# --- Delete, full slots ------------------------------------------------------------------------
	Session.quit_to_title()
	await _frames(10)
	title = current_scene as TitleScreen
	title.show_page("select")
	await _frames(2)
	await _pad(JOY_BUTTON_X)
	_check("X asks before deleting (%s)" % title._message.text, Session.has_slot(0) and title._message.text.contains("again"))
	await _pad(JOY_BUTTON_X)
	_check("a second X deletes slot 1", not Session.has_slot(0) and title._slot_box.get_child(0).text.contains("empty"))
	for i in Session.SLOT_COUNT:
		if not Session.has_slot(i):
			Session.write_slot(i, SaveData.create("Filler", CharacterData.Race.HUMAN, CharacterData.Gender.MALE,
				CharacterData.Job.STRIKER, 0))
	title._create_slot = -1
	title._create()
	_check("with every slot full, creation says so (%s)" % title._message.text, title._message.text.contains("full"))

	_wipe()
	print("\n%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _scene(path: String) -> void:
	change_scene_to_file(path)
	await _frames(10)


## Steps onto a pad and presses A (pads no longer fire on their own).
func _stand_on(player: Player, pad: Teleporter) -> void:
	player.global_position = pad.global_position + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	for i in 15:
		await physics_frame
	await _pad(JOY_BUTTON_A)
	await _frames(4)


func _step_off(player: Player, pad: Teleporter) -> void:
	player.global_position = pad.global_position + Vector3(0, 0.1, 6)
	await _frames(8)


func _wipe() -> void:
	var abs := ProjectSettings.globalize_path(DIR)
	if DirAccess.dir_exists_absolute(abs):
		_rm(abs)


func _rm(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		_rm(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = at
		e.global_position = at
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame


func _focused_text() -> String:
	var f := root.gui_get_focus_owner()
	if f is Button:
		return (f as Button).text.strip_edges()
	return ""


func _check(label: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + label)
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame
		await process_frame
	await process_frame
