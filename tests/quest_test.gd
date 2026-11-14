extends SceneTree
## Quest sessions and people (Grayson 2026-11-13), through the example quest
## res://quests/foremans_favour (tools/build_example_quest.gd):
## accepting starts a quest session (Nomad-2 reloads with the quest's people,
## the teleporter offers only its areas), people talk, change with the steps,
## walk, take items and are escorted to a quest-only level; reporting pays
## the party and goes back to free play. Also: the leader's quest is the
## party's, a quest's named levels win the picks, and old one-objective
## quests still read as one step.
##   godot --headless --path . --script res://tests/quest_test.gd

const DIR := "user://quest_test/"
const QUEST := &"foremans_favour"

var _failures := 0
var _save: SaveData


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + label)
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _level() -> Node:
	return current_scene


func _player() -> Player:
	return _level().get_node("Player") as Player


func _events() -> LevelEvents:
	return _level().get("events") as LevelEvents


func _person(id: String) -> Person:
	var ev := _events()
	return ev.objects.get(id) as Person if ev else null


## Waits for a scene change to land and its navmesh to bake.
func _arrive(path_hint: String) -> void:
	for i in 120:
		await process_frame
		var lvl := current_scene
		if lvl and Maps.id_of(lvl).contains(path_hint) and lvl.get("events") != null:
			break
	await _frames(30)
	for p in get_nodes_in_group("player"):
		(p as Player).autosave = false


## The dialogue that's open now ("" for none), closed afterwards.
func _close_dialogue() -> String:
	var ev := _events()
	var box: DialogueBox = ev._box if ev and is_instance_valid(ev._box) else null
	if box == null:
		return ""
	var id := String(box.dialogue.get("id", ""))
	ev._box = null
	if box.player:
		box.player.input_locked = false
	box.queue_free()
	return id


