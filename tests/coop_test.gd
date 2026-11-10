extends SceneTree
## Automated test for Part 12, local co-op (Grayson, 2026-11-09).
##
## - Start on a second controller opens a character picker in a new
##   split-screen pane (left / right); characters already playing can't join.
## - The guest plays their own character with their own controller: each
##   controller moves only its Seeker, and each Seeker's menu opens in its own
##   pane without pausing the other.
## - Target rings stay in their owner's pane; floor plates count both Seekers.
## - Falling in co-op: down until a partner's Revive (or A back to the start);
##   everyone down sends everyone back. EXP goes to everyone on the map.
## - Each Seeker travels on their own: a guest goes to Nomad-2 (a hosted map
##   in its own world) while the leader stays; EXP stays on its map; enemy HP
##   grows with Seekers on the map; the leader follows (the window's level
##   becomes a placeholder); the guest leaves; the leader travels back and
##   it's plain single player again.
##
## Uses its own folder for character slots, so real characters are never touched.
##   godot --headless --path . --script res://tests/coop_test.gd

const DIR := "user://coop_test/"
const ENEMY_DIR := "res://data/enemies/"

var _main: Node
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_wipe()
	Session.slot_dir = DIR + "characters/"
	Session.legacy_save = DIR + "save.tres"
	Session.settings_path = DIR + "session.cfg"
	Party.clear()
	Party.leader_pad = -1
	var names := ["Leader", "Spare", "Guest"]
	for i in names.size():
		var data := SaveData.create(names[i], CharacterData.Race.HUMAN, CharacterData.Gender.MALE,
			CharacterData.Job.STRIKER, 1)
		Session.write_slot(i, data)
	Session.use_slot(0, Session.load_slot(0))

	await _scene("res://scenes/arena.tscn")
	var leader := _main.get_node("Player") as Player
	await _pad(0, JOY_BUTTON_A)
	_check("the first controller used is the leader's", Party.leader_pad == 0)
	_check("alone, the leader plays with the shared controls", leader.input.is_shared())

	# --- Joining -----------------------------------------------------------------------------
	await _pad(1, JOY_BUTTON_START)
	var split: SplitScreen = CoopDirector.find(self).split if CoopDirector.find(self) else null
	_check("Start on a second controller splits the screen (2 panes)", split != null and split.panes.size() == 2)
	_check("only the panes draw the world now", root.disable_3d)
	_check("the leader's controls are their own now (keyboard and pad 0)",
		leader.input.slot == 0 and leader.input.device == 0 and leader.input.keyboard)
	_check("the leader's HUD and menu moved into the left pane",
		_main.hud.get_parent() == split.panes[0].sub and _main.loadout_menu.get_parent() == split.panes[0].sub)
	var picker := _find(split.panes[1].sub, "JoinPicker") as JoinPicker
	_check("the new pane asks which character joins", picker != null)
	if picker:
		var entries := picker.entries()
		_check("the leader's character is marked playing (%s)" % entries[0], entries[0].ends_with("(playing)"))
		_check("empty slots can't be picked (%s)" % entries[3], entries[3].contains("empty"))
	_check("panes split left and right",
		split.panes[0].position == Vector2.ZERO and split.panes[1].position.x > 0.0
		and split.panes[1].position.y == 0.0 and is_equal_approx(split.panes[1].size.y, split.panes[0].size.y))
	await _pad(1, JOY_BUTTON_DPAD_DOWN)
	await _pad(1, JOY_BUTTON_A)
	_check("the leader's controller didn't move the guest's picker", _main.kits.size() == 2)
	var guest: Player = _main.kits[1].player if _main.kits.size() > 1 else null
	_check("the guest joined as their own character (%s)" % (guest.save.character.seeker_name if guest else "none"),
		guest != null and guest.save.character.seeker_name == "Guest" and Party.size() == 2)
	if guest == null:
		_finish()
		return
	_check("on their own controller", guest.input.slot == 1 and guest.input.device == 1 and not guest.input.keyboard)
	_check("their HUD is in the right pane", _main.kits[1].hud.get_parent() == split.panes[1].sub)

	# --- Each controller moves its own Seeker -------------------------------------------------
	await _settle()
	var lead_at := leader.global_position
	var guest_at := guest.global_position
	await _stick(1, -1.0, 30)
	_check("pad 1's stick moves the guest (%.1f m)" % guest.global_position.distance_to(guest_at),
		guest.global_position.distance_to(guest_at) > 1.0)
	_check("and not the leader (%.2f m)" % leader.global_position.distance_to(lead_at),
		leader.global_position.distance_to(lead_at) < 0.1)
	lead_at = leader.global_position
	guest_at = guest.global_position
	await _stick(0, -1.0, 30)
	_check("pad 0's stick moves the leader and not the guest",
		leader.global_position.distance_to(lead_at) > 1.0 and guest.global_position.distance_to(guest_at) < 0.1)

	# --- Menus in their own panes, no pause ---------------------------------------------------
	var guest_menu: LoadoutMenu = _main.kits[1].menu
	await _pad(1, JOY_BUTTON_START)
	_check("Start on the guest's controller opens their menu only",
		guest_menu.visible and not _main.loadout_menu.visible and guest_menu.get_parent() == split.panes[1].sub)
	_check("the game keeps running", not paused and guest.input_locked and not leader.input_locked)
	lead_at = leader.global_position
	await _stick(0, -1.0, 20)
	_check("the leader keeps playing while the guest is in their menu", leader.global_position.distance_to(lead_at) > 0.5)
	await _pad(0, JOY_BUTTON_START)
	_check("then the leader's own menu opens in their pane", _main.loadout_menu.visible and guest_menu.visible)
	await _pad(0, JOY_BUTTON_START)
	await _pad(1, JOY_BUTTON_B)
	_check("each closes with their own controller", not _main.loadout_menu.visible and not guest_menu.visible)

	# --- Rings and plates ------------------------------------------------------------------------
	_check("each Seeker's target rings are on their own layer",
		_main.kits[0].markers.render_layers == SeekerPane.marker_layer(0)
		and _main.kits[1].markers.render_layers == SeekerPane.marker_layer(1))
	_check("and each pane hides the other Seeker's rings",
		split.panes[0].camera.cull_mask & SeekerPane.marker_layer(1) == 0
		and split.panes[1].camera.cull_mask & SeekerPane.marker_layer(0) == 0
		and split.panes[1].camera.cull_mask & SeekerPane.marker_layer(1) != 0)
	var plates := _main.get_node("Switches/HallSwitch") as SwitchGroup
	_check("the four floor plates now let only 2 stay down", plates.seekers() == 2 and plates.max_latched() == 2)

	# --- Falling in co-op --------------------------------------------------------------------------
	_kill(guest)
	await _frames(3)
	_check("a fallen guest stays down where they fell", guest.downed and guest.health.is_dead() and guest.input_locked)
	_check("enemies look past a fallen Seeker", Player.nearest(_main, guest.global_position) == leader)
	guest.revive(0.5)
	_check("a Revive brings them back", not guest.downed and not guest.input_locked and guest.health.hp > 0.0)
	_kill(guest)
	await _frames(3)
	guest.global_position += Vector3(3, 0, 0)
	await _pad(1, JOY_BUTTON_A)
	await _frames(2)
	_check("A while down goes back to the start, standing",
		not guest.downed and guest.health.hp == guest.health.max_hp
		and guest.global_position.distance_to(_main.kits[1].spawn.origin) < 0.5)
	leader.global_position += Vector3(0, 0, -3)
	_kill(guest)
	_kill(leader)
	await _frames(3)
	_check("when everyone is down, everyone goes back to the start",
		not guest.downed and not leader.downed and leader.health.hp == leader.health.max_hp
		and leader.global_position.distance_to(_main.kits[0].spawn.origin) < 0.5)

	# --- EXP for everyone on the map --------------------------------------------------------------
	var hound := _enemy("grub_hound", leader.global_position + Vector3(0, 0, -6))
	_check("enemies get more HP with two Seekers on the map (%.0f)" % hound.health.max_hp,
		is_equal_approx(hound.health.max_hp, hound.data.max_hp * 1.5))
	_kill(guest)
	await _frames(2)
	var exp_leader := leader.save.character.experience
	var exp_guest := guest.save.character.experience
	_main.on_enemy_defeated(hound)
	_check("a kill gives both Seekers its full EXP, even one who's down",
		leader.save.character.experience > exp_leader and guest.save.character.experience - exp_guest == leader.save.character.experience - exp_leader)
	hound.queue_free()
	guest.revive(1.0)

	# --- Travelling on your own -------------------------------------------------------------------
	var director := CoopDirector.find(self)
	guest.autosave = false
	CoopDirector.travel(guest, Session.HUB_SCENE)
	await _frames(20)
	var hub: Node = director.hosts.get(Session.HUB_SCENE)
	_check("the guest goes to Nomad-2 alone; the leader stays in the arena",
		hub != null and _main.kits.size() == 1 and _main.kits[0].player == leader and hub.kits.size() == 1)
	guest = hub.kits[0].player
	guest.autosave = false
	_check("still as their character, on their controller, in their own pane",
		guest.save.character.seeker_name == "Guest" and guest.input.device == 1
		and director.split.pane_for_who(1).player == guest and split.panes.size() == 2)
	_check("each pane looks into its Seeker's map",
		director.split.pane_for_who(1).sub.world_3d == guest.get_world_3d()
		and director.split.pane_for_who(Party.LEADER).sub.world_3d == leader.get_world_3d()
		and guest.get_world_3d() != leader.get_world_3d())
	_check("each map only sees its own Seekers",
		Scope.group(leader, "player") == [leader] and Scope.group(guest, "player") == [guest])
	var solo := _enemy("grub_hound", leader.global_position + Vector3(0, 0, -6))
	_check("alone on the map, enemies have their normal HP", is_equal_approx(solo.health.max_hp, solo.data.max_hp))
	exp_leader = leader.save.character.experience
	exp_guest = guest.save.character.experience
	_main.on_enemy_defeated(solo)
	_check("a kill on another map gives the guest nothing",
		leader.save.character.experience > exp_leader and guest.save.character.experience == exp_guest)
	solo.queue_free()

	leader.autosave = false
	CoopDirector.travel(leader, Session.HUB_SCENE)
	await _frames(20)
	_check("the leader follows: both in Nomad-2, the window's level is a placeholder",
		current_scene.scene_file_path == CoopDirector.PLACEHOLDER and hub.kits.size() == 2)
	leader = hub.kits[1].player
	leader.autosave = false

	# --- Leaving ----------------------------------------------------------------------------------
	hub.leave_party(guest)
	await _frames(3)
	_check("a guest can leave the party", hub.kits.size() == 1 and not Party.is_active() and split.panes.size() == 1)
	_check("the leader keeps playing in Nomad-2 full screen", CoopDirector.find(self) != null and split.panes[0].player == leader)
	CoopDirector.travel(leader, "res://scenes/arena.tscn")
	await _frames(30)
	_main = current_scene
	for kit in _main.kits:
		kit.player.autosave = false
	leader = _main.kits[0].player
	_check("travelling back to the arena: plain single player again",
		CoopDirector.find(self) == null and not root.disable_3d and leader.input.is_shared()
		and _main.hud.get_parent() == _main and _main.scene_file_path == "res://scenes/arena.tscn")
	await _pad(2, JOY_BUTTON_START)
	director = CoopDirector.find(self)
	var p2 := _find(director.split.panes[1].sub, "JoinPicker") as JoinPicker if director else null
	_check("a third controller can join next (picker open)", p2 != null)
	if p2:
		p2.cancelled.emit()
		await _frames(3)
	_check("cancelling the picker closes the pane and the split screen", CoopDirector.find(self) == null)

	_finish()


