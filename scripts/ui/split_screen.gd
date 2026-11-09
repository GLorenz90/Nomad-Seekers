class_name SplitScreen
extends CanvasLayer
## Couch co-op split-screen (Part 12): one pane per Seeker, all looking into the
## same world. Two Seekers split the screen top and bottom; three or four use
## quarters (PSO GameCube style).
##
## Each pane (SeekerPane) is a SubViewport sharing the level's World3D, with a
## camera that copies its Seeker's CameraRig camera every frame. The Seeker's
## HUD, menu and counters live inside its pane, so each has its own focus and
## only hears its own controller (the pane filters input events by device).
## While panes are up the window's own 3D view is switched off.

## Menus are laid out for at least this height and scaled down into a pane,
## so a half-height pane still fits the whole menu (text gets smaller).
const MIN_UI_HEIGHT := 720.0

var panes: Array[SeekerPane] = []

var _root: Control


func _init() -> void:
	layer = -1  # under every HUD and menu layer (they live in the panes anyway)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	get_viewport().size_changed.connect(_layout)


func add_pane(input: PlayerInput) -> SeekerPane:
	var pane := SeekerPane.new()
	pane.input = input
	_root.add_child(pane)
	pane.sub.world_3d = get_viewport().world_3d
	panes.append(pane)
	_layout()
	return pane


func remove_pane(pane: SeekerPane) -> void:
	panes.erase(pane)
	pane.queue_free()
	_layout()


func pane_for(seeker: Player) -> SeekerPane:
	for pane in panes:
		if pane.player == seeker:
			return pane
	return null


## Top / bottom for two; quarters for three or four.
func _layout() -> void:
	if _root == null:
		return
	var size := get_viewport().get_visible_rect().size
	var count := panes.size()
	for i in count:
		var rect := Rect2(Vector2.ZERO, size)
		if count == 2:
			rect = Rect2(Vector2(0.0, size.y * 0.5 * i), Vector2(size.x, size.y * 0.5))
		elif count > 2:
			rect = Rect2(Vector2(size.x * 0.5 * (i % 2), size.y * 0.5 * floori(i / 2.0)), size * 0.5)
		var pane := panes[i]
		pane.position = rect.position
		pane.size = rect.size
		var scale := maxf(1.0, MIN_UI_HEIGHT / maxf(rect.size.y, 1.0))
		pane.sub.size_2d_override = Vector2i(rect.size * scale)
		pane.sub.size_2d_override_stretch = true
