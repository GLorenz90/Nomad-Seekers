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
## Local co-op (Part 12): pressing Start on another controller opens a
## character picker in a new split-screen pane; the guest then plays beside the
## leader with their own camera, HUD and menu (see CoopDirector, Party,
## SplitScreen, PlayerInput). Party members travel on their own: this level
## holds only the Seekers on this map (the scene's own Player takes the first
## of them), and a level can run hosted in its own world beside the window's.
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
	var spawn := Transform3D.IDENTITY


var _spawn := Transform3D.IDENTITY
var rng := RandomNumberGenerator.new()
## The leader's menu and markers (kept for tests and older code).
var loadout_menu: LoadoutMenu
var target_markers: TargetMarkers
## Every Seeker here, the leader first.
var kits: Array[Kit] = []

@onready var player: Player = $Player
@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: DebugHud = $HUD
@onready var navigation: NavigationRegion3D = $Navigation


func _ready() -> void:
	add_to_group("loot_spawner")
	add_to_group("respawner")
	rng.randomize()
	_spawn = player.global_transform
	for room in Scope.group(self, "wave_rooms"):
		room.wave_started.connect(func(r: WaveRoom, index: int, total: int):
			banner("%s — Wave %d / %d" % [r.room_name, index + 1, total]))
		room.room_cleared.connect(func(r: WaveRoom):
			banner("%s clear" % r.room_name)
			_check_all_rooms_cleared())
	for pad in Scope.group(self, "teleporters"):
		pad.deposited.connect(func(seeker: Player, amount: int):
			var kit := kit_for(seeker)
			if kit:
				kit.hud.show_banner("Deposited %d Lumidium" % amount))
	if get_viewport() == get_tree().root:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var director := CoopDirector.find(get_tree())
	if director == null:
		var leader := _wire(player, camera_rig, hud)
		leader.spawn = _spawn
		loadout_menu = leader.menu
		target_markers = leader.markers
	else:
		_join_director(director)
	_bake_navmesh()


## A level opened while the party is up (the window's or a hosted map):
## spawns whoever is on this map, the scene's own Seeker taking the first.
func _join_director(director: CoopDirector) -> void:
	var members := Party.members_on(scene_file_path)
	if members.is_empty():
		members.append(Party.LEADER)
	var first := members[0]
	if first != Party.LEADER:
		player.guest_device = first
		player.use_save(Party.guest_for(first).save as SaveData)
	player.input = CoopDirector.input_for(first)
	var kit := _wire(player, camera_rig, hud)
	kit.spawn = _spawn_point(first)
	player.global_transform = kit.spawn
	loadout_menu = kit.menu
	target_markers = kit.markers
	director.attach(player, camera_rig, hud, kit.menu, kit.markers)
	for i in range(1, members.size()):
		spawn_member(members[i])
	director.maybe_end.call_deferred()


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


## A banner on every Seeker's HUD on this map.
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


# --- The party (Part 12) ------------------------------------------------------------------

## Start on another controller joins (see CoopDirector). Once the director
## exists it listens itself.
func _input(event: InputEvent) -> void:
	if get_viewport() == get_tree().root and CoopDirector.find(get_tree()) == null:
		CoopDirector.watch_for_join(self, event)


## The first guest joined: the leader moves into the split screen.
func adopt_director(director: CoopDirector) -> void:
	var leader := kits[0]
	leader.player.input = CoopDirector.input_for(Party.LEADER)
	director.attach(leader.player, leader.rig, leader.hud, leader.menu, leader.markers)


## The party is over and the leader is alone here: back to a plain level.
func release_director() -> void:
	if kits.is_empty():
		return
	var leader := kits[0]
	leader.player.input = PlayerInput.shared()
	leader.player.ui_parent = null
	for node: Node in [leader.hud, leader.menu]:
		node.reparent(self)
	for menu in get_tree().get_nodes_in_group("modal_menus"):
		if menu.get("player") == leader.player:
			(menu as Node).reparent(self)
	leader.markers.render_layers = 1
	Party.leader_map = ""


## Where a party member appears: guests beside the leader's spot.
func _spawn_point(who: int) -> Transform3D:
	var at := _spawn
	var slot := 0 if who == Party.LEADER else Party.slot_of(who)
	at.origin += _spawn.basis.x * GUEST_SPACING * slot
	return at


## Brings a party member onto this map (joining, or arriving by teleporter).
func spawn_member(who: int) -> Kit:
	var seeker := PLAYER_SCENE.instantiate() as Player
	if who != Party.LEADER:
		seeker.guest_device = who
	seeker.input = CoopDirector.input_for(who)
	seeker.name = "Seeker%d" % (seeker.input.slot + 1)
	add_child(seeker)
	var at := _spawn_point(who)
	seeker.global_transform = at
	seeker.reset_physics_interpolation()
	var rig := RIG_SCENE.instantiate() as CameraRig
	rig.name = "CameraRig%d" % (seeker.input.slot + 1)
	add_child(rig)
	var seeker_hud := HUD_SCENE.instantiate() as DebugHud
	seeker_hud.name = "HUD%d" % (seeker.input.slot + 1)
	add_child(seeker_hud)
	var kit := _wire(seeker, rig, seeker_hud)
	kit.spawn = at
	var director := CoopDirector.find(get_tree())
	if director:
		director.attach(seeker, rig, seeker_hud, kit.menu, kit.markers)
	return kit


## A Seeker leaves this map (teleporter, or leaving the party): their Seeker,
## camera, HUD, menu and any counter they had open go. Their pane stays.
func remove_seeker(seeker: Player) -> void:
	var kit := kit_for(seeker)
	if kit == null:
		return
	kits.erase(kit)
	for menu in get_tree().get_nodes_in_group("modal_menus"):
		if menu.get("player") == seeker:
			(menu as Node).queue_free()
	for node: Node in [kit.menu, kit.markers, kit.hud, kit.rig, seeker]:
		if is_instance_valid(node):
			node.queue_free()


## A guest leaves the party (Options tab).
func leave_party(seeker: Player) -> void:
	var director := CoopDirector.find(get_tree())
	if director:
		director.leave(seeker)


# --- Loot and EXP -------------------------------------------------------------------------

## Called by every Enemy as it dies. Every party member on this map gets the
## full EXP, whoever landed the kill and whether or not they hit it, even if
## they're down (Grayson, 2026-11-09: unhindered, unlike PSO). Members on other
## maps get none. The drop rolls from the emblem of the Seeker nearest the enemy.
func on_enemy_defeated(enemy: Enemy) -> void:
	var enemy_id := enemy.data.resource_path.get_file().get_basename()
	for kit in kits:
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
	for room in Scope.group(self, "wave_rooms"):
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
