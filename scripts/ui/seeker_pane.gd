class_name SeekerPane
extends SubViewportContainer
## One Seeker's part of the split screen (Part 12). See SplitScreen.

## Visual layers 11-14 hold each Seeker's own target markers, so a partner's
## rings don't show in your pane.
const MARKER_LAYER_BASE := 10

var input: PlayerInput
var player: Player
var rig: CameraRig
var sub: SubViewport
var camera: Camera3D


func _init() -> void:
	stretch = true  # the SubViewport follows the pane's size
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000  # after the camera rigs have moved
	mouse_filter = Control.MOUSE_FILTER_PASS
	sub = SubViewport.new()
	sub.handle_input_locally = true
	sub.audio_listener_enable_3d = false
	add_child(sub)
	camera = Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.current = true
	sub.add_child(camera)


func attach(seeker: Player, camera_rig: CameraRig) -> void:
	player = seeker
	rig = camera_rig
	var slot := maxi(seeker.input.slot, 0)
	# See every marker layer except the other Seekers'.
	var mask := 0xFFFFF
	for i in PlayerInput.MAX_PLAYERS:
		if i != slot:
			mask &= ~(1 << (MARKER_LAYER_BASE + i))
	camera.cull_mask = mask
	sub.audio_listener_enable_3d = slot == 0


static func marker_layer(slot: int) -> int:
	return 1 << (MARKER_LAYER_BASE + maxi(slot, 0))


## Only this Seeker's controller (and the leader's keyboard and mouse) reach
## the pane's HUD and menus.
func _propagate_input_event(event: InputEvent) -> bool:
	return input != null and input.owns(event)


func _process(_delta: float) -> void:
	if rig and is_instance_valid(rig) and rig.camera:
		camera.global_transform = rig.camera.global_transform
		camera.fov = rig.camera.fov
		camera.near = rig.camera.near
		camera.far = rig.camera.far