func _finish() -> void:
	Party.clear()
	Session.slot = -1
	Session.save = null
	_wipe()
	print("PASS: coop test" if _failures == 0 else "FAIL: %d coop checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _scene(path: String) -> void:
	if _main:
		_main.queue_free()
		await process_frame
	_main = (load(path) as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	for kit in _main.kits:
		kit.player.autosave = false
	await _frames(20)
	for kit in _main.kits:
		kit.player.autosave = false


func _find(parent: Node, cls: String) -> Node:
	for child in parent.get_children():
		if child.get_script() and (child.get_script() as Script).get_global_name() == cls:
			return child
	return null


func _enemy(file: String, at: Vector3) -> Enemy:
	var data := (load(ENEMY_DIR + file + ".tres") as EnemyData).duplicate() as EnemyData
	var enemy := Enemy.create(data)
	_main.add_child(enemy)
	enemy.global_position = at
	return enemy


func _kill(seeker: Player) -> void:
	var info := DamageInfo.new()
	info.amount = 99999.0
	info.accuracy = -1.0
	seeker.health.take_damage(info)


func _settle() -> void:
	for kit in _main.kits:
		kit.player.velocity = Vector3.ZERO
	await _frames(10)


func _pad(device: int, button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		e.device = device
		Input.parse_input_event(e)
		await process_frame
		await physics_frame
		await process_frame


func _stick(device: int, y: float, frames: int) -> void:
	for value in [y, 0.0]:
		var e := InputEventJoypadMotion.new()
		e.axis = JOY_AXIS_LEFT_Y
		e.axis_value = value
		e.device = device
		Input.parse_input_event(e)
		await _frames(frames if value != 0.0 else 8)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + label)
	if not ok:
		_failures += 1


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
