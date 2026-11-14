class_name CoopDirector
extends Node
## The session's maps and local co-op (Part 12; persistent maps since
## 2026-11-12).
##
## Maps persist for the whole session, like PSO (Grayson 2026-11-12): from
## the first trip until quitting to the title, every map anyone has been to
## stays as it was left (enemies stay dead, items stay where they lie, rooms
## stay cleared). A map nobody is on is parked: its scripts, physics and
## navigation stop and it isn't drawn. A Seeker arriving wakes it.
##
## Lives at the root of the scene tree from the first trip or join until the
## session ends (or, with no trip yet, until a party is back to one Seeker on
## the window's own level). It owns:
## - the split screen (one pane per Seeker, kept across map changes; alone
##   that's one full-window pane);
## - "hosted" maps: every map other than the window's own scene runs inside a
##   SubViewport with its own World3D (own physics, navigation and groups,
##   kept apart by Scope). Panes look into the world their Seeker is in.
##
## Travelling (teleporters): only the Seeker who travels goes (Grayson
## 2026-11-09). If the destination is open (awake or parked) they join it;
## otherwise it opens. A Teleportal sends them to a set spot
## (Party.arrivals).
##
## Joining: Start on a controller nobody plays with opens a character picker
## in a new pane; the guest appears on the leader's map.

## Hosted maps don't draw themselves (only the panes do).
const HOST_SIZE := Vector2i(2, 2)

var split: SplitScreen
## Hosted maps: scene path -> the level node (its parent is the SubViewport).
var hosts := {}
## Controllers picking a character: device -> SeekerPane.
var _joining := {}


static func find(tree: SceneTree) -> CoopDirector:
	return tree.root.get_node_or_null("CoopDirector") as CoopDirector


static func ensure(tree: SceneTree) -> CoopDirector:
	var d := find(tree)
	if d:
		return d
	d = CoopDirector.new()
	d.name = "CoopDirector"
	tree.root.add_child(d)
	return d


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	split = SplitScreen.new()
	split.name = "SplitScreen"
	add_child(split)
	get_tree().root.disable_3d = true  # only the panes draw the world now


# --- Levels -------------------------------------------------------------------------------

## The level node for a map that's open (the window's or hosted), or null.
func level_for(path: String) -> Node:
	if hosts.has(path) and is_instance_valid(hosts[path]):
		return hosts[path]
	var scene := get_tree().current_scene
	if scene and Maps.id_of(scene) == path and scene.has_method("spawn_member"):
		return scene
	return null


func _root_path() -> String:
	var scene := get_tree().current_scene
	return Maps.id_of(scene) if scene else ""


## Opens a map in its own world. Its level script spawns whoever is on it.
func host(path: String) -> Node:
	var viewport := SubViewport.new()
	viewport.name = "Host_" + path.get_file().get_basename()
	viewport.own_world_3d = true
	viewport.size = HOST_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.audio_listener_enable_3d = false
	add_child(viewport)
	var level := Maps.instantiate(path)
	hosts[path] = level
	viewport.add_child(level)
	return level


# --- Parking (2026-11-12) -------------------------------------------------------------------

## Every open map: the window's level and the hosted ones.
func open_levels() -> Array[Node]:
	var out: Array[Node] = []
	var scene := get_tree().current_scene
	if scene and scene.has_method("spawn_member"):
		out.append(scene)
	for path in hosts:
		if is_instance_valid(hosts[path]):
			out.append(hosts[path])
	return out


## Parks every map with nobody on it and wakes the rest.
func refresh_parking() -> void:
	for level in open_levels():
		set_parked(level, Party.members_on(Maps.id_of(level)).is_empty())


static func is_parked(level: Node) -> bool:
	return level.process_mode == Node.PROCESS_MODE_DISABLED


## A parked map keeps everything but stops: no processing, physics or
## navigation (hosted maps are never drawn by themselves; the window's own
## 3D is off while the director runs). Waking it is a new visit (shops
## restock, like PSO's on each trip back).
func set_parked(level: Node, parked: bool) -> void:
	if is_parked(level) == parked:
		return
	level.process_mode = Node.PROCESS_MODE_DISABLED if parked else Node.PROCESS_MODE_INHERIT
	var world := (level.get_viewport() as Viewport).find_world_3d()
	if world:
		PhysicsServer3D.space_set_active(world.space, not parked)
		NavigationServer3D.map_set_active(world.navigation_map, not parked)
	if not parked and level.has_method("new_visit"):
		level.call("new_visit")


func _drop_host(path: String) -> void:
	var level: Node = hosts.get(path)
	hosts.erase(path)
	if level and is_instance_valid(level):
		var viewport := level.get_parent() as SubViewport
		# Panes still looking into that world look away first.
		for pane in (split.panes if is_instance_valid(split) else []):
			if pane.sub.world_3d == viewport.find_world_3d():
				pane.sub.world_3d = get_tree().root.find_world_3d()
		viewport.queue_free()


# --- Panes --------------------------------------------------------------------------------

## Puts a Seeker's HUD, menu and view into their pane (made if needed).
func attach(seeker: Player, rig: CameraRig, hud: Node, menu: Node, markers: TargetMarkers) -> SeekerPane:
	var who := Party.who_of(seeker)
	var pane := split.pane_for_who(who)
	if pane == null:
		pane = split.add_pane(seeker.input, who)
	pane.input = seeker.input
	pane.attach(seeker, rig)
	seeker.ui_parent = pane.sub
	for node: Node in [hud, menu]:
		if node.get_parent() != pane.sub:
			node.reparent(pane.sub)
	markers.render_layers = SeekerPane.marker_layer(seeker.input.slot)
	return pane


