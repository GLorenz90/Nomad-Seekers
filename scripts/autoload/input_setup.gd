extends Node
## Registers every input action in code, so the whole control map is in one
## readable place (North Star §4.1). Gamepad first, keyboard/mouse as a fallback
## for testing at a desk.
##
## Events are bound to ALL devices for now. Couch co-op (Part 8) will switch to
## per-device actions or per-player device filtering.

const STICK_DEADZONE := 0.2
const TRIGGER_DEADZONE := 0.4


func _enter_tree() -> void:
	# --- Movement: left stick / WASD ---
	_define("move_left", STICK_DEADZONE)
	_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_key("move_left", KEY_A)
	_define("move_right", STICK_DEADZONE)
	_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_key("move_right", KEY_D)
	_define("move_forward", STICK_DEADZONE)
	_joy_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_key("move_forward", KEY_W)
	_define("move_back", STICK_DEADZONE)
	_joy_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_key("move_back", KEY_S)

	# --- Camera: right stick / arrow keys (mouse look is handled by CameraRig) ---
	_define("look_left", STICK_DEADZONE)
	_joy_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_key("look_left", KEY_LEFT)
	_define("look_right", STICK_DEADZONE)
	_joy_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_key("look_right", KEY_RIGHT)
	_define("look_up", STICK_DEADZONE)
	_joy_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_key("look_up", KEY_UP)
	_define("look_down", STICK_DEADZONE)
	_joy_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_key("look_down", KEY_DOWN)

	# --- Movement buttons ---
	_define("jump")
	_joy_button("jump", JOY_BUTTON_A)
	_key("jump", KEY_SPACE)
	_define("dash")
	_joy_button("dash", JOY_BUTTON_B)
	_key("dash", KEY_SHIFT)
	_define("lock_on")  # Lock on / recenter camera when nothing is in range
	_joy_button("lock_on", JOY_BUTTON_RIGHT_STICK)
	_key("lock_on", KEY_Q)
	_mouse("lock_on", MOUSE_BUTTON_MIDDLE)

	# --- Combat (defined now, used from Part 2 on) ---
	_define("hand_x")
	_joy_button("hand_x", JOY_BUTTON_X)
	_mouse("hand_x", MOUSE_BUTTON_LEFT)
	_define("hand_y")
	_joy_button("hand_y", JOY_BUTTON_Y)
	_mouse("hand_y", MOUSE_BUTTON_RIGHT)
	_define("shift", TRIGGER_DEADZONE)  # RT: special / switch spell
	_joy_axis("shift", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_key("shift", KEY_E)
	_define("block", TRIGGER_DEADZONE)  # LT: block / powerstance
	_joy_axis("block", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_key("block", KEY_F)
	_define("loadout_prev")
	_joy_button("loadout_prev", JOY_BUTTON_LEFT_SHOULDER)
	_key("loadout_prev", KEY_Z)
	_define("loadout_next")
	_joy_button("loadout_next", JOY_BUTTON_RIGHT_SHOULDER)
	_key("loadout_next", KEY_C)
	_define("sync_burst")
	_joy_button("sync_burst", JOY_BUTTON_LEFT_STICK)
	_key("sync_burst", KEY_R)
	# Quick-use consumables: D-pad left / up / right, keys 1 / 2 / 3.
	for i in 3:
		var action := "item_%d" % (i + 1)
		_define(action)
		_joy_button(action, [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT][i])
		_key(action, [KEY_1, KEY_2, KEY_3][i])

	# --- System ---
	_define("pause")  # Esc releases the mouse
	_key("pause", KEY_ESCAPE)
	_define("menu")  # Loadout menu
	_joy_button("menu", JOY_BUTTON_START)
	_key("menu", KEY_TAB)
	_define("toggle_debug")
	_joy_button("toggle_debug", JOY_BUTTON_BACK)
	_key("toggle_debug", KEY_F3)
	# Menus: Godot's built-in ui_accept / ui_cancel have no gamepad buttons.
	# A accepts and B cancels (keeping Enter / Space / Esc).
	_joy_button("ui_accept", JOY_BUTTON_A)
	_joy_button("ui_cancel", JOY_BUTTON_B)


func _define(action: StringName, deadzone: float = 0.5) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
		InputMap.action_set_deadzone(action, deadzone)
	else:
		InputMap.add_action(action, deadzone)


func _key(action: StringName, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.device = -1
	InputMap.action_add_event(action, event)


func _mouse(action: StringName, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.device = -1
	InputMap.action_add_event(action, event)


func _joy_button(action: StringName, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.device = -1
	InputMap.action_add_event(action, event)


func _joy_axis(action: StringName, axis: JoyAxis, direction: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = direction
	event.device = -1
	InputMap.action_add_event(action, event)
