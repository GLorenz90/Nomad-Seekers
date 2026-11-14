class_name GuildMenu
extends CounterMenu
## Nomad-2's Guild counter (Part 10, PSO's Hunter's Guild): pick a quest and
## accept it, which starts a quest session (QuestSession: Nomad-2 reloads with
## the quest's people and the teleporter goes to the quest's areas), work
## through its steps, then come back here and report for the reward.
## Reporting or abandoning starts a fresh free-play session. One quest at a
## time; in co-op only the leader takes or abandons one, and the whole party
## must be on Nomad-2. See QuestBook.

## Tests turn this off to stay on the same Nomad-2.
static var restart_sessions := true
## Seconds the message shows before the session changes.
const RESTART_DELAY := 1.4


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
			return _active_item("Report", func(_n: int) -> String:
				var why := QuestSession.party_ready(player.get_tree())
				if why != "":
					return why
				var message := QuestBook.report(save())
				if QuestBook.active(save()).is_empty():
					_new_session_on_close()
				return message, true)
		"abandon":
			return _active_item("Abandon this quest", func(_n: int) -> String:
				if QuestBook.party_save(save()) != save():
					return "Only the party leader can abandon the quest."
				var why := QuestSession.party_ready(player.get_tree())
				if why != "":
					return why
				var title_text: String = QuestBook.active(save()).title
				QuestBook.abandon(save())
				_new_session("Back to free play.")
				return "%s abandoned." % title_text, false)
	return []


func _quest_items() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var s := save()
	var current := QuestBook.active(s)
	for q in QuestBook.all():
		var accepted: bool = not current.is_empty() and current.id == q.id
		if not accepted and not QuestBook.available(s, q):
			continue  # its story flags don't hold (yet)
		var cleared := int(s.quests_cleared.get(String(q.id), 0))
		var item := {"text": "%s%s   %s Oro" % [q.title, "  (accepted)" if accepted else "", _num(int(q.reward))],
			"color": Color(0.75, 1.0, 0.8) if accepted else Color(0.85, 0.92, 1.0),
			"detail": _detail_text(q, cleared), "max": 1,
			"confirm": func(_n: int) -> String: return "Accept %s" % q.title,
			"act": func(_n: int) -> String:
				var why := QuestSession.party_ready(player.get_tree())
				if why != "":
					return why
				var error := QuestBook.accept(s, q.id)
				if error != "":
					return error
				_new_session("Starting the quest.")
				return "%s accepted. The teleporter goes to %s now." % [q.title, String(q.place).to_lower()]}
		if accepted:
			item.error = "You're on this quest: %s. Report here when it's done." % QuestBook.progress_text(s)
		elif not current.is_empty():
			item.error = "You're already on %s. Report or abandon it first." % current.title
		elif QuestBook.party_save(s) != s:
			item.error = "Only the party leader can take a quest."
		list.append(item)
	return list


func _detail_text(q: Dictionary, cleared: int) -> String:
	var places := ", ".join((q.areas as Array).map(func(a): return String(a.name))) if not q.areas.is_empty() else String(q.place)
	return "%s\nClient: %s\n\n%s\n\n%s %s\nWhere: %s\nReward: %s Oro%s" % [q.title, q.client, q.text,
		"Objective:" if q.steps.size() == 1 else "Steps:\n", QuestBook.objective_text(q), places, _num(int(q.reward)),
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


## After a report the ending can be long: the new session starts when the
## counter is closed.
func _new_session_on_close() -> void:
	if not restart_sessions:
		return
	var tree := player.get_tree()
	tree_exited.connect(func() -> void: QuestSession.restart(tree), CONNECT_ONE_SHOT)


## Closes the counter and starts the session that fits the quest (or free
## play) after the message has been read.
func _new_session(_why: String) -> void:
	if not restart_sessions:
		return
	var tree := player.get_tree()
	tree.create_timer(RESTART_DELAY).timeout.connect(func() -> void:
		if is_instance_valid(self):
			close()
		QuestSession.restart(tree))
