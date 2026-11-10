class_name SeekerPane
extends SubViewportContainer
## One Seeker's part of the split screen (Part 12). See SplitScreen.

## Visual layers 11-14 hold each Seeker's own target markers, so a partner's
## rings don't show in your pane.
const MARKER_LAYER_BASE := 10
## Extra vertical FOV for a tall, narrow pane (half of a widescreen), so the
## view doesn't feel cramped (Claude's pick; Grayson: "increased a little").
const NARROW_FOV_BONUS := 10.0

var input: PlayerInput
## Whose pane: Party.LEADER or a guest's controller.
var who := -1
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
	# Look into the Seeker's own map (party members can be on different ones).
	sub.world_3d = seeker.get_world_3d()
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
		var aspect := size.x / maxf(size.y, 1.0)
		camera.fov = rig.camera.fov + (NARROW_FOV_BONUS if aspect < 1.3 else 0.0)
		rig.view_fov = camera.fov
		rig.view_aspect = aspect
		camera.near = rig.camera.near
		camera.far = rig.camera.far
