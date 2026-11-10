class_name CounterMenu
extends CanvasLayer
## Base for Nomad-2's counters (Part 10): the shops, the bank and the Guild.
## Like the menu, doesn't pause the game (PSO; Part 12 for co-op): the
## Seeker just stops taking game input while it's open.
##
## Layout, PSO-style: the clerk's commands on the left (Buy / Sell / Leave and
## so on), the list for the chosen command in the middle, and on the right the
## focused entry's details, then the offer: how many (for stacks) and the
## button that does it ("Buy for 300 Oro").
##
## Gamepad: d-pad moves, A picks (command -> entry -> confirm), B steps back
## (offer -> list -> commands -> leave), Start leaves.
##
## Subclasses fill in commands() and items_for(command). Each item is:
##   {"text": String, "color": Color, "detail": String,
##    "max": int (how many at most; above 1 shows an amount picker),
##    "start": int, "big_steps": bool,
##    "confirm": Callable(count) -> String (the confirm button's text),
##    "act": Callable(count) -> String (does it; returns the message),
##    "error": String (non-empty: greyed, and A explains instead)}

signal closed

var player: Player
var title := "Counter"
var greeting := ""

var _root: Control
var _header: Label
var _greeting: Label
var _commands: VBoxContainer
var _list_title: Label
var _list: VBoxContainer
var _detail: Label
var _offer: VBoxContainer
var _message: Label
var _command := ""
var _items: Array[Dictionary] = []
var _selected := -1
var _picker: AmountPicker
var _confirm: Button


func _init() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("modal_menus")


# --- For subclasses ----------------------------------------------------------------

## [[label, command id], ...]. "Leave" is added after them.
func commands() -> Array:
	return []


func items_for(_command_id: String) -> Array[Dictionary]:
	return []


func header_text() -> String:
	var save := player.save
	return "Oro %s    Pack %d / %d" % [_num(save.inventory.oro), save.pack_used(), Inventory.PACK_SLOTS]


## The Seeker's save, for subclasses.
func save() -> SaveData:
	return player.save


# --- Opening and closing ---------------------------------------------------------------

func open(seeker: Player) -> void:
	player = seeker
	_build()
	player.input_locked = true
	player.set_mouse_captured(false)
	_refresh_header()
	_focus_first(_commands)


func close() -> void:
	if player:
		player.input_locked = player.downed
		player.set_mouse_captured(true)
		player.hold_input()
		player.apply_bonuses()
		player.save_game()
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if _root:
		MenuFocus.recover(_root, event, focus_default)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		close()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back()


## B: offer -> list -> commands -> leave.
func back() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if _offer.get_child_count() > 0:
		_clear(_offer)
		_select_focus(_selected)
	elif focus and _list.is_ancestor_of(focus):
		_focus_command()
	else:
		close()


func focus_default() -> void:
	if _offer.get_child_count() > 0 and _confirm:
		_grab(_confirm)
	elif not _command.is_empty() and _list.get_child_count() > 0:
		_select_focus(maxi(_selected, 0))
	else:
		_focus_first(_commands)


# --- Layout -----------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -580.0
	panel.offset_top = -330.0
	panel.offset_right = 580.0
	panel.offset_bottom = 330.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.96)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20.0)
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	panel.add_child(page)

	var top := HBoxContainer.new()
	page.add_child(top)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(names)
	names.add_child(_label(title, 26))
	_greeting = _label(greeting, 15)
	_greeting.modulate = Color(0.75, 0.85, 1.0)
	names.add_child(_greeting)
	_header = _label("", 18)
	_header.modulate = Color(1.0, 0.88, 0.5)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_header)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	page.add_child(body)
	_commands = _column(body, 200.0)
	for spec in commands():
		_command_button(spec[0], spec[1])
	_command_button("Leave", "")
	_commands.add_child(_label("\nA: choose   B: back\nStart: leave", 13))

	var middle := _column(body, 450.0)
	_list_title = _label("", 18)
	middle.add_child(_list_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(450.0, 480.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 1)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	middle.add_child(scroll)

	var right := _column(body, 420.0)
	_detail = _label("", 16)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(420.0, 200.0)
	right.add_child(_detail)
	_offer = VBoxContainer.new()
	_offer.add_theme_constant_override("separation", 6)
	right.add_child(_offer)
	_message = _label("", 16)
	_message.modulate = Color(1.0, 0.85, 0.5)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.x = 420.0
	right.add_child(_message)


func _column(parent: Node, width: float) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 4)
	c.custom_minimum_size.x = width
	parent.add_child(c)
	return c


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _command_button(text: String, id: String) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 36.0
	b.set_meta("command", id)
	b.pressed.connect(func():
		if id == "":
			close()
		else:
			show_command(id))
	_commands.add_child(b)


