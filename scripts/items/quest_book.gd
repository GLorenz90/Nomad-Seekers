class_name QuestBook
extends RefCounted
## The Guild's quests (Part 10, Grayson 2026-11-09: "exactly like PSO").
##
## PSO's Hunter's Guild: pick a quest at the counter and accept it, go down
## through the teleporter (it now offers the quest's destination first),
## complete it, then come back to the counter and report for the reward.
## One quest at a time; it can be abandoned at the counter. The quest stays
## active (with its progress) until it's reported or abandoned, and is kept
## in the save (SaveData.quest).
##
## Objectives:
## - "clear": clear every wave room of the destination in one trip.
## - "defeat": defeat `count` of one enemy (EnemyData file name).
## - "bank_lumidium": bank `count` Lumidium at teleporters.
## - "event" (Part 13a): a level's wiring completes it (complete_objective
##   with this quest's `key`), for "reach the shrine", "talk to Brandt"...
##
## Part 13a: `scene` can be any map (Maps): a scene, a data level folder or
## "area:<area>" (whatever level the session picked there). Quests made in
## the level editor are JSON files in res://quests/ (docs/level_format.md),
## listed after the built-in ones.

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

static var _loaded: Array = []
static var _loaded_once := false


static func all() -> Array:
	if not _loaded_once:
		reload()
	return QUESTS + _loaded


## Reads res://quests/*.json (each file is one quest or a list of them).
static func reload(folder := QUEST_DIR) -> void:
	_loaded_once = true
	_loaded = []
	for file in DirAccess.get_files_at(folder):
		if not file.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(file)))
		var list: Array = parsed if parsed is Array else ([parsed] if parsed is Dictionary else [])
		for q in list:
			if q is Dictionary and q.has("id") and q.has("objective"):
				var quest: Dictionary = {"title": String(q.id), "client": "", "text": "",
					"count": 1, "scene": "", "place": "", "reward": 0}
				quest.merge(q, true)
				quest.id = StringName(String(q.id))
				_loaded.append(quest)


static func get_quest(id: StringName) -> Dictionary:
	for q in all():
		if q.id == id:
			return q
	return {}


## The accepted quest's definition ({} when none).
static func active(save: SaveData) -> Dictionary:
	if save == null or save.quest.is_empty():
		return {}
	return get_quest(StringName(save.quest.get("id", "")))


static func progress(save: SaveData) -> int:
	return int(save.quest.get("progress", 0)) if save else 0


static func is_complete(save: SaveData) -> bool:
	var q := active(save)
	return not q.is_empty() and progress(save) >= int(q.count)


## "" when accepted, or why not.
static func accept(save: SaveData, id: StringName) -> String:
	if not active(save).is_empty():
		return "You're already on a quest: %s. Report or abandon it first." % active(save).title
	if get_quest(id).is_empty():
		return "No such quest."
	save.quest = {"id": String(id), "progress": 0}
	return ""


static func abandon(save: SaveData) -> void:
	save.quest = {}


## Counts progress. Returns true when this completed the quest.
static func record(save: SaveData, objective: String, key: String = "", amount: int = 1) -> bool:
	var q := active(save)
	if q.is_empty() or q.objective != objective or is_complete(save):
		return false
	if objective == "defeat" and key != String(q.enemy):
		return false
	if objective == "clear" and key != String(q.scene) and key != Maps.resolve(String(q.scene)):
		return false
	if objective == "event" and key != String(q.get("key", "")):
		return false
	save.quest.progress = mini(progress(save) + amount, int(q.count))
	return is_complete(save)


## Pays the reward for a completed quest and clears it. Returns the message.
static func report(save: SaveData) -> String:
	var q := active(save)
	if q.is_empty():
		return "You have no quest."
	if not is_complete(save):
		return "%s isn't done yet (%s)." % [q.title, progress_text(save)]
	var paid := save.inventory.add_oro(int(q.reward))
	save.quests_cleared[String(q.id)] = int(save.quests_cleared.get(String(q.id), 0)) + 1
	save.quest = {}
	return "%s complete. Reward: %d Oro%s." % [q.title, int(q.reward),
		"" if paid == int(q.reward) else " (%d didn't fit: Oro is full)" % (int(q.reward) - paid)]


static func progress_text(save: SaveData) -> String:
	var q := active(save)
	if q.is_empty():
		return ""
	match String(q.objective):
		"clear":
			return "done" if is_complete(save) else "rooms not cleared yet"
		"defeat":
			return "%d / %d %s" % [progress(save), int(q.count), _enemy_name(String(q.enemy))]
		"bank_lumidium":
			return "%d / %d Lumidium banked" % [progress(save), int(q.count)]
		"event":
			return "done" if is_complete(save) else "not done yet"
	return ""


static func objective_text(q: Dictionary) -> String:
	match String(q.objective):
		"clear":
			return "Clear every room in %s in one trip." % String(q.place).to_lower()
		"defeat":
			return "Defeat %d %s." % [int(q.count), _enemy_name(String(q.enemy))]
		"bank_lumidium":
			return "Bank %d Lumidium at teleporters." % int(q.count)
		"event":
			return String(q.get("goal", "Complete the objective."))
	return ""


static func _enemy_name(file: String) -> String:
	var data := load("res://data/enemies/%s.tres" % file) as EnemyData
	return (data.display_name + "s") if data else file
