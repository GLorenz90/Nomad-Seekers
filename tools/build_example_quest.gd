extends SceneTree
## Builds res://quests/foremans_favour: an example quest folder using every
## part of quest sessions (2026-11-13). Normally quests are made in the level
## editor; this one is generated so tests have a fixed quest to play.
##   godot --headless --path . --script res://tools/build_example_quest.gd
##
## The Foreman's Favour:
##   1. talk_foreman  Talk to Foreman Petram Solidus (walking his rounds by
##                    the teleporter). Agreeing completes the step.
##   2. meet_lapis    Lapis Viridi shows up by the bank. Talking to her starts
##                    the escort.
##   3. survey        Take her to the beacon at the survey site (a level only
##                    this quest has): the zone counts only with her nearby.
##   4. deliver       Bring the foreman 2 HP Gels (he takes them).
## Areas: the survey site, and the demo level (a pick from area test_1).

const DIR := "res://quests/foremans_favour"


func _init() -> void:
	var dir := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var quest := {
		"format": 1, "id": "foremans_favour", "title": "The Foreman's Favour", "client": "Petram Solidus, foreman",
		"text": "The foreman needs a Lumidium survey done and his crew patched up. Find him by the teleporter.",
		"reward": 800,
		"steps": [
			{"id": "talk_foreman", "type": "event", "goal": "Talk to Foreman Petram Solidus by the teleporter."},
			{"id": "meet_lapis", "type": "event", "goal": "Find Lapis Viridi by the bank and ask her to come along."},
			{"id": "survey", "type": "event", "goal": "Take Lapis to the beacon at the survey site."},
			{"id": "deliver", "type": "event", "goal": "Bring the foreman 2 HP Gels for his crew."}],
		"areas": [{"quest_level": "survey_site", "name": "Survey site"}, {"area": "test_1", "name": "The demo level"}]}
	var f := FileAccess.open(dir.path_join("quest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(quest, "\t", false))
	f.close()
	_nomad2().save_dir(dir.path_join("nomad2"))
	_survey_site().save_dir(dir.path_join("levels/survey_site"))
	print("built ", DIR)
	quit()


## What the quest adds to Nomad-2: the foreman and Lapis, their dialogue and
## wiring, and a crate stack for the foreman's crew.
func _nomad2() -> LevelData:
	var level := LevelData.create("The Foreman's Favour: Nomad-2", "nomad2")
	level.meta.kind = "nomad2"
	level.map.pieces = [
		{"id": "crates_1", "asset": "builtin:box", "size": [1.2, 1.2, 1.2], "pos": [5.5, 0, -7], "color": [0.55, 0.42, 0.25], "surface": "obstacle"},
		{"id": "crates_2", "asset": "builtin:box", "size": [1.2, 1.2, 1.2], "pos": [6.8, 0, -7.3], "yaw": 20, "color": [0.55, 0.42, 0.25], "surface": "obstacle"}]
	level.interaction.objects = [
		{"type": "person", "id": "foreman", "name": "Petram Solidus", "pos": [4, 0, -6], "yaw": 0,
			"look": {"color": [0.85, 0.55, 0.2], "height": 2.0},
			"talk": [{"dialogue": "foreman_ask"}, {"dialogue": "foreman_wait", "from_step": "talk_foreman"},
				{"dialogue": "foreman_gels", "from_step": "survey"}, {"dialogue": "foreman_thanks", "from_step": "deliver"}],
			"route": {"points": [[4, 0, -6], [4, 0, -2]], "mode": "back_and_forth", "speed": 1.2, "wait": 3.0}, "walking": true},
		{"type": "person", "id": "lapis", "name": "Lapis Viridi", "pos": [-9, 0, 3], "yaw": 90,
			"look": {"color": [0.3, 0.75, 0.6]}, "show_from": "talk_foreman",
			"talk": [{"dialogue": "lapis_ready"}, {"dialogue": "lapis_thanks", "from_step": "survey"}]}]
	level.interaction.dialogues = [
		{"id": "foreman_ask", "lines": [
			{"speaker": "Petram Solidus", "text": "Seeker! The survey office wants readings from the new dig, and I can't spare a soul."},
			{"speaker": "Petram Solidus", "text": "Lapis Viridi will go if someone keeps her safe. Will you?"}],
			"choices": [{"id": "yes", "text": "I'll do it."}, {"id": "no", "text": "Not now."}]},
		{"id": "foreman_wait", "lines": [{"speaker": "Petram Solidus", "text": "Lapis is by the bank. Keep her close down there."}]},
		{"id": "foreman_gels", "lines": [{"speaker": "Petram Solidus", "text": "Good work. One more thing: my crew's banged up. Got 2 HP Gels?"}],
			"choices": [{"id": "give", "text": "Here you go."}, {"id": "later", "text": "Not yet."}]},
		{"id": "foreman_short", "lines": [{"speaker": "Petram Solidus", "text": "That's not two Gels, Seeker. The shop's right there."}]},
		{"id": "foreman_thanks", "lines": [{"speaker": "Petram Solidus", "text": "The crew owes you one. Tell the Guild we're square."}]},
		{"id": "lapis_ready", "lines": [{"speaker": "Lapis Viridi", "text": "You're my escort? Lead the way, I'll stay right behind you."}]},
		{"id": "lapis_thanks", "lines": [{"speaker": "Lapis Viridi", "text": "Those readings are better than I hoped. Thank you!"}]}]
	level.interaction.rules = [
		{"id": "agree", "when": {"event": "dialogue_ended", "source": "foreman_ask", "value": "yes"},
			"do": [{"action": "complete_step", "step": "talk_foreman"}], "once": true},
		{"id": "escort", "when": {"event": "dialogue_ended", "source": "lapis_ready"},
			"if": [{"check": "quest_step", "step": "meet_lapis", "is": "current"}],
			"do": [{"action": "escort", "target": "lapis"}, {"action": "complete_step", "step": "meet_lapis"}], "once": true},
		{"id": "give", "when": {"event": "dialogue_ended", "source": "foreman_gels", "value": "give"},
			"if": [{"check": "has_item", "item": "hp_gel", "amount": 2}],
			"do": [{"action": "take_item", "item": "hp_gel", "amount": 2}, {"action": "complete_step", "step": "deliver"}], "once": false},
		{"id": "short", "when": {"event": "dialogue_ended", "source": "foreman_gels", "value": "give"},
			"if": [{"check": "has_item", "item": "hp_gel", "amount": 2, "is": false}],
			"do": [{"action": "start_dialogue", "target": "foreman_short"}], "once": false}]
	return level


## The survey site: a small floor, the beacon zone, and the way home.
func _survey_site() -> LevelData:
	var level := LevelData.create("Survey site", "")
	level.map.start = {"pos": [0, 0.1, 6], "yaw": 0}
	level.map.pieces = [
		{"id": "ground", "asset": "builtin:box", "size": [16, 0.5, 20], "pos": [0, -0.5, 0], "color": [0.35, 0.45, 0.3], "surface": "floor"},
		{"id": "beacon_post", "asset": "builtin:cylinder", "size": [0.6, 2.5, 0.6], "pos": [0, 0, -6], "color": [0.3, 0.8, 0.9], "surface": "obstacle"}]
	# One room covering the floor (the editor saves this from the navmesh).
	var a := [-7.6, 0.0, -9.6]
	var b := [7.6, 0.0, -9.6]
	var c := [7.6, 0.0, 9.6]
	var d := [-7.6, 0.0, 9.6]
	level.map.areas = [{"id": "room_1", "name": "Dig site", "kind": "room", "color": [0.43, 0.64, 0.95], "seed": [0, 0, 4],
		"polys": [[a, b, c], [a, c, d]]}]
	level.map.decorations = [{"id": "beacon_light", "asset": "builtin:light", "pos": [0, 2.8, -6], "color": [0.4, 0.9, 1.0], "energy": 1.5, "range": 8.0}]
	level.interaction.objects = [
		{"type": "trigger_zone", "id": "beacon", "pos": [0, 0, -4], "size": [6, 3, 4], "once": false},
		{"type": "teleporter", "id": "home", "pos": [0, 0, 8], "destination": "hub", "label": "Nomad-2"}]
	level.interaction.dialogues = [
		{"id": "too_far", "lines": [{"speaker": "SyncAIDa", "text": "Lapis isn't with you. Go back for her."}]}]
	level.interaction.rules = [
		{"id": "survey", "when": {"event": "entered", "source": "beacon"},
			"if": [{"check": "quest_step", "step": "survey", "is": "current"}, {"check": "escort_near", "target": "lapis", "distance": 10}],
			"do": [{"action": "stop_escort", "target": "lapis"}, {"action": "complete_step", "step": "survey"}], "once": true},
		{"id": "alone", "when": {"event": "entered", "source": "beacon"},
			"if": [{"check": "quest_step", "step": "survey", "is": "current"}, {"check": "escort_near", "target": "lapis", "distance": 10, "is": false}],
			"do": [{"action": "start_dialogue", "target": "too_far"}], "once": false}]
	return level
