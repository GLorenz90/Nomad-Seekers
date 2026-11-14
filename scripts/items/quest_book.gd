class_name QuestBook
extends RefCounted
## The Guild's quests (Part 10, Grayson 2026-11-09: "exactly like PSO";
## quest sessions 2026-11-13).
##
## PSO's Hunter's Guild: pick a quest at the counter and accept it. Accepting
## starts a quest session (QuestSession): the area picks roll again, Nomad-2
## reloads with the quest's people, and the teleporter goes only to the
## quest's areas. Work through its steps in order, then report at the counter
## for the reward. Reporting or abandoning ends the quest session and starts
## a fresh free-play one. One quest at a time.
##
## In co-op the leader's quest is the party's (Grayson 2026-11-13, like PSO):
## a guest's save never holds one; every lookup goes to the party's save, and
## the reward goes to everyone.
##
## A quest (normalised by `normalize`):
##   {"id", "title", "client", "text", "place", "reward",
##    "steps": [{"id", "type", "goal", "count", "enemy", "area"}],
##    "areas": [{"name", "destination", "area", "level"}],
##    "dir": its folder ("" for built-in and single-file quests),
##    "nomad2": its Nomad-2 overlay folder, or ""}
##
## Step types:
## - "clear": clear every wave room of one of the quest's areas (`area`: its
##   area name; any of the quest's maps when blank) in one trip.
## - "defeat": defeat `count` of one enemy (EnemyData file name).
## - "bank_lumidium": bank `count` Lumidium at teleporters.
## - "event": the wiring completes it (complete_step with the step's id), for
##   "talk to Brandt", "bring the part to the foreman", "reach the shrine".
##
## Where quests come from: the built-in ones below, single JSON files in
## res://quests/ (Part 13a's format: one `objective` and one `scene`, read as
## a one-step quest), and quest folders made in the level editor:
##   res://quests/<id>/quest.json   (docs/level_format.md, "Quests")
##   res://quests/<id>/nomad2/      what the quest adds to Nomad-2 (a level
##                                  folder laid over Nomad-2: people, props,
##                                  dialogue, wiring)
##   res://quests/<id>/levels/<x>/  levels only this quest uses
##
## The quest in progress lives in the party's save (SaveData.quest):
##   {"id", "step": index of the current step, "progress": count within it,
##    "flags": {quest flags}, "escorts": [people following the party]}
##
## Also (2026-11-13):
## - Areas can open as the quest goes on: `opens_after` (a step id) and / or
##   `opens_with` (a quest flag). Nomad-2's teleporter lists only open areas,
##   and a banner announces each one that opens.
## - Endings: [{"text", "reward", "if": [{"flag", "is", "story"}],
##   "sets": {story flag: value}}]. The first whose conditions all hold is the
##   ending told at the report (its reward, if given, replaces the quest's;
##   its `sets` become story flags for everyone in the party).
## - Story flags (SaveData.story_flags) outlast the quest. `requires`:
##   [{"flag", "is"}] (story flags) keeps a quest off the Guild's list until
##   they hold.

const QUESTS := [
	{"id": &"arena_trial", "title": "Arena Trial", "client": "Guild instructor",
		"text": "The Guild runs its new Seekers through the test arena. Clear every room in one trip, then report back.",
		"objective": "clear", "count": 1,
		"scene": "res://scenes/arena.tscn", "place": "The test arena", "reward": 600},
	{"id": &"hound_cull", "title": "Hound Cull", "client": "Nomad-2 maintenance",
		"text": "Grub Hounds keep getting into the arena's air ducts. Thin them out: defeat 6.",
		"objective": "defeat", "enemy": "grub_hound", "count": 6,
		"scene": "res://scenes/arena.tscn", "place": "The test arena", "reward": 300},
	{"id": &"crystal_survey", "title": "Crystal Survey", "client": "Survey office",
		"text": "We need samples of the arena's Lumidium. Gather 10 and bank them at a teleporter.",
		"objective": "bank_lumidium", "count": 10,
		"scene": "res://scenes/arena.tscn", "place": "The test arena", "reward": 400},
]