# --- Commands and lists -------------------------------------------------------------------

## Opens a command's list and focuses its first entry.
func show_command(id: String) -> void:
	_command = id
	for b in _commands.get_children():
		if b is Button:
			(b as Button).text = ("> " if b.get_meta("command", "") == id else "") + \
				(b as Button).text.trim_prefix("> ")
	_message.text = ""
	_rebuild_list()
	if _list.get_child_count() > 0 and _list.get_child(0) is Button:
		_select_focus(0)


func _rebuild_list() -> void:
	_clear(_offer)
	_clear(_list)
	_items = items_for(_command)
	for spec in commands():
		if spec[1] == _command:
			_list_title.text = spec[0]
	for i in _items.size():
		var item := _items[i]
		var b := Button.new()
		b.text = item.text
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.modulate = item.get("color", Color.WHITE)
		if String(item.get("error", "")) != "":
			b.modulate = b.modulate * Color(1, 1, 1, 0.5)
		b.focus_entered.connect(func():
			if _offer.get_child_count() == 0:
				_selected = i
				_detail.text = item.get("detail", ""))
		b.pressed.connect(_select.bind(i))
		_list.add_child(b)
	if _items.is_empty():
		_list.add_child(_label("Nothing here.", 15))
		_detail.text = ""
	_refresh_header()


## A on an entry: shows the offer (amount and confirm), or why not.
func _select(index: int) -> void:
	_selected = index
	var item := _items[index]
	_detail.text = item.get("detail", "")
	_clear(_offer)
	if String(item.get("error", "")) != "":
		_message.text = item.error
		return
	var most := int(item.get("max", 1))
	_picker = null
	if most > 1:
		_picker = AmountPicker.new().setup(most, int(item.get("start", 1)), bool(item.get("big_steps", false)))
		_offer.add_child(_picker)
	_confirm = Button.new()
	_confirm.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_confirm.custom_minimum_size.y = 38.0
	var confirm: Callable = item.confirm
	_confirm.text = confirm.call(_picker.value if _picker else 1)
	if _picker:
		_picker.changed.connect(func(v: int): _confirm.text = confirm.call(v))
	_confirm.pressed.connect(_do.bind(index))
	_offer.add_child(_confirm)
	if _picker:
		_picker.wire(null, _confirm)
	_grab(_confirm)


func _do(index: int) -> void:
	var item := _items[index]
	var act: Callable = item.act
	_message.text = act.call(_picker.value if _picker else 1)
	_rebuild_list()
	_select_focus(mini(index, _items.size() - 1))


func _select_focus(index: int) -> void:
	var buttons: Array = []
	for b in _list.get_children():
		if b is Button and not b.is_queued_for_deletion():
			buttons.append(b)
	if buttons.is_empty():
		_focus_command()
		return
	_grab(buttons[clampi(index, 0, buttons.size() - 1)])


func _focus_command() -> void:
	for b in _commands.get_children():
		if b is Button and b.get_meta("command", "") == _command:
			_grab(b)
			return
	_focus_first(_commands)


func _refresh_header() -> void:
	if _header and player:
		_header.text = header_text()


func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	if box == _offer:
		_picker = null
		_confirm = null


func _focus_first(box: Container) -> void:
	for child in box.get_children():
		if child is Button and not child.is_queued_for_deletion():
			_grab(child)
			return


## Deferred focus that survives rebuilt lists.
func _grab(control: Control) -> void:
	(func():
		if is_instance_valid(control) and control.is_inside_tree() and not control.is_queued_for_deletion():
			control.grab_focus()).call_deferred()


static func _num(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## The listing's buttons (tests).
func list_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for b in _list.get_children():
		if b is Button and not b.is_queued_for_deletion():
			out.append(b)
	return out
