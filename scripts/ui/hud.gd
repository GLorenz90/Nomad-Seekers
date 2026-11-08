class_name DebugHud
extends CanvasLayer
## Debug readout and control help for the movement prototype. F3 / Select toggles it.

const HELP := """Controls (gamepad / keyboard+mouse)
Move: Left stick / WASD
Camera: Right stick / mouse or arrow keys
Jump: A / Space  (hold for full height, tap for a hop)
Dash: B / Shift  (works once in the air; jump during a ground dash to dash-jump)
Lock on: R3 / Q / middle mouse  (with nothing in range, recenters the camera)
Switch target: flick right stick / sweep mouse while locked
Click to capture the mouse, Esc to release. F3 hides this panel."""

var player: Player
var camera_rig: CameraRig

@onready var _panel: Control = $Panel
@onready var _debug: Label = $Panel/Debug
@onready var _help: Label = $Panel/Help


func _ready() -> void:
	_help.text = HELP


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_panel.visible = not _panel.visible


func _process(_delta: float) -> void:
	if player == null or not _panel.visible:
		return
	_debug.text = "%s\n%s\nFPS: %d" % [
		player.get_debug_text(), camera_rig.get_debug_text(), Engine.get_frames_per_second()]