func _run() -> void:
	Session.slot_dir = DIR + "characters/"
	Session.settings_path = DIR + "session.cfg"
	Party.clear()
	QuestBook.reload()
	_save = SaveData.create("Quester", CharacterData.Race.HUMAN, CharacterData.Gender.FEMALE, CharacterData.Job.RANGER, 1)
	Session.save = _save
	Session.slot = -1

	# --- The quest folder ---------------------------------------------------------------------
	var q := QuestBook.get_quest(QUEST)
	_check("a quest folder loads (%s)" % q.get("title", "none"), q.get("title") == "The Foreman's Favour")
	_check("with its 4 steps in order", q.steps.size() == 4 and q.steps[0].id == "talk_foreman" and q.steps[3].id == "deliver")
	_check("its areas: its own level and a pick from test_1",
		q.areas.size() == 2 and String(q.areas[0].destination).ends_with("foremans_favour/levels/survey_site")
		and q.areas[1].destination == "area:test_1")
	_check("and its Nomad-2 additions", String(q.nomad2).ends_with("foremans_favour/nomad2"))
	_check("the example quest's levels pass the format check",
		LevelData.load_dir(q.nomad2).validate().is_empty() and LevelData.load_dir(q.areas[0].destination).validate().is_empty())
	var old := QuestBook.get_quest(&"demo_run")
	_check("a Part 13a quest reads as one event step", old.steps.size() == 1 and old.steps[0].id == "demo_boss" and old.areas.size() == 1)

	# --- Free play --------------------------------------------------------------------------
	change_scene_to_file(Session.HUB_SCENE)
	await _arrive("hub")
	_check("Nomad-2 in free play has nobody extra", get_nodes_in_group("people").is_empty())

	# --- Accepting starts a quest session ----------------------------------------------------
	Maps.picks["test_1"] = "somewhere"
	_check("accepting works", QuestBook.accept(_save, QUEST) == "")
	QuestSession.restart(self)
	await _arrive("hub")
	_check("the area picks roll again", not Maps.picks.has("test_1"))
	var foreman := _person("foreman")
	var lapis := _person("lapis")
	_check("Nomad-2 reloads with the quest's people", foreman != null and lapis != null)
	_check("the foreman is around; Lapis isn't yet (she shows from step 1)", foreman != null and foreman.visible and lapis != null and not lapis.visible)
	var crates := _level().find_child("crates_1", true, false)
	_check("the quest's props are on Nomad-2", crates != null)
	_check("the teleporter offers only the quest's areas",
		QuestSession.destinations().map(func(d): return d[0]) == ["Survey site", "The demo level"])
	var start := foreman.global_position
	await _frames(90)
	_check("the foreman walks his rounds (%.1f m)" % foreman.global_position.distance_to(start), foreman.global_position.distance_to(start) > 0.5)

	# --- Talking ----------------------------------------------------------------------------
	_events().on_talked(foreman, _player())
	_check("talking to him opens his first lines", _close_dialogue() == "foreman_ask")
	_check("the wiring hears who was talked to", _events().history.has("talked:foreman"))
	_events().emit_event("dialogue_ended", "foreman_ask", "no")
	_check("saying no leaves the step", QuestBook.step_index(_save) == 0)
	_events().emit_event("dialogue_ended", "foreman_ask", "yes")
	await _frames(3)
	_check("saying yes completes step 1", QuestBook.step_done(_save, "talk_foreman") and QuestBook.step_index(_save) == 1)
	_check("the wiring hears step_completed", _events().history.has("step_completed:talk_foreman"))
	_check("Lapis shows up", lapis.visible)
	_events().on_talked(foreman, _player())
	_check("and the foreman says something new", _close_dialogue() == "foreman_wait")

	# --- Escort -------------------------------------------------------------------------------
	_events().on_talked(lapis, _player())
	_check("Lapis's lines", _close_dialogue() == "lapis_ready")
	_events().emit_event("dialogue_ended", "lapis_ready", "")
	await _frames(3)
	_check("she starts following and step 2 is done", lapis.escorting and QuestBook.step_index(_save) == 2
		and QuestSession.escorts().size() == 1)

	# --- The quest's own level ------------------------------------------------------------------
	Maps.change_to(self, String(q.areas[0].destination))
	await _arrive("survey_site")
	var escort := _person("lapis")
	_check("Lapis comes along to the survey site", escort != null and escort.escorting and escort.visible)
	var zone := _events().objects.get("beacon") as Node3D
	escort.global_position = Vector3(7, 0.1, 9)
	_player().global_position = zone.global_position
	_events().emit_event("entered", "beacon")
	_check("the beacon without her doesn't count", QuestBook.step_index(_save) == 2 and _close_dialogue() == "too_far")
	escort.global_position = zone.global_position + Vector3(1, 0.1, 0)
	_events().emit_event("entered", "beacon")
	await _frames(3)
	_check("with her close it does (step 3)", QuestBook.step_done(_save, "survey"))
	_check("and the escort ends", not escort.escorting and QuestSession.escorts().is_empty())

	# --- Delivery -------------------------------------------------------------------------------
	Maps.change_to(self, "hub")
	await _arrive("hub")
	foreman = _person("foreman")
	_events().on_talked(foreman, _player())
	_check("back on Nomad-2 the foreman asks for Gels", _close_dialogue() == "foreman_gels")
	_save.inventory.consumables.erase(&"hp_gel")
	_events().emit_event("dialogue_ended", "foreman_gels", "give")
	_check("without 2 Gels he says so", _close_dialogue() == "foreman_short" and QuestBook.step_index(_save) == 3)
	_save.inventory.add_consumable(&"hp_gel", 3)
	_events().emit_event("dialogue_ended", "foreman_gels", "give")
	await _frames(3)
	_check("with them he takes 2 (1 left)", _save.inventory.count(&"hp_gel") == 1)
	_check("and the quest is complete", QuestBook.is_complete(_save) and QuestBook.progress_text(_save) == "done")

	# --- Reporting ---------------------------------------------------------------------------
	var oro := _save.inventory.oro
	var message := QuestBook.report(_save)
	_check("reporting pays (%s)" % message, _save.inventory.oro == oro + 800 and QuestBook.active(_save).is_empty())
	QuestSession.restart(self)
	await _arrive("hub")
	_check("and Nomad-2 is back to free play", get_nodes_in_group("people").is_empty())

	# --- Co-op: the leader's quest is the party's ----------------------------------------------
	var guest := SaveData.create("Guest", CharacterData.Race.HUMAN, CharacterData.Gender.MALE, CharacterData.Job.STRIKER, 1)
	Party.guests.append({"device": 7, "slot": 9, "save": guest, "input": 1, "map": Session.HUB_SCENE})
	_check("a guest can't take a quest", QuestBook.accept(guest, QUEST) == "Only the party leader can take a quest.")
	QuestBook.accept(_save, &"hound_cull")
	_check("the guest is on the leader's quest", String(QuestBook.active(guest).get("id", "")) == "hound_cull" and guest.quest.is_empty())
	QuestBook.record(guest, "defeat", "grub_hound", 6)
	_check("a guest's progress counts for the party", QuestBook.is_complete(_save))
	var guest_oro := guest.inventory.oro
	oro = _save.inventory.oro
	QuestBook.report(guest)
	_check("everyone gets the reward", guest.inventory.oro == guest_oro + 300 and _save.inventory.oro == oro + 300
		and int(guest.quests_cleared.get("hound_cull", 0)) == 1)
	Party.guests.clear()

	# --- A quest's named levels win the picks -----------------------------------------------
	QuestSession.roll_picks({"areas": [{"area": "test_1", "level": "res://levels/test_1/demo", "destination": "area:test_1"}]})
	_check("an area the quest names a level for gets it", Maps.picks.get("test_1") == "res://levels/test_1/demo")
	QuestSession.roll_picks({})
	_check("free play picks fresh", Maps.picks.is_empty())

	print("FAIL: %d failure(s)" % _failures if _failures else "PASS: 0 failure(s)")
	quit(_failures)
