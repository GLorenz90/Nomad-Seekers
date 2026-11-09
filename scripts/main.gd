extends Node3D
## Shared level script (test room, arena, Nomad-2). Wires each Seeker's camera,
## HUD, menu and target markers together, bakes the navmesh, and respawns a
## Seeker who falls out of the level or dies.
##
## The navmesh is baked at startup from the Level's collision (a child of the
## Navigation region), so blockout edits never leave it stale. The same navmesh
## will later drive the player's area map.
##
## Loot (Part 5): Main is the loot_spawner. Defeated enemies call
## on_enemy_defeated(); the Seekers get the EXP and a drop is rolled from an
## emblem's pool, spawned as an ItemPickup where the enemy fell.
##
## Local co-op (Part 12): the scene's Player is the party leader. Pressing Start
## on another controller opens a character picker in a new split-screen pane;
## the guest then plays beside the leader with their own camera, HUD and menu
## (see Party, SplitScreen, PlayerInput). Guests come along through teleporters.
## A Seeker who falls in co-op stays down until a partner's Revive, or presses
## A to go back to the start; when everyone is down, everyone goes back.

signal navmesh_ready

const KILL_HEIGHT := -20.0
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const RIG_SCENE := preload("res://scenes/camera/camera_rig.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
## How far apart guests appear beside the leader's spawn point.
const GUEST_SPACING := 1.6


## One Seeker and everything that's theirs.
class Kit:
	var player: Player
	var rig: CameraRig
	var hud: DebugHud
	var menu: LoadoutMenu
	var markers: TargetMarkers
	var pane: SeekerPane
	var spawn := Transform3D.IDENTITY


var _spawn := Transform3D.IDENTITY
var rng := RandomNumberGenerator.new()
## The leader's menu and markers (kept for tests and older code).
var loadout_menu: LoadoutMenu
var target_markers: TargetMarkers
## Every Seeker here, the leader first.
var kits: Array[Kit] = []
var split: SplitScreen
## Controllers picking a character: device -> SeekerPane.
var _joining := {}

@onready var player: Player = $Player
@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: DebugHud = $HUD
@onready var navigation: NavigationRegion3D = $Navigation


func _ready() -> void:
	add_to_group("loot_spawner")
	add_to_group("respawner")
	rng.randomize()
	_spawn = player.global_transform
	var leader := _wire(player, camera_rig, hud)
	leader.spawn = _spawn
	loadout_menu = leader.menu
	target_markers = leader.markers
	for room in get_tree().get_nodes_in_group("wave_rooms"):
		room.wave_started.connect(func(r: WaveRoom, index: int, total: int):
			banner("%s — Wave %d / %d" % [r.room_name, index + 1, total]))
		room.room_cleared.connect(func(r: WaveRoom):
			banner("%s clear" % r.room_name)
			_check_all_rooms_cleared())
	for pad in get_tree().get_nodes_in_group("teleporters"):
		pad.deposited.connect(func(seeker: Player, amount: int):
			var kit := kit_for(seeker)
			if kit:
				kit.hud.show_banner("Deposited %d Lumidium" % amount))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for guest in Party.guests.duplicate():
		_add_guest(guest)
	_bake_navmesh()


func _wire(seeker: Player, rig: CameraRig, seeker_hud: DebugHud) -> Kit:
	var kit := Kit.new()
	kit.player = seeker
	kit.rig = rig
	kit.hud = seeker_hud
	seeker.camera_rig = rig
	rig.setup(seeker)
	seeker_hud.setup(seeker, rig)
	kit.menu = LoadoutMenu.new()
	add_child(kit.menu)
	kit.menu.setup(seeker.combat)
	seeker.health.died.connect(_on_seeker_died.bind(seeker))
	kit.markers = TargetMarkers.new()
	add_child(kit.markers)
	kit.markers.setup(seeker.combat, rig)
	rig.show_lock_marker = false
	seeker.item_collected.connect(seeker_hud.show_pickup)
	seeker.exp_gained.connect(func(amount: int): seeker_hud.show_pickup("+%d EXP" % amount))
	seeker.leveled_up.connect(seeker_hud.show_level_up)
	kits.append(kit)
	return kit


func kit_for(seeker: Player) -> Kit:
	for kit in kits:
		if kit.player == seeker:
			return kit
	return null


## A banner on every Seeker's HUD.
func banner(text: String) -> void:
	for kit in kits:
		kit.hud.show_banner(text)


func _bake_navmesh() -> void:
	# CSG builds its collision a frame after entering the tree, so wait for it.
	# The navmesh parses static colliders (layer 1), which is fast at runtime.
	await get_tree().process_frame
	await get_tree().physics_frame
	navigation.bake_navigation_mesh(false)
	navmesh_ready.emit()


func _physics_process(_delta: float) -> void:
	for kit in kits.duplicate():
		if kit.player.global_position.y < KILL_HEIGHT:
			_respawn_player(kit)
		elif kit.player.downed and kit.player.input.just_pressed("jump"):
			_respawn_player(kit)  # A while down: back to the start


# --- Joining (Part 12) -------------------------------------------------------------------

## Start on a controller nobody plays with opens the character picker for it.
## Alone, the leader plays with any controller; the first one they use is
## theirs.
func _input(event: InputEvent) -> void:
	var pad_event := event is InputEventJoypadButton \
		or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5)
	if not pad_event:
		return
	var start := event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed \
		and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START
	if Party.leader_pad < 0:
		Party.leader_pad = event.device
		return
	if start and not Party.has_device(event.device) and not _joining.has(event.device):
		get_viewport().set_input_as_handled()
		start_join(event.device)


