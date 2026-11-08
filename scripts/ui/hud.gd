class_name DebugHud
extends CanvasLayer
## Prototype HUD: HP/LP/Sync bars, combo pips, equipped hands, combo feedback,
## wallet and pickups, plus an optional debug readout (off by default; F3 /
## Select or the menu's Levels tab toggles it). The control reference lives in
## the menu's Controls tab (HELP).

const HELP := """Controls (gamepad / keyboard+mouse)
Move: Left stick / WASD    Camera: Right stick / mouse
Jump: A / Space    Dash: B / Shift (cancels an attack after it hits)
Lock on: R3 / Q / middle mouse    Switch target: flick right stick
Attack: X / left click, Y / right click (tap = Normal, hold = Hard)
Chain: press again inside the timing window (too early breaks the combo)
Second spell: hold RT / E while casting    Loadouts: LB/RB / Z,C
Same-type pair (e.g. Sword + Frost Sword): every attack uses both hands
Block: LT / F    Special: hold RT / E + hand    Loadout menu: Start / Tab
Items: D-pad left/up/right / 1,2,3 (HP Gel, LP Cell, Cure Salt)
Lumidium: hit a crystal 3 times; stand on a teleporter to deposit it
Sync Burst (gauge full): L3 / R    Feed and pair SyncAIDa: menu, SyncAIDa tab
Menu: Start / Tab. In menus: d-pad or stick to move, A to accept, B to go back, LB / RB to switch tabs.
Click to capture the mouse, Esc to release. Debug readout: Select / F3."""

var player: Player
var camera_rig: CameraRig

var _hp_bar: ProgressBar
var _lp_bar: ProgressBar
var _sync_bar: ProgressBar
var _sync_label: Label
var _pips: Label
var _hands: Label
var _lt: Label
var _status: Label
var _banner: Label
var _banner_tween: Tween
var _feedback: Label
var _feedback_tween: Tween
var _wallet: Label
var _feed: VBoxContainer

@onready var _panel: Control = $Panel
@onready var _debug: Label = $Panel/Debug
@onready var _help: Label = $Panel/Help


func _ready() -> void:
	add_to_group("hud")
	_help.text = ""
	_help.visible = false
	_panel.visible = false
	_build_status()


func set_debug_visible(on: bool) -> void:
	_panel.visible = on


func is_debug_visible() -> bool:
	return _panel.visible


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
	var companion := player.syncaida
	if companion and companion.data:
		var d := companion.data
		_sync_bar.value = d.gauge
		var fill := _sync_bar.get_theme_stylebox("fill") as StyleBoxFlat
		fill.bg_color = Color(1.0, 0.9, 0.4) if companion.is_ready() else d.color()
		_sync_label.text = "%s  %s  Lv %d   Burst: %s%s%s" % [d.display_name, d.form, d.level(), d.burst_name(),
			"  READY (L3)" if companion.is_ready() else "",
			"   Aegis %.0fs" % combat.aegis_time_left() if combat.aegis_active() else ""]
	elif companion:
		_sync_bar.value = 0.0
		_sync_label.text = "No SyncAIDa yet: choose your starter (Start / Tab > SyncAIDa)"
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
	if player.save:
		var c := player.save.character
		var inv := player.save.inventory
		_wallet.text = "%s  %s  (%s emblem)\nEXP %d\nOro %d\nLumidium carried %d   banked %d\nHP Gel %d   LP Cell %d   Cure Salt %d" % [
			c.seeker_name, c.job_name(), c.emblem_name(), c.experience, inv.oro,
			player.carried_lumidium_total(), inv.lumidium_total(),
			inv.count(&"hp_gel"), inv.count(&"lp_cell"), inv.count(&"cure_salt")]
		_wallet.modulate = c.emblem_color().lightened(0.5)
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
		var slot := player.combat.spell_slot(w, hand, Input.is_action_pressed("shift"))
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


## Small stacked pickup messages (loot, EXP, Lumidium), bottom right.
func show_pickup(text: String) -> void:
	var label := _label(_feed, 18)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.modulate = Color(1.0, 0.95, 0.7)
	while _feed.get_child_count() > 6:
		_feed.get_child(0).free()
	var tween := label.create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


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
	box.offset_top = -250.0
	box.offset_right = 420.0
	box.offset_bottom = -20.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_hp_bar = _bar(box, "HP", Color(0.35, 0.85, 0.4))
	_lp_bar = _bar(box, "LP", Color(0.3, 0.6, 1.0))
	_sync_bar = _bar(box, "SY", Color(0.8, 0.9, 1.0))
	_sync_bar.max_value = SyncAIDaCompanion.GAUGE_MAX
	_sync_bar.custom_minimum_size.y = 10.0
	_sync_label = _label(box, 15)
	_sync_label.modulate = Color(0.85, 0.95, 1.0)
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

	_wallet = _label(self, 17)
	_wallet.anchor_left = 1.0
	_wallet.anchor_right = 1.0
	_wallet.offset_left = -440.0
	_wallet.offset_right = -24.0
	_wallet.offset_top = 20.0
	_wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_feed = VBoxContainer.new()
	_feed.anchor_left = 1.0
	_feed.anchor_right = 1.0
	_feed.anchor_top = 1.0
	_feed.anchor_bottom = 1.0
	_feed.offset_left = -460.0
	_feed.offset_right = -24.0
	_feed.offset_top = -260.0
	_feed.offset_bottom = -24.0
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)

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
