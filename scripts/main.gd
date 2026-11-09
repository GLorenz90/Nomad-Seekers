extends Node3D
## Shared level script (test room and arena). Wires the Seeker, camera, HUD,
## loadout menu, target markers and any wave rooms together, bakes the navmesh,
## and respawns the Seeker if they fall out of the level or die.
##
## The navmesh is baked at startup from the Level's collision (a child of the
## Navigation region), so blockout edits never leave it stale. The same navmesh
## will later drive the player's area map.
##
## Loot (Part 5): Main is the loot_spawner. Defeated enemies call
## on_enemy_defeated(); the Seeker gets the EXP and a drop roll from their
## emblem's pool, spawned as an ItemPickup where the enemy fell.

signal navmesh_ready

const KILL_HEIGHT := -20.0

var _spawn := Transform3D.IDENTITY
var rng := RandomNumberGenerator.new()
var loadout_menu: LoadoutMenu
var target_markers: TargetMarkers

@onready var player: Player = $Player
@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: DebugHud = $HUD
@onready var navigation: NavigationRegion3D = $Navigation


func _ready() -> void:
	add_to_group("loot_spawner")
	add_to_group("respawner")
	rng.randomize()
	_spawn = player.global_transform
	player.camera_rig = camera_rig
	camera_rig.setup(player)
	hud.setup(player, camera_rig)
	loadout_menu = LoadoutMenu.new()
	add_child(loadout_menu)
	loadout_menu.setup(player.combat)
	player.health.died.connect(_respawn_player)
	target_markers = TargetMarkers.new()
	add_child(target_markers)
	target_markers.setup(player.combat, camera_rig)
	camera_rig.show_lock_marker = false
	for room in get_tree().get_nodes_in_group("wave_rooms"):
		room.wave_started.connect(func(r: WaveRoom, index: int, total: int):
			hud.show_banner("%s — Wave %d / %d" % [r.room_name, index + 1, total]))
		room.room_cleared.connect(func(r: WaveRoom):
			hud.show_banner("%s clear" % r.room_name)
			_check_all_rooms_cleared())
	for pad in get_tree().get_nodes_in_group("teleporters"):
		pad.deposited.connect(func(_s: Player, amount: int):
			hud.show_banner("Deposited %d Lumidium" % amount))
	player.item_collected.connect(hud.show_pickup)
	player.exp_gained.connect(func(amount: int): hud.show_pickup("+%d EXP" % amount))
	player.leveled_up.connect(hud.show_level_up)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_bake_navmesh()


func _bake_navmesh() -> void:
	# CSG builds its collision a frame after entering the tree, so wait for it.
	# The navmesh parses static colliders (layer 1), which is fast at runtime.
	await get_tree().process_frame
	await get_tree().physics_frame
	navigation.bake_navigation_mesh(false)
	navmesh_ready.emit()


func _physics_process(_delta: float) -> void:
	if player.global_position.y < KILL_HEIGHT:
		_respawn_player()


## Called by every Enemy as it dies (group "loot_spawner").
func on_enemy_defeated(enemy: Enemy) -> void:
	player.gain_exp(enemy.data.exp_value())
	if QuestBook.record(player.save, "defeat", enemy.data.resource_path.get_file().get_basename()):
		quest_done()
	var emblem := player.save.character.emblem_index() if player.save else 0
	var traps := player.save != null and player.save.character.can_use_traps()
	var drop := Loot.roll_drop(enemy.data, emblem, rng, traps)
	if not drop.is_empty():
		spawn_drop(drop, enemy.global_position)


## Guild quests (Part 10): every wave room cleared in one trip.
func _check_all_rooms_cleared() -> void:
	for room in get_tree().get_nodes_in_group("wave_rooms"):
		if (room as WaveRoom).state != WaveRoom.RoomState.CLEARED:
			return
	if QuestBook.record(player.save, "clear", scene_file_path):
		quest_done()


func quest_done() -> void:
	hud.show_banner("Quest complete: report to the Guild")


func spawn_drop(drop: Dictionary, at: Vector3) -> ItemPickup:
	var pickup := ItemPickup.create(drop)
	add_child(pickup)
	pickup.global_position = at
	return pickup


## Menu tool (Levels tab): back to the start, keeping carried Lumidium.
func respawn_player() -> void:
	_reset_player()


func _respawn_player() -> void:
	var lost := player.lose_carried()
	if lost > 0:
		hud.show_banner("Lost %d carried Lumidium" % lost)
	_reset_player()


func _reset_player() -> void:
	player.global_transform = _spawn
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	player.health.restore_full()
	player.status.clear_all()
