class_name LevelEvents
extends Node
## A data level's wiring (Part 13a, level editor Layer 2): when <event> from
## <source>, if <conditions>, do <actions>. It generalises Part 11's
## SwitchGroup (buttons → switch_action): every action that targets an
## object calls that object's switch_action().
##
## A rule (interaction.json "rules"):
##   {"id": "r1",
##    "when": {"event": "combat_ended", "source": "room_2"},
##    "if": [{"check": "flag", "flag": "lever", "is": true}],
##    "do": [{"action": "open", "target": "door_3"},
##           {"action": "wait", "seconds": 1.5},
##           {"action": "start_dialogue", "target": "brandt_call"}],
##    "once": true}
## Events, conditions and actions are listed in docs/level_format.md.
##
## Quests (2026-11-13): the same wiring runs a quest's Nomad-2 overlay and
## its levels. It hears step_completed and talked, checks quest_step,
## quest_flag, has_item and escort_near, and can complete_step,
## set_quest_flag, take_item, set_talk, escort and stop_escort (plus show,
## hide, walk and stop on people).

signal fired(event: String, source: String)

var level: Node
## id -> the node built for it (doors, rooms, platforms...).
var objects := {}
## id -> dialogue data.
var dialogues := {}
var flags := {}
var rules: Array = []
## Every event so far, newest last (tests and debugging).
var history: Array[String] = []
var _spent := {}
## Dialogues waiting their turn (one at a time).
var _queue: Array = []
var _box: DialogueBox
## Who last talked to someone (take_item / has_item use their pack).
var talker: Player


func _ready() -> void:
	add_to_group("level_events")


## Something happened. `value`: the wave number for wave_cleared, the HP
## percent for health_below, the choice for dialogue_ended.
func emit_event(event: String, source := "", value: Variant = null) -> void:
	history.append("%s:%s" % [event, source])
	fired.emit(event, source)
	for rule in rules:
		var id := String(rule.get("id", ""))
		if _spent.has(id) or not _matches(rule.get("when", {}), event, source, value):
			continue
		if not _conditions_met(rule.get("if", [])):
			continue
		if bool(rule.get("once", true)):
			_spent[id] = true
		_run(rule.get("do", []))


func _matches(when: Dictionary, event: String, source: String, value: Variant) -> bool:
	if String(when.get("event", "")) != event:
		return false
	var want := String(when.get("source", ""))
	if want != "" and want != source:
		return false
	if not when.has("value") or value == null:
		return true
	match event:
		"health_below":
			return float(value) <= float(when.value)
		"wave_cleared":
			return int(value) == int(when.value)
		_:
			return String(value) == String(when.value)


func _conditions_met(checks: Array) -> bool:
	for c in checks:
		match String(c.get("check", "")):
			"flag":
				if flags.get(String(c.get("flag", "")), false) != c.get("is", true):
					return false
			"difficulty_at_least":
				var tiers := LevelData.DIFFICULTIES
				if tiers.find(Session.difficulty) < tiers.find(String(c.get("value", "normal"))):
					return false
			"party_at_least":
				if Scope.group(level, "player").size() < int(c.get("value", 1)):
					return false
			"quest_step":
				# is: "current", "done" or "not_done" (default "done").
				var step := String(c.get("step", ""))
				var save := _party_save()
				var done := QuestBook.step_done(save, step)
				var current := String(QuestBook.current_step(save).get("id", "")) == step
				match String(c.get("is", "done")):
					"current":
						if not current:
							return false
					"not_done":
						if done:
							return false
					_:
						if not done:
							return false
			"quest_flag":
				if QuestBook.flag(_party_save(), String(c.get("flag", ""))) != c.get("is", true):
					return false
			"has_item":
				if _has_item(_who(), c) != bool(c.get("is", true)):
					return false
			"escort_near":
				var person: Node = objects.get(String(c.get("target", "")))
				var seeker := _who()
				var near := person != null and seeker != null and is_instance_valid(person) and (person as Node3D).visible \
					and (person as Node3D).global_position.distance_to(seeker.global_position) <= float(c.get("distance", 8.0))
				if near != bool(c.get("is", true)):
					return false
			"quest_active":
				var any := false
				for seeker in Scope.group(level, "player"):
					var q := QuestBook.active((seeker as Player).save)
					if not q.is_empty() and String(q.id) == String(c.get("value", "")):
						any = true
				if not any:
					return false
	return true


func _run(actions: Array) -> void:
	for a in actions:
		if String(a.get("action", "")) == "wait":
			await get_tree().create_timer(maxf(float(a.get("seconds", 0.0)), 0.0)).timeout
			if not is_inside_tree():
				return
		else:
			do_action(a)