## The input a party member plays with while the party is up.
static func input_for(who: int) -> PlayerInput:
	if who == Party.LEADER:
		if Party.leader_pad < 0:
			Party.leader_pad = 0
		return PlayerInput.bind(0, Party.leader_pad, true)
	return PlayerInput.bind(Party.slot_of(who), who, false)


# --- Joining ------------------------------------------------------------------------------

## Start on a controller nobody plays with opens the character picker for it.
func _input(event: InputEvent) -> void:
	CoopDirector.watch_for_join(self, event)


## Shared by levels (before any director exists) and the director.
static func watch_for_join(from: Node, event: InputEvent) -> void:
	var pad_event := event is InputEventJoypadButton \
		or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5)
	if not pad_event:
		return
	var start := event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed \
		and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START
	if Party.leader_pad < 0:
		Party.leader_pad = event.device
		return
	if not start or Party.has_device(event.device):
		return
	var director := CoopDirector.find(from.get_tree())
	if director and director._joining.has(event.device):
		return
	from.get_viewport().set_input_as_handled()
	if director == null:
		var level := from.get_tree().current_scene
		if level == null or not level.has_method("spawn_member"):
			return
		director = CoopDirector.begin(level)
	director.start_join(event.device)


## Turns a solo level into a party: the director takes over its leader.
static func begin(level: Node) -> CoopDirector:
	var director := ensure(level.get_tree())
	Party.leader_map = Maps.id_of(level)
	level.call("adopt_director", director)
	return director


func start_join(device: int) -> SeekerPane:
	if device < 0 or Party.size() + _joining.size() >= PlayerInput.MAX_PLAYERS:
		return null
	var listen := PlayerInput.new()
	listen.slot = PlayerInput.MAX_PLAYERS  # never polled; owns() filters by device
	listen.device = device
	listen.keyboard = false
	var pane := split.add_pane(listen, device)
	var picker := JoinPicker.new()
	pane.sub.add_child(picker)
	picker.open(Party.slots_in_use())
	picker.picked.connect(func(slot: int): _finish_join(device, slot, pane, picker))
	picker.cancelled.connect(func(): _cancel_join(device, pane))
	_joining[device] = pane
	return pane


func _finish_join(device: int, slot: int, pane: SeekerPane, picker: JoinPicker) -> void:
	var guest := Party.join(device, slot)
	if guest.is_empty():
		picker.show_message("That character can't join.")
		return
	_joining.erase(device)
	picker.queue_free()
	guest["map"] = Party.leader_map
	var level := level_for(Party.leader_map)
	if level:
		level.call("spawn_member", device)
		level.call("banner", "%s joined the party" % (guest.save as SaveData).character.seeker_name)
	else:
		split.remove_pane(pane)


func _cancel_join(device: int, pane: SeekerPane) -> void:
	_joining.erase(device)
	split.remove_pane(pane)
	maybe_end()


## Joining controllers (for tests).
func joining() -> Dictionary:
	return _joining


# --- Travelling ---------------------------------------------------------------------------

## A Seeker takes a teleporter on their own. The first trip of a session
## starts the director, so the map being left is kept. `arrive_at` (a
## Teleportal's spot) replaces the map's spawn point.
static func travel(seeker: Player, destination: String, arrive_at := Vector3.INF) -> void:
	var director := find(seeker.get_tree())
	if director == null:
		var level := Scope.level(seeker)
		if level == null or not level.has_method("adopt_director"):
			return
		director = begin(level)
	if arrive_at != Vector3.INF:
		Party.arrivals[Party.who_of(seeker)] = arrive_at
	director.move(seeker, Maps.resolve(destination))


func move(seeker: Player, destination: String) -> void:
	var who := Party.who_of(seeker)
	var from_level := Scope.level(seeker)
	var from_path := Maps.id_of(from_level) if from_level else ""
	if from_path == destination or destination == "":
		Party.arrivals.erase(who)
		return
	seeker.save_game()
	Party.set_map(who, destination)
	if from_level:
		from_level.call("remove_seeker", seeker)
	var target := level_for(destination)
	if target:
		set_parked(target, false)
		target.call("spawn_member", who)
	else:
		host(destination)
	refresh_parking()


# --- Leaving and ending ----------------------------------------------------------------------

## A guest leaves (Options tab): saved, then their Seeker and pane go.
func leave(seeker: Player) -> void:
	var who := Party.who_of(seeker)
	if who == Party.LEADER:
		return
	var level := Scope.level(seeker)
	var path := Maps.id_of(level) if level else ""
	seeker.save_game()
	var name_was := seeker.save.character.seeker_name
	if level:
		level.call("remove_seeker", seeker)
		level.call("banner", "%s left the party" % name_was)
	Party.leave(who)
	var pane := split.pane_for_who(who)
	if pane:
		split.remove_pane(pane)
	refresh_parking()
	maybe_end()


## Back to plain single player once the leader is alone on the window's own
## level and no other map is open. After the session's first trip, other maps
## stay open, so a lone Seeker keeps a one-pane split until the title.
func maybe_end() -> void:
	if Party.is_active() or not _joining.is_empty() or not hosts.is_empty():
		return
	var level := get_tree().current_scene
	if level == null or not level.has_method("release_director"):
		return
	level.call("release_director")
	split.queue_free()
	get_tree().root.disable_3d = false
	queue_free()


## A new session (QuestSession): every hosted map closes; the window's level
## is replaced by Nomad-2, which spawns the party again.
func close_hosted() -> void:
	for path in hosts.keys():
		_drop_host(path)


## Quit to title: every map and pane goes (panes first, so none is left
## looking into a world that's gone).
func shutdown() -> void:
	if is_instance_valid(split):
		split.free()
	for path in hosts.keys():
		_drop_host(path)
	get_tree().root.disable_3d = false
	queue_free()