const QUEST_DIR := "res://quests"
const STEP_TYPES := ["clear", "defeat", "bank_lumidium", "event"]
const STEPS_MAX := 32
const AREAS_MAX := 12

static var _loaded: Array = []
static var _loaded_once := false
static var _builtin: Array = []


static func all() -> Array:
	if not _loaded_once:
		reload()
	return _builtin + _loaded


## Reads res://quests: single .json files (one quest or a list) and quest
## folders (quest.json).
static func reload(folder := QUEST_DIR) -> void:
	_loaded_once = true
	_loaded = []
	_builtin = []
	for q in QUESTS:
		_builtin.append(normalize(q))
	if not DirAccess.dir_exists_absolute(folder):
		return
	for file in DirAccess.get_files_at(folder):
		if not file.ends_with(".json"):
			continue
		for q in _parse(folder.path_join(file)):
			_loaded.append(normalize(q))
	for sub in DirAccess.get_directories_at(folder):
		var dir := folder.path_join(sub)
		if FileAccess.file_exists(dir.path_join("quest.json")):
			for q in _parse(dir.path_join("quest.json")):
				_loaded.append(normalize(q, dir))


static func _parse(path: String) -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var list: Array = parsed if parsed is Array else ([parsed] if parsed is Dictionary else [])
	return list.filter(func(q): return q is Dictionary and q.has("id") and (q.has("objective") or q.has("steps")))


## A quest in the current shape, from either format. `dir`: its folder.
static func normalize(q: Dictionary, dir := "") -> Dictionary:
	var out := {"id": StringName(String(q.id)), "title": String(q.get("title", q.id)), "client": String(q.get("client", "")),
		"text": String(q.get("text", "")), "place": String(q.get("place", "")),
		"reward": clampi(int(q.get("reward", 0)), 0, 999999), "dir": dir, "nomad2": "", "steps": [], "areas": [],
		"endings": [], "requires": _conditions(q.get("requires", []))}
	for e in (q.get("endings", []) as Array).slice(0, 16) if q.get("endings") is Array else []:
		if e is Dictionary:
			var sets := {}
			if e.get("sets") is Dictionary:
				for k in e.sets:
					if String(k) != "":
						sets[String(k)] = e.sets[k]
			out.endings.append({"text": String(e.get("text", "")), "reward": int(e.reward) if e.has("reward") else -1,
				"if": _conditions(e.get("if", [])), "sets": sets})
	if dir != "" and LevelData.is_level_dir(dir.path_join("nomad2")):
		out.nomad2 = dir.path_join("nomad2")
	if q.has("steps"):
		for s in (q.steps as Array).slice(0, STEPS_MAX):
			if s is Dictionary:
				out.steps.append(_step(s, out.steps.size()))
		for a in (q.get("areas", []) as Array).slice(0, AREAS_MAX):
			if a is Dictionary:
				var area := _area(a, dir)
				if not area.is_empty():
					out.areas.append(area)
	else:
		# Part 10 / 13a: one objective, one scene.
		var step := {"id": String(q.get("key", "main")), "type": String(q.objective), "count": q.get("count", 1),
			"enemy": q.get("enemy", ""), "goal": q.get("goal", "")}
		out.steps.append(_step(step, 0))
		var scene := String(q.get("scene", ""))
		if scene != "":
			out.areas.append({"name": out.place if out.place != "" else Maps.display_name(scene), "destination": scene,
				"area": scene.trim_prefix("area:") if scene.begins_with("area:") else "", "level": ""})
	if out.place == "" and not out.areas.is_empty():
		out.place = out.areas[0].name
	return out


## [{"flag", "is", "story"}] with blank flags dropped.
static func _conditions(list) -> Array:
	var out := []
	if list is Array:
		for c in list:
			if c is Dictionary and String(c.get("flag", "")) != "":
				out.append({"flag": String(c.flag), "is": c.get("is", true), "story": bool(c.get("story", false))})
	return out