func do_action(a: Dictionary) -> void:
	var action := String(a.get("action", ""))
	var target := String(a.get("target", ""))
	match action:
		"start_dialogue":
			play_dialogue(target)
		"set_flag":
			var flag := String(a.get("flag", ""))
			flags[flag] = a.get("value", true)
			emit_event("flag_set", flag, flags[flag])
		"start_timer":
			var timer_id := String(a.get("id", target))
			var seconds := clampf(float(a.get("seconds", 1.0)), 0.0, 3600.0)
			get_tree().create_timer(seconds).timeout.connect(func():
				if is_inside_tree():
					emit_event("timer_done", timer_id))
		"give_item":
			_give(a)
		"complete_objective":
			# Part 13a: completes the `event` step with that key (its id).
			var result := QuestBook.record(_party_save(), "event", String(a.get("key", "")))
			if result != "":
				level.call("banner", QuestBook.news(_party_save(), result))
		"complete_step":
			var done := QuestBook.complete_step(_party_save(), String(a.get("step", target)))
			if done != "":
				level.call("banner", QuestBook.news(_party_save(), done))
		"set_quest_flag":
			QuestBook.set_flag(_party_save(), String(a.get("flag", "")), a.get("value", true))
		"take_item":
			_take(_who(), a)
		"set_talk":
			var person := objects.get(target) as Person
			if person:
				person.talk_override = String(a.get("dialogue", ""))
		"escort":
			var person := objects.get(target) as Person
			if person:
				person.escorting = true
				QuestSession.start_escort({"id": person.person_id, "name": person.display_name, "look": person.look})
		"stop_escort":
			var person := objects.get(target) as Person
			if person:
				person.escorting = false
			QuestSession.stop_escort(target)
		"banner":
			level.call("banner", String(a.get("text", "")))
		_:
			var node: Node = objects.get(target)
			if node and is_instance_valid(node) and node.has_method("switch_action"):
				node.switch_action(action)
			else:
				push_warning("Level wiring: %s can't %s" % [target, action])


## give_item: {"item": "oro", "amount": 100} | {"item": "hp_gel", "amount": 2}
## | {"item": "lumidium", "color": "fire", "amount": 3}. Dropped at each
## Seeker's feet (pack limits apply like any pickup).
func _give(a: Dictionary) -> void:
	var item := String(a.get("item", ""))
	var amount := clampi(int(a.get("amount", 1)), 1, 99999)
	for seeker in Scope.group(level, "player"):
		var at := (seeker as Node3D).global_position + Vector3.UP * 0.3
		if item == "oro":
			level.call("spawn_drop", {"oro": amount}, at)
		elif item == "lumidium" and Inventory.LUMIDIUM.has(StringName(String(a.get("color", "raw")))):
			for i in mini(amount, 15):
				level.call("spawn_drop", {"lumidium": StringName(String(a.get("color", "raw")))}, at)
		elif Inventory.CONSUMABLES.has(StringName(item)):
			for i in mini(amount, 10):
				level.call("spawn_drop", {"consumable": StringName(item)}, at)
		else:
			push_warning("Level wiring: can't give \"%s\"" % item)


## take_item: takes from the Seeker who talked (else the first Seeker here)
## {"item": "oro" | a consumable id | "lumidium" (+ "color"), "amount"}.
## Nothing is taken unless they have it all; check with has_item first.
func _take(seeker: Player, a: Dictionary) -> bool:
	if seeker == null or not _has_item(seeker, a):
		return false
	var item := String(a.get("item", ""))
	var amount := clampi(int(a.get("amount", 1)), 1, 99999)
	var inv := seeker.save.inventory
	if item == "oro":
		inv.oro -= amount
	elif item == "lumidium":
		var color := StringName(String(a.get("color", "raw")))
		seeker.carried_lumidium[color] = int(seeker.carried_lumidium.get(color, 0)) - amount
	else:
		inv.remove_consumable(StringName(item), amount)
	seeker.item_collected.emit("-%d %s" % [amount, item.capitalize() if item != "oro" else "Oro"])
	return true


func _has_item(seeker: Player, c: Dictionary) -> bool:
	if seeker == null or seeker.save == null:
		return false
	var item := String(c.get("item", ""))
	var amount := clampi(int(c.get("amount", 1)), 1, 99999)
	var inv := seeker.save.inventory
	if item == "oro":
		return inv.oro >= amount
	if item == "lumidium":
		return int(seeker.carried_lumidium.get(StringName(String(c.get("color", "raw"))), 0)) >= amount
	return inv.count(StringName(item)) >= amount


## The Seeker the wiring is about: whoever last talked to someone, else the
## first one here.
func _who() -> Player:
	if talker and is_instance_valid(talker) and Scope.level(talker) == level:
		return talker
	return Scope.first(level, "player") as Player


func _party_save() -> SaveData:
	var seeker := _who()
	return seeker.save if seeker else Session.save


## A quest step was completed (QuestSession): people show or hide, and the
## wiring hears step_completed.
func on_step_completed(step_id: String) -> void:
	for node in objects.values():
		if is_instance_valid(node) and node is Person:
			(node as Person).refresh()
	emit_event("step_completed", step_id)


## A on a person: the wiring hears talked, then they say their piece.
func on_talked(person: Person, seeker: Player) -> void:
	talker = seeker
	emit_event("talked", person.person_id)
	var id := person.current_dialogue()
	if id != "":
		play_dialogue(id, seeker)


# --- Dialogue -------------------------------------------------------------------------------

func play_dialogue(id: String, seeker: Player = null) -> void:
	if not dialogues.has(id):
		push_warning("Level wiring: no dialogue %s" % id)
		return
	if _box and is_instance_valid(_box):
		_queue.append(id)
		return
	var reader := seeker if seeker else _who()
	_box = DialogueBox.new()
	(reader.ui_root() if reader else level).add_child(_box)
	_box.finished.connect(_on_dialogue_finished)
	_box.open(dialogues[id], reader)


func is_talking() -> bool:
	return _box != null and is_instance_valid(_box)


func _on_dialogue_finished(id: String, choice: String) -> void:
	_box = null
	emit_event("dialogue_ended", id, choice)
	if not _queue.is_empty():
		play_dialogue(_queue.pop_front())
