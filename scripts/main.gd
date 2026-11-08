extends Node3D
## Test room for Part 1. Wires the Seeker, camera and HUD together, and respawns
## the Seeker if it ever falls out of the level.

const KILL_HEIGHT := -20.0

var _spawn := Transform3D.IDENTITY

@onready var player: Player = $Player
@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: DebugHud = $HUD


func _ready() -> void:
	_spawn = player.global_transform
	player.camera_rig = camera_rig
	camera_rig.setup(player)
	hud.player = player
	hud.camera_rig = camera_rig
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(_delta: float) -> void:
	if player.global_position.y < KILL_HEIGHT:
		player.global_transform = _spawn
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