## Opens the character picker for a controller in a new pane.
func start_join(device: int) -> SeekerPane:
	if device < 0 or Party.size() + _joining.size() >= PlayerInput.MAX_PLAYERS:
		return null
	_ensure_split()
	var listen := PlayerInput.new()
	listen.slot = PlayerInput.MAX_PLAYERS  # never polled; owns() filters by device
	listen.device = device
	listen.keyboard = false
	var pane := split.add_pane(listen)
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
	var kit := _add_guest(guest, pane)
	banner("%s joined the party" % kit.player.save.character.seeker_name)


func _cancel_join(device: int, pane: SeekerPane) -> void:
	_joining.erase(device)
	split.remove_pane(pane)
	if kits.size() == 1 and _joining.is_empty():
		_end_split()


## Spawns a guest's Seeker beside the leader's spawn point.
func _add_guest(guest: Dictionary, pane: SeekerPane = null) -> Kit:
	_ensure_split()
	var seeker := PLAYER_SCENE.instantiate() as Player
	seeker.guest_device = int(guest.device)
	seeker.name = "Seeker%d" % (int(guest.input) + 1)
	seeker.input = PlayerInput.bind(int(guest.input), int(guest.device), false)
	add_child(seeker)
	var at := _spawn
	at.origin += _spawn.basis.x * GUEST_SPACING * int(guest.input)
	seeker.global_transform = at
	seeker.reset_physics_interpolation()
	var rig := RIG_SCENE.instantiate() as CameraRig
	rig.name = "CameraRig%d" % (int(guest.input) + 1)
	add_child(rig)
	var seeker_hud := HUD_SCENE.instantiate() as DebugHud
	seeker_hud.name = "HUD%d" % (int(guest.input) + 1)
	add_child(seeker_hud)
	var kit := _wire(seeker, rig, seeker_hud)
	kit.spawn = at
	if pane == null:
		pane = split.add_pane(seeker.input)
	else:
		pane.input = seeker.input
	_move_into(kit, pane)
	return kit


## A guest leaves (Options tab): saved, then their Seeker and pane go.
func leave_party(seeker: Player) -> void:
	var kit := kit_for(seeker)
	if kit == null or seeker.guest_device < 0:
		return
	seeker.deposit_lumidium()
	seeker.save_game()
	Party.leave(seeker.guest_device)
	kits.erase(kit)
	if kit.pane:
		split.remove_pane(kit.pane)
	for node: Node in [kit.menu, kit.markers, kit.hud, kit.rig, seeker]:
		if is_instance_valid(node):
			node.queue_free()
	banner("%s left the party" % seeker.save.character.seeker_name)
	if kits.size() == 1 and _joining.is_empty():
		_end_split()


# --- Split screen ----------------------------------------------------------------------

func _ensure_split() -> void:
	if split:
		return
	split = SplitScreen.new()
	split.name = "SplitScreen"
	add_child(split)
	var leader := kits[0]
	if Party.leader_pad < 0:
		Party.leader_pad = 0
	leader.player.input = PlayerInput.bind(0, Party.leader_pad, true)
	_move_into(leader, split.add_pane(leader.player.input))
	# Only the panes draw the world now.
	get_viewport().disable_3d = true


