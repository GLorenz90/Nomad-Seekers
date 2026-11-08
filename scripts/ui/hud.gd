class_name DebugHud
extends CanvasLayer
## Prototype HUD: HP/LP bars, combo pips, equipped hands, combo feedback, plus a
## debug readout and control help. F3 / Select toggles the debug panel.

const HELP := """Controls (gamepad / keyboard+mouse)
Move: Left stick / WASD    Camera: Right stick / mouse
Jump: A / Space    Dash: B / Shift (cancels an attack after it hits)
Lock on: R3 / Q / middle mouse    Switch target: flick right stick
Attack: X / left click, Y / right click (tap = Normal, hold = Hard)
Chain: press again inside the timing window (too early breaks the combo)
Second spell: hold RT / E while casting    Loadouts: LB/RB / Z,C
Same-type pair (e.g. Sword + Frost Sword): every attack uses both hands
Block: LT / F    Special: hold RT / E + hand    Loadout menu: Start / Tab
Click to capture the mouse, Esc to release. F3 hides this panel."""

var player: Player
var camera_rig: CameraRig

var _hp_bar: ProgressBar
var _lp_bar: ProgressBar
var _pips: Label
var _hands: Label
var _lt: Label
var _status: Label
var _banner: Label
var _banner_tween: Tween
var _feedback: Label
var _feedback_tween: Tween

@onready var _panel: Control = $Panel
@onready var _debug: Label = $Panel/Debug
@onready var _help: Label = $Panel/Help


func _ready() -> void:
	_help.text = HELP
	_build_status()


func setup(seeker: Player, rig: CameraRig) -> void:
	player = seeker
	camera_rig = rig
	player.combat.combo_feedback.connect(_show_feedback)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_panel.visible = not _panel.visible


func _process(_delta: float) -> void:
	if player == null:
		return
	var combat := player.combat
	_hp_bar.max_value = player.health.max_hp
	_hp_bar.value = player.health.hp
	_lp_bar.max_value = combat.stats.max_lp
	_lp_bar.value = combat.lp
	var pips := ""
	for i in CombatController.MAX_CHAIN:
		pips += ("● " if i < combat.chain_step else "○ ")
	_pips.text = "Chain  " + pips
	var x_hand := CombatController.Hand.LEFT if combat.x_is_left else CombatController.Hand.RIGHT
	var y_hand := CombatController.Hand.RIGHT if combat.x_is_left else CombatController.Hand.LEFT
	var two_hand := combat.get_loadout().two_handed_weapon()
	if two_hand:
		_hands.text = "%d  X / Y: %s (both hands)" % [combat.loadout_index + 1, two_hand.display_name]
	else:
		_hands.text = "%d  X: %s    Y: %s" % [combat.loadout_index + 1, _weapon_label(x_hand), _weapon_label(y_hand)]
	_lt.text = combat.get_lt_text()
	_status.text = player.status.describe()
	_lt.modulate = Color(0.6, 0.85, 1.0) if combat.is_blocking() else Color.WHITE
	if _panel.visible:
		_debug.text = "%s\n%s\n%s\nFPS: %d" % [
			player.get_debug_text(), camera_rig.get_debug_text(),
			combat.get_debug_text(), Engine.get_frames_per_second()]


func _weapon_label(hand: int) -> String:
	var w := player.combat.current_weapon(hand)
	if w == null:
		return "-"
	if w.casting:
		var slot := 1 if Input.is_action_pressed("shift") else 0
		return "%s (%s)" % [w.display_name, w.get_spell_name(slot)]
	return w.display_name


## Big centered text for room events ("Wave 2 / 3", "Room clear").
func show_banner(text: String) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(1.4)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.6)


func _show_feedback(text: String) -> void:
	_feedback.text = text
	_feedback.modulate.a = 1.0
	if _feedback_tween:
		_feedback_tween.kill()
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(0.5)
	_feedback_tween.tween_property(_feedback, "modulate:a", 0.0, 0.4)


func _build_status() -> void:
	var box := VBoxContainer.new()
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 24.0
	box.offset_top = -200.0
	box.offset_right = 420.0
	box.offset_bottom = -20.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_hp_bar = _bar(box, "HP", Color(0.35, 0.85, 0.4))
	_lp_bar = _bar(box, "LP", Color(0.3, 0.6, 1.0))
	_pips = _label(box, 20)
	_hands = _label(box, 18)
	_lt = _label(box, 16)
	_status = _label(box, 16)
	_status.modulate = Color(1.0, 0.75, 0.5)

	_feedback = _label(self, 34)
	_feedback.anchor_left = 0.5
	_feedback.anchor_right = 0.5
	_feedback.anchor_top = 0.62
	_feedback.anchor_bottom = 0.62
	_feedback.offset_left = -200.0
	_feedback.offset_right = 200.0
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.modulate.a = 0.0

	_banner = _label(self, 44)
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.anchor_top = 0.18
	_banner.anchor_bottom = 0.18
	_banner.offset_left = -400.0
	_banner.offset_right = 400.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0


func _bar(parent: Node, caption: String, color: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(row, 18)
	label.text = caption
	label.custom_minimum_size.x = 36.0
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(300.0, 18.0)
	bar.show_percentage = false
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	row.add_child(bar)
	return bar


func _label(parent: Node, size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
