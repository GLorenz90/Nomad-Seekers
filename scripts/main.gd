extends Node3D
## Test room. Wires the Seeker, camera and HUD together, bakes the navmesh, and
## respawns the Seeker if it ever falls out of the level.
##
## The navmesh is baked at startup from the Level's collision (a child of the
## Navigation region), so blockout edits never leave it stale. The same navmesh
## will later drive the player's area map.

signal navmesh_ready

const KILL_HEIGHT := -20.0

var _spawn := Transform3D.IDENTITY

@onready var player: Player = $Player
@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: DebugHud = $HUD
@onready var navigation: NavigationRegion3D = $Navigation


func _ready() -> void:
	_spawn = player.global_transform
	player.camera_rig = camera_rig
	camera_rig.setup(player)
	hud.setup(player, camera_rig)
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
		player.global_transform = _spawn
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