func _end_split() -> void:
	if split == null:
		return
	var leader := kits[0]
	leader.player.input = PlayerInput.shared()
	leader.player.ui_parent = null
	leader.pane = null
	for node: Node in [leader.hud, leader.menu]:
		node.reparent(self)
	_reparent_modals(leader.player, self)
	leader.markers.render_layers = 1
	split.queue_free()
	split = null
	get_viewport().disable_3d = false


func _move_into(kit: Kit, pane: SeekerPane) -> void:
	kit.pane = pane
	pane.attach(kit.player, kit.rig)
	kit.player.ui_parent = pane.sub
	for node: Node in [kit.hud, kit.menu]:
		node.reparent(pane.sub)
	_reparent_modals(kit.player, pane.sub)
	kit.markers.render_layers = SeekerPane.marker_layer(kit.player.input.slot)


## Counters and teleporter lists already open follow their Seeker's view.
func _reparent_modals(seeker: Player, to: Node) -> void:
	for menu in get_tree().get_nodes_in_group("modal_menus"):
		if menu.get("player") == seeker:
			(menu as Node).reparent(to)


# --- Loot and EXP -------------------------------------------------------------------------

## Called by every Enemy as it dies (group "loot_spawner"). Every Seeker still
## standing gets the EXP (Claude's pick for co-op); the drop rolls from the
## emblem of the Seeker nearest the enemy.
func on_enemy_defeated(enemy: Enemy) -> void:
	var enemy_id := enemy.data.resource_path.get_file().get_basename()
	for kit in kits:
		if kit.player.downed or kit.player.health.is_dead():
			continue
		kit.player.gain_exp(enemy.data.exp_value())
		if QuestBook.record(kit.player.save, "defeat", enemy_id):
			kit.hud.show_banner("Quest complete: report to the Guild")
	var nearest := Player.nearest(self, enemy.global_position, true)
	var save := nearest.save if nearest else null
	var emblem := save.character.emblem_index() if save else 0
	var traps := save != null and save.character.can_use_traps()
	var drop := Loot.roll_drop(enemy.data, emblem, rng, traps)
	if not drop.is_empty():
		spawn_drop(drop, enemy.global_position)


## Guild quests (Part 10): every wave room cleared in one trip.
func _check_all_rooms_cleared() -> void:
	for room in get_tree().get_nodes_in_group("wave_rooms"):
		if (room as WaveRoom).state != WaveRoom.RoomState.CLEARED:
			return
	for kit in kits:
		if QuestBook.record(kit.player.save, "clear", scene_file_path):
			kit.hud.show_banner("Quest complete: report to the Guild")


func quest_done() -> void:
	banner("Quest complete: report to the Guild")


func spawn_drop(drop: Dictionary, at: Vector3) -> ItemPickup:
	var pickup := ItemPickup.create(drop)
	add_child(pickup)
	pickup.global_position = at
	return pickup


# --- Falling and respawning ----------------------------------------------------------------

## Menu tool (Debug tab): back to the start, keeping carried Lumidium.
func respawn_player(seeker: Player = null) -> void:
	var kit := kit_for(seeker) if seeker else kits[0]
	if kit:
		_reset_player(kit)


## Alone, a fallen Seeker goes straight back to the start. In co-op they stay
## down for a partner's Revive, unless nobody is left standing.
func _on_seeker_died(seeker: Player) -> void:
	var kit := kit_for(seeker)
	if kit == null:
		return
	if kits.size() > 1:
		var standing := kits.filter(func(k: Kit): return not k.player.downed and not k.player.health.is_dead())
		if not standing.is_empty():
			seeker.set_downed(true)
			kit.hud.show_banner("Down! A partner's Revive brings you back. A: return to the start")
			return
		for other in kits.duplicate():
			if other != kit:
				_respawn_player(other)
	_respawn_player(kit)


func _respawn_player(kit: Kit) -> void:
	var lost := kit.player.lose_carried()
	if lost > 0:
		kit.hud.show_banner("Lost %d carried Lumidium" % lost)
	_reset_player(kit)


func _reset_player(kit: Kit) -> void:
	var seeker := kit.player
	if seeker.downed:
		seeker.set_downed(false)
	seeker.global_transform = kit.spawn
	seeker.velocity = Vector3.ZERO
	seeker.reset_physics_interpolation()
	seeker.health.restore_full()
	seeker.status.clear_all()
