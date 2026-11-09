class_name GuildMenu
extends CounterMenu
## Nomad-2's Guild counter (Part 10, PSO's Hunter's Guild): pick a quest and
## accept it, head out through the teleporter (it lists the quest first),
## then come back here and report for the reward. One quest at a time; it can
## be abandoned here. See QuestBook.


func _init() -> void:
	super()
	title = "Guild"
	greeting = "Welcome to the Seekers' Guild. Looking for work?"


func commands() -> Array:
	return [["Quests", "quests"], ["Report", "report"], ["Abandon quest", "abandon"]]


func header_text() -> String:
	var s := save()
	var q := QuestBook.active(s)
	var on := "No quest" if q.is_empty() else "On: %s (%s)" % [q.title, QuestBook.progress_text(s)]
	return "Oro %s\n%s" % [_num(s.inventory.oro), on]


func items_for(command_id: String) -> Array[Dictionary]:
	match command_id:
		"quests":
			return _quest_items()
		"report":
			return _active_item("Report", func(_n: int) -> String: return QuestBook.report(save()), true)
		"abandon":
			return _active_item("Abandon this quest", func(_n: int) -> String:
				var title_text: String = QuestBook.active(save()).title
				QuestBook.abandon(save())
				return "%s abandoned." % title_text, false)
	return []


func _quest_items() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var s := save()
	var current := QuestBook.active(s)
	for q in QuestBook.all():
		var accepted: bool = not current.is_empty() and current.id == q.id
		var cleared := int(s.quests_cleared.get(String(q.id), 0))
		var item := {"text": "%s%s   %s Oro" % [q.title, "  (accepted)" if accepted else "", _num(int(q.reward))],
			"color": Color(0.75, 1.0, 0.8) if accepted else Color(0.85, 0.92, 1.0),
			"detail": _detail_text(q, cleared), "max": 1,
			"confirm": func(_n: int) -> String: return "Accept %s" % q.title,
			"act": func(_n: int) -> String:
				var error := QuestBook.accept(s, q.id)
				return error if error != "" else "%s accepted. Take the teleporter to %s." % [q.title, String(q.place).to_lower()]}
		if accepted:
			item.error = "You're on this quest: %s. Report here when it's done." % QuestBook.progress_text(s)
		elif not current.is_empty():
			item.error = "You're already on %s. Report or abandon it first." % current.title
		list.append(item)
	return list


func _detail_text(q: Dictionary, cleared: int) -> String:
	return "%s\nClient: %s\n\n%s\n\nObjective: %s\nWhere: %s\nReward: %s Oro%s" % [q.title, q.client, q.text,
		QuestBook.objective_text(q), q.place, _num(int(q.reward)),
		"\nCompleted %d time%s." % [cleared, "" if cleared == 1 else "s"] if cleared > 0 else ""]


## The accepted quest as one entry, with `confirm` as its button.
func _active_item(confirm: String, act: Callable, needs_complete: bool) -> Array[Dictionary]:
	var s := save()
	var q := QuestBook.active(s)
	if q.is_empty():
		return []
	var item := {"text": "%s   (%s)" % [q.title, QuestBook.progress_text(s)], "color": Color(0.75, 1.0, 0.8),
		"detail": _detail_text(q, int(s.quests_cleared.get(String(q.id), 0))), "max": 1,
		"confirm": func(_n: int) -> String: return confirm, "act": act}
	if needs_complete and not QuestBook.is_complete(s):
		item.error = "%s isn't done yet (%s)." % [q.title, QuestBook.progress_text(s)]
	return [item]