static func _step(s: Dictionary, index: int) -> Dictionary:
	var type := String(s.get("type", "event"))
	return {"id": String(s.get("id", "step_%d" % (index + 1))), "type": type if STEP_TYPES.has(type) else "event",
		"goal": String(s.get("goal", "")), "count": clampi(int(s.get("count", 1)), 1, 9999),
		"enemy": String(s.get("enemy", "")), "area": String(s.get("area", ""))}


## An area of a quest: {"area": "forest_1"} (a fresh pick from that area's
## folder), {"area": "forest_1", "level": "res://levels/forest_1/glade"} (that
## level), or {"quest_level": "glade"} (the quest's own levels/glade).
static func _area(a: Dictionary, dir: String) -> Dictionary:
	var name := String(a.get("name", ""))
	var own := String(a.get("quest_level", ""))
	if own != "":
		if dir == "" or own.contains("..") or own.contains("/"):
			return {}
		var path := dir.path_join("levels").path_join(own)
		return _opens(a, {"name": name if name != "" else Maps.display_name(path), "destination": path, "area": "", "level": path})
	var area := String(a.get("area", ""))
	if area == "" or area.contains("..") or area.contains("/"):
		return {}
	var level := String(a.get("level", ""))
	if level != "" and not level.begins_with(Maps.AREA_ROOT.path_join(area) + "/"):
		level = ""  # only a level from that area's own folder
	return _opens(a, {"name": name if name != "" else area.capitalize(), "destination": "area:" + area, "area": area, "level": level})


## When an area opens: after a step and / or once a quest flag is on.
static func _opens(a: Dictionary, out: Dictionary) -> Dictionary:
	out.opens_after = String(a.get("opens_after", ""))
	out.opens_with = String(a.get("opens_with", ""))
	return out


## Reads one quest folder from anywhere (the editor's playtest) and adds it,
## replacing a quest with the same id. Returns it ({} if it isn't a quest).
static func add_folder(dir: String) -> Dictionary:
	if not _loaded_once:
		reload()
	var found := _parse(dir.path_join("quest.json"))
	if found.is_empty():
		return {}
	var q := normalize(found[0], dir)
	_loaded = _loaded.filter(func(old): return old.id != q.id)
	_loaded.append(q)
	return q


## Whether the Guild offers a quest: its required story flags hold.
static func available(save: SaveData, q: Dictionary) -> bool:
	for c in q.get("requires", []):
		if bool(story_flag(save, String(c.flag))) != bool(c.is):
			return false
	return true


static func get_quest(id: StringName) -> Dictionary:
	for q in all():
		if q.id == id:
			return q
	return {}


# --- The party's quest ------------------------------------------------------------------------

## The save that holds the party's quest: the leader's when `save` is a
## guest's (Grayson 2026-11-13: the leader's quest is the party's).
static func party_save(save: SaveData) -> SaveData:
	if save == null:
		return null
	for g in Party.guests:
		if g.get("save") == save:
			return Session.save if Session.save else save
	return save


## The accepted quest's definition ({} when none).
static func active(save: SaveData) -> Dictionary:
	var s := party_save(save)
	if s == null or s.quest.is_empty():
		return {}
	return get_quest(StringName(s.quest.get("id", "")))


static func state(save: SaveData) -> Dictionary:
	var s := party_save(save)
	return s.quest if s else {}


static func step_index(save: SaveData) -> int:
	return int(state(save).get("step", 0))


## The step being worked on ({} when done or no quest).
static func current_step(save: SaveData) -> Dictionary:
	var q := active(save)
	var i := step_index(save)
	return q.steps[i] if not q.is_empty() and i < q.steps.size() else {}


static func step_done(save: SaveData, step_id: String) -> bool:
	var q := active(save)
	if q.is_empty():
		return false
	for i in q.steps.size():
		if String(q.steps[i].id) == step_id:
			return step_index(save) > i
	return false


static func progress(save: SaveData) -> int:
	return int(state(save).get("progress", 0))


static func is_complete(save: SaveData) -> bool:
	var q := active(save)
	return not q.is_empty() and step_index(save) >= q.steps.size()


static func flag(save: SaveData, name: String) -> Variant:
	return (state(save).get("flags", {}) as Dictionary).get(name, false)


