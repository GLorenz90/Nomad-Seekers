class_name PlayerInput
extends RefCounted
## One Seeker's controls (Part 12, local co-op).
##
## Alone, a Seeker reads the shared actions ("jump", "hand_x", ...), which every
## device drives, exactly like before co-op. In a party each Seeker gets a slot:
## bind() copies every game action to "p<slot>_<action>" bound only to that
## Seeker's controller (and, for the leader, the keyboard and mouse too), so two
## controllers never move the same Seeker.
##
## Polling code asks the Seeker's input instead of Input:
##   player.input.just_pressed("jump") instead of Input.is_action_just_pressed("jump")
## Event code (menus, mouse look) asks owns(event) to ignore other Seekers'
## devices; in split-screen each pane only forwards its own Seeker's events.

const MAX_PLAYERS := 4

## -1: the shared actions (single player). 0-3: this Seeker's own actions.
var slot := -1
## The joypad this Seeker uses (-1: none yet).
var device := -1
## The keyboard and mouse belong to this Seeker (the party leader).
var keyboard := true


static func shared() -> PlayerInput:
	return PlayerInput.new()


## A Seeker's own copy of every game action, bound to one joypad (and the
## keyboard and mouse when `with_keyboard`).
static func bind(player_slot: int, joypad: int, with_keyboard: bool) -> PlayerInput:
	var input := PlayerInput.new()
	input.slot = player_slot
	input.device = joypad
	input.keyboard = with_keyboard
	var prefix := "p%d_" % (player_slot + 1)
	for action in game_actions():
		var own := StringName(prefix + String(action))
		if InputMap.has_action(own):
			InputMap.erase_action(own)
		InputMap.add_action(own, InputMap.action_get_deadzone(action))
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				var copy := event.duplicate() as InputEvent
				copy.device = joypad
				InputMap.action_add_event(own, copy)
			elif with_keyboard:
				InputMap.action_add_event(own, event.duplicate() as InputEvent)
	return input


## The shared game actions (not Godot's ui_* ones, nor the per-Seeker copies).
static func game_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	for action in InputMap.get_actions():
		var s := String(action)
		if s.begins_with("ui_") or (s.length() > 3 and s[0] == "p" and s[1].is_valid_int() and s[2] == "_"):
			continue
		out.append(action)
	return out


func is_shared() -> bool:
	return slot < 0


func action(name: StringName) -> StringName:
	return name if slot < 0 else StringName("p%d_%s" % [slot + 1, name])


func pressed(name: StringName) -> bool:
	return Input.is_action_pressed(action(name))


func just_pressed(name: StringName) -> bool:
	return Input.is_action_just_pressed(action(name))


func just_released(name: StringName) -> bool:
	return Input.is_action_just_released(action(name))


func axis(negative: StringName, positive: StringName) -> float:
	return Input.get_axis(action(negative), action(positive))


func vector(left: StringName, right: StringName, up: StringName, down: StringName) -> Vector2:
	return Input.get_vector(action(left), action(right), action(up), action(down))


## Whether an input event came from this Seeker's devices.
func owns(event: InputEvent) -> bool:
	if slot < 0:
		return true
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return event.device == device
	return keyboard


## Only the keyboard-and-mouse Seeker captures or frees the mouse.
func uses_mouse() -> bool:
	return keyboard
