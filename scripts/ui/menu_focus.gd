class_name MenuFocus
extends RefCounted
## Keeps menus usable with a gamepad (Part 8 fix). A menu with nothing focused
## ignores the controller: that happens after a mouse click on empty space
## (clicking the window to bring it forward clears GUI focus), or when the
## focused button is hidden or freed. Menus call recover() from _input: any
## gamepad press or stick push while nothing in the menu has focus puts focus
## back on the menu's default button and uses up that press.
## (A or a direction only: B, Start and the shoulders still do their job.)


const NAV_ACTIONS: Array[StringName] = [&"ui_accept", &"ui_up", &"ui_down", &"ui_left", &"ui_right"]


## True for a gamepad A press or d-pad / left-stick push. B, Start and the
## shoulders keep their own jobs (back, close, switch tabs).
static func is_pad_input(event: InputEvent) -> bool:
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return false
	for action in NAV_ACTIONS:
		if event.is_action_pressed(action):
			return true
	return false


## True when nothing inside `menu` has focus.
static func lost(menu: Node) -> bool:
	var vp := menu.get_viewport()
	if vp == null:
		return false
	var f := vp.gui_get_focus_owner()
	return f == null or not f.is_visible_in_tree() or not menu.is_ancestor_of(f)


## Call from _input. Returns true (and handles the event) when focus had to be
## restored with `focus_default`.
static func recover(menu: Node, event: InputEvent, focus_default: Callable) -> bool:
	if not is_pad_input(event) or not lost(menu):
		return false
	focus_default.call()
	menu.get_viewport().set_input_as_handled()
	return true
