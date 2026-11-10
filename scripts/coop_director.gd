class_name CoopDirector
extends Node
## Local co-op across maps (Part 12, Grayson 2026-11-09: "one player should be
## able to go to the hub to sell items while the other player explores").
##
## Lives at the root of the scene tree from the first join until the party is
## back to one Seeker on the window's own level. It owns:
## - the split screen (one pane per party member, kept across map changes);
## - "hosted" maps: a level any party member is on that isn't the window's own
##   scene runs inside a SubViewport with its own World3D (own physics,
##   navigation and groups, kept apart by Scope). Its panes look into that
##   world.
##
## Travelling (teleporters): only the Seeker who travels goes. If their map
## empties, it's dropped (a hosted map is freed; the window's level becomes an
## empty placeholder). If the destination is already open, they join it;
## otherwise it opens fresh (as the window's level when that's free, else
## hosted).
##
## Joining: Start on a controller nobody plays with opens a character picker
## in a new pane; the guest appears on the leader's map.

const PLACEHOLDER := "res://scenes/empty.tscn"
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
	if scene and scene.scene_file_path == path and scene.has_method("spawn_member"):
		return scene
	return null


func _root_path() -> String:
	var scene := get_tree().current_scene
	return scene.scene_file_path if scene else ""


## Opens a map in its own world. Its level script spawns whoever is on it.
func host(path: String) -> Node:
	var viewport := SubViewport.new()
	viewport.name = "Host_" + path.get_file().get_basename()
	viewport.own_world_3d = true
	viewport.size = HOST_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.audio_listener_enable_3d = false
	add_child(viewport)
	var level := (load(path) as PackedScene).instantiate()
	hosts[path] = level
	viewport.add_child(level)
	return level


func _drop_host(path: String) -> void:
	var level: Node = hosts.get(path)
	hosts.erase(path)
	if level and is_instance_valid(level):
		var viewport := level.get_parent() as SubViewport
		# Panes still looking into that world look away first.
		for pane in split.panes:
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
	Party.leader_map = level.scene_file_path
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

## A Seeker takes a teleporter on their own. Alone (no party, no director),
## the window's level just changes.
static func travel(seeker: Player, destination: String) -> void:
	var tree := seeker.get_tree()
	var director := find(tree)
	if director == null:
		for node in Scope.group(seeker, "player"):
			(node as Player).save_game()
		tree.change_scene_to_file.call_deferred(destination)
		return
	director.move(seeker, destination)


func move(seeker: Player, destination: String) -> void:
	var who := Party.who_of(seeker)
	var from_level := Scope.level(seeker)
	var from_path := from_level.scene_file_path if from_level else ""
	if from_path == destination:
		return
	seeker.save_game()
	Party.set_map(who, destination)
	if from_level:
		from_level.call("remove_seeker", seeker)
	if hosts.has(from_path) and Party.members_on(from_path).is_empty():
		_drop_host(from_path)
	var root_path := _root_path()
	var root_free := root_path == PLACEHOLDER or (root_path != "" and Party.members_on(root_path).is_empty())
	var target := level_for(destination)
	if target:
		target.call("spawn_member", who)
		if root_free and root_path != PLACEHOLDER:
			get_tree().change_scene_to_file.call_deferred(PLACEHOLDER)
	elif root_free:
		get_tree().change_scene_to_file.call_deferred(destination)
	else:
		host(destination)


# --- Leaving and ending ----------------------------------------------------------------------

## A guest leaves (Options tab): saved, then their Seeker and pane go.
func leave(seeker: Player) -> void:
	var who := Party.who_of(seeker)
	if who == Party.LEADER:
		return
	var level := Scope.level(seeker)
	var path := level.scene_file_path if level else ""
	seeker.deposit_lumidium()
	seeker.save_game()
	var name_was := seeker.save.character.seeker_name
	if level:
		level.call("remove_seeker", seeker)
		level.call("banner", "%s left the party" % name_was)
	Party.leave(who)
	var pane := split.pane_for_who(who)
	if pane:
		split.remove_pane(pane)
	if hosts.has(path) and Party.members_on(path).is_empty():
		_drop_host(path)
		var root_path := _root_path()
		if root_path != PLACEHOLDER and Party.members_on(root_path).is_empty():
			get_tree().change_scene_to_file.call_deferred(PLACEHOLDER)
	maybe_end()


## Back to plain single player once the leader is alone on the window's own
## level (a leader alone on a hosted map keeps a one-pane split until they
## travel).
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


## Quit to title: every map and pane goes.
func shutdown() -> void:
	for path in hosts.keys():
		_drop_host(path)
	get_tree().root.disable_3d = false
	queue_free()
