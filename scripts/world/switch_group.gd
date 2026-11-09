class_name SwitchGroup
extends Node
## Buttons that act together (Part 11, Grayson 2026-11-09). When every button
## in `buttons` is pressed, each node in `targets` gets
## switch_action(actions[i]): SwitchDoor "open" / "close" / "toggle",
## RoomHazard "disable" / "enable" / "toggle", WaveRoom "start", HazardTrap
## "disable" (traps off).
##
## Floor plates and players (Grayson): with fewer Seekers than plates, the
## first (plates - Seekers) plates stay pressed once stepped on; the rest
## need someone standing on them at the same time. Alone, all but the last
## latch (PSO's single-player rule); four plates and two Seekers: two latch,
## the last two need both Seekers.

signal fired

@export var buttons: Array[NodePath] = []
@export var targets: Array[NodePath] = []
@export var actions: PackedStringArray = []
## Fires once (most PSO switches); off: fires again each time it's satisfied.
@export var once := true

var done := false
var _buttons: Array[RoomButton] = []


func _ready() -> void:
	add_to_group("switch_groups")
	for path in buttons:
		var b := get_node_or_null(path) as RoomButton
		if b:
			b.group = self
			_buttons.append(b)
			b.refresh.call_deferred()


func seekers() -> int:
	return maxi(get_tree().get_nodes_in_group("player").size(), 1)


## How many floor plates may stay down without someone on them.
func max_latched() -> int:
	return maxi(_buttons.size() - seekers(), 0)


func latched_count() -> int:
	var n := 0
	for b in _buttons:
		if b.mode == RoomButton.Mode.FLOOR and b.latched:
			n += 1
	return n


func pressed_count() -> int:
	var n := 0
	for b in _buttons:
		if b.is_pressed():
			n += 1
	return n


func button_down(b: RoomButton) -> void:
	if b.mode == RoomButton.Mode.FLOOR and not b.latched and latched_count() < max_latched():
		b.latched = true
	_check()


func button_up(_b: RoomButton) -> void:
	for b in _buttons:
		b.refresh()


func _check() -> void:
	if done and once:
		return
	if pressed_count() < _buttons.size():
		for b in _buttons:
			b.refresh()
		return
	done = true
	for i in targets.size():
		var node := get_node_or_null(targets[i])
		if node and node.has_method("switch_action"):
			node.switch_action(actions[i] if i < actions.size() else "toggle")
	for b in _buttons:
		b.refresh()
	fired.emit()
	if not once:
		done = false