static func set_flag(save: SaveData, name: String, value: Variant) -> void:
	var s := state(save)
	if s.is_empty():
		return
	var before := open_area_names(save)
	if not s.has("flags"):
		s.flags = {}
	s.flags[name] = value
	_announce_opened(save, before)


# --- Story flags (outlast a quest) --------------------------------------------------------------

static func story_flag(save: SaveData, name: String) -> Variant:
	var s := party_save(save)
	return s.story_flags.get(name, false) if s else false


## Sets a story flag for everyone in the party (they were all there).
static func set_story_flag(save: SaveData, name: String, value: Variant) -> void:
	var s := party_save(save)
	if s == null or name == "":
		return
	for member in party_saves(s):
		member.story_flags[name] = value


# --- Areas opening ----------------------------------------------------------------------------

## Whether one of the quest's areas is open yet.
static func area_open(save: SaveData, a: Dictionary) -> bool:
	if String(a.get("opens_after", "")) != "" and not step_done(save, String(a.opens_after)):
		return false
	if String(a.get("opens_with", "")) != "" and not bool(flag(save, String(a.opens_with))):
		return false
	return true


static func open_areas(save: SaveData) -> Array:
	return (active(save).get("areas", []) as Array).filter(func(a): return area_open(save, a))


static func open_area_names(save: SaveData) -> Array:
	return open_areas(save).map(func(a): return String(a.name))


static func _announce_opened(save: SaveData, before: Array) -> void:
	var opened := open_area_names(save).filter(func(n): return not before.has(n))
	if not opened.is_empty():
		QuestSession.announce("The teleporter can go to %s now." % ", ".join(opened))


## "" when accepted, or why not. Only the leader takes quests in co-op.
static func accept(save: SaveData, id: StringName) -> String:
	if party_save(save) != save:
		return "Only the party leader can take a quest."
	if not active(save).is_empty():
		return "You're already on a quest: %s. Report or abandon it first." % active(save).title
	if get_quest(id).is_empty():
		return "No such quest."
	save.quest = {"id": String(id), "step": 0, "progress": 0, "flags": {}, "escorts": []}
	return ""


static func abandon(save: SaveData) -> void:
	var s := party_save(save)
	if s:
		s.quest = {}


## Counts progress on the current step. Returns "" (nothing happened),
## "step" (a step was completed and another is next) or "done" (the last step
## was completed). Listeners hear step_completed (QuestSession).
static func record(save: SaveData, type: String, key: String = "", amount: int = 1) -> String:
	var s := party_save(save)
	var step := current_step(s)
	if step.is_empty() or String(step.type) != type:
		return ""
	match type:
		"defeat":
			if key != String(step.enemy):
				return ""
		"clear":
			if not _clears_step(s, step, key):
				return ""
		"event":
			if key != String(step.id):
				return ""
	s.quest.progress = mini(progress(s) + amount, int(step.count) if type != "event" else 1)
	if progress(s) < (int(step.count) if type != "event" else 1):
		return ""
	return _advance(s, String(step.id))


## Completes the current step if it's `step_id` (wiring: complete_step).
static func complete_step(save: SaveData, step_id: String) -> String:
	var step := current_step(save)
	if step.is_empty() or String(step.id) != step_id:
		return ""
	return _advance(party_save(save), step_id)


static func _advance(s: SaveData, step_id: String) -> String:
	var before := open_area_names(s)
	s.quest.step = step_index(s) + 1
	s.quest.progress = 0
	QuestSession.step_completed(step_id)
	_announce_opened(s, before)
	return "done" if is_complete(s) else "step"


## Clearing counts on the step's area (or any of the quest's maps).
static func _clears_step(save: SaveData, step: Dictionary, map_id: String) -> bool:
	var q := active(save)
	for a in q.areas:
		if String(step.area) != "" and String(a.area) != String(step.area) and String(a.destination) != String(step.area):
			continue
		if map_id == String(a.destination) or map_id == Maps.resolve(String(a.destination)):
			return true
	return false


