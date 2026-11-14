class_name QuestSession
extends RefCounted
## Quests are sessions, like PSO (Grayson 2026-11-13). Accepting a quest at
## the Guild starts a quest session: every map closes, the area picks roll
## again (an area the quest names a level for gets that level), Nomad-2
## reloads with the quest's people (its nomad2 overlay, HubLevel), and the
## hub teleporter offers only the quest's areas. Reporting or abandoning ends
## it the same way, into a fresh free-play session.
##
## The whole party must be on Nomad-2 to start or end one (everyone is moved
## together, PSO's quest counter rule).


## The party's quest right now ({} in free play).
static func quest() -> Dictionary:
	return QuestBook.active(Session.save)


static func is_active() -> bool:
	return not quest().is_empty()


## Where the hub teleporter can go in this quest session: [[name, destination]].
static func destinations() -> Array:
	var out := []
	for a in QuestBook.open_areas(Session.save):
		out.append([String(a.name), String(a.destination)])
	return out


## A banner on every map with a Seeker on it ("The teleporter can go to...").
static func announce(text: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var told := {}
	for p in tree.get_nodes_in_group("player"):
		var level := Scope.level(p)
		if level and not told.has(level) and level.has_method("banner"):
			told[level] = true
			level.call_deferred("banner", text)


## Fresh picks for a session (free play: q = {}). A quest's named levels win.
static func roll_picks(q: Dictionary) -> void:
	Maps.new_session()
	for a in q.get("areas", []):
		if String(a.area) != "" and String(a.level) != "" and LevelData.is_level_dir(String(a.level)):
			Maps.picks[String(a.area)] = String(a.level)


## "" when the whole party is on Nomad-2, or why not.
static func party_ready(tree: SceneTree) -> String:
	var here := 0
	for p in tree.get_nodes_in_group("player"):
		if Maps.id_of(Scope.level(p)) == Session.HUB_SCENE:
			here += 1
	return "" if here >= Party.size() else "The whole party has to be on Nomad-2 first."


## Starts the session that fits the party's quest (a quest session, or free
## play with none): new picks, every map closed, Nomad-2 again.
static func restart(tree: SceneTree) -> void:
	for p in tree.get_nodes_in_group("player"):
		(p as Player).save_game()
	roll_picks(quest())
	Teleportals.new_session()
	for who in [Party.LEADER] + Party.guests.map(func(g): return int(g.device)):
		Party.set_map(who, Session.HUB_SCENE)
		Party.arrivals.erase(who)
	var director := CoopDirector.find(tree)
	if director:
		director.close_hosted()
	tree.change_scene_to_file.call_deferred(Session.HUB_SCENE)


## A step was completed: every level's wiring hears step_completed (people
## on Nomad-2 change, doors in a quest level open...).
static func step_completed(step_id: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for events in _all_events(tree):
		events.call_deferred("on_step_completed", step_id)


## Every LevelEvents in the tree, hosted maps included (each map has its own
## groups, so look under every SubViewport too).
static func _all_events(tree: SceneTree) -> Array:
	var out := []
	for n in tree.root.find_children("LevelEvents", "LevelEvents", true, false):
		out.append(n)
	return out


# --- Escorts ----------------------------------------------------------------------------------

## People following the party (by person id), with how they look, so a
## quest level can bring them along: [{"id", "name", "look"}].
static func escorts() -> Array:
	return QuestBook.state(Session.save).get("escorts", [])


static func start_escort(spec: Dictionary) -> void:
	var s := QuestBook.state(Session.save)
	if s.is_empty():
		return
	if not s.has("escorts"):
		s.escorts = []
	for e in s.escorts:
		if String(e.id) == String(spec.id):
			return
	s.escorts.append({"id": String(spec.id), "name": String(spec.get("name", "")), "look": spec.get("look", {})})


static func stop_escort(id: String) -> void:
	var s := QuestBook.state(Session.save)
	if s.has("escorts"):
		s.escorts = (s.escorts as Array).filter(func(e): return String(e.id) != id)