## The banner for what record / complete_step returned ("" for nothing).
static func news(save: SaveData, result: String) -> String:
	match result:
		"done":
			return "Quest complete: report to the Guild"
		"step":
			var next := current_step(save)
			return "Quest updated: %s" % step_text(save, next) if not next.is_empty() else ""
	return ""


## Pays the reward to every Seeker in the party and clears the quest.
## Returns the message.
static func report(save: SaveData) -> String:
	var s := party_save(save)
	var q := active(s)
	if q.is_empty():
		return "You have no quest."
	if not is_complete(s):
		return "%s isn't done yet (%s)." % [q.title, progress_text(s)]
	var ending := ending_for(s)
	var reward := int(q.reward) if int(ending.get("reward", -1)) < 0 else int(ending.reward)
	var short := 0
	for member in party_saves(s):
		var paid := member.inventory.add_oro(reward)
		short += reward - paid
		member.quests_cleared[String(q.id)] = int(member.quests_cleared.get(String(q.id), 0)) + 1
	for k in ending.get("sets", {}):
		set_story_flag(s, String(k), ending.sets[k])
	s.quest = {}
	var told := String(ending.get("text", ""))
	return "%s complete.%s\n\nReward: %d Oro%s." % [q.title, "" if told == "" else "\n\n" + told, reward,
		"" if short == 0 else " (%d didn't fit: Oro is full)" % short]


## The ending the quest has reached ({} for none): the first whose flags all
## hold (quest flags, or story flags with "story").
static func ending_for(save: SaveData) -> Dictionary:
	for e in active(save).get("endings", []):
		var ok := true
		for c in e.get("if", []):
			var value: Variant = story_flag(save, String(c.flag)) if bool(c.story) else flag(save, String(c.flag))
			if bool(value) != bool(c.is):
				ok = false
				break
		if ok:
			return e
	return {}


## The leader's save and every guest's (the party's saves; just `save` alone).
static func party_saves(save: SaveData) -> Array[SaveData]:
	var out: Array[SaveData] = [save]
	if party_save(save) == Session.save and save == Session.save:
		for g in Party.guests:
			if g.get("save") is SaveData and not out.has(g.save):
				out.append(g.save)
	return out


# --- Text -------------------------------------------------------------------------------------

static func progress_text(save: SaveData) -> String:
	var q := active(save)
	if q.is_empty():
		return ""
	if is_complete(save):
		return "done"
	var step := current_step(save)
	var where := "step %d of %d" % [step_index(save) + 1, q.steps.size()] if q.steps.size() > 1 else ""
	var count := ""
	match String(step.type):
		"defeat":
			count = "%d / %d %s" % [progress(save), int(step.count), _enemy_name(String(step.enemy))]
		"bank_lumidium":
			count = "%d / %d Lumidium banked" % [progress(save), int(step.count)]
		"clear":
			count = "rooms not cleared yet"
		_:
			count = "not done yet"
	return count if where == "" else "%s: %s" % [where, count]


## What a step asks for, in words.
static func step_text(_save: SaveData, step: Dictionary) -> String:
	if String(step.get("goal", "")) != "":
		return String(step.goal)
	match String(step.get("type", "")):
		"clear":
			return "Clear every room%s in one trip." % ("" if String(step.area) == "" else " in " + String(step.area).capitalize())
		"defeat":
			return "Defeat %d %s." % [int(step.count), _enemy_name(String(step.enemy))]
		"bank_lumidium":
			return "Bank %d Lumidium at teleporters." % int(step.count)
	return "Complete the objective."


## The steps, numbered, for the Guild's quest details.
static func objective_text(q: Dictionary) -> String:
	if q.steps.size() == 1:
		return step_text(null, q.steps[0])
	var lines := PackedStringArray()
	for i in q.steps.size():
		lines.append("%d. %s" % [i + 1, step_text(null, q.steps[i])])
	return "\n".join(lines)


static func _enemy_name(file: String) -> String:
	var data := load("res://data/enemies/%s.tres" % file) as EnemyData if ResourceLoader.exists("res://data/enemies/%s.tres" % file) else null
	return (data.display_name + "s") if data else file
