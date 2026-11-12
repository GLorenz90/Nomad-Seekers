class_name DecorAnimator
extends Node
## Animates its parent with a preset (Part 13a, level editor decorations), so
## levels can have swaying plants or sweeping searchlights without scripts.
##   sway   tilts back and forth (vegetation)
##   bob    floats up and down
##   spin   turns around Y
##   pulse  grows and shrinks a little
##   sweep  turns left and right (searchlights)
## `amount` scales the motion (0..2) and `speed` the rate (0.1..4).

@export var preset := "none"
@export var amount := 1.0
@export var speed := 1.0

var _base: Transform3D
var _t := 0.0
var _target: Node3D


func _ready() -> void:
	_target = get_parent() as Node3D
	amount = clampf(amount, 0.0, 2.0)
	speed = clampf(speed, 0.1, 4.0)
	if _target:
		_base = _target.transform
	_t = randf() * TAU  # neighbours don't move in lockstep
	set_process(_target != null and preset != "none")


func _process(delta: float) -> void:
	_t += delta * speed
	var t := _base
	match preset:
		"sway":
			t.basis = _base.basis * Basis(Vector3.FORWARD, sin(_t * 1.3) * 0.08 * amount)
		"bob":
			t.origin = _base.origin + Vector3.UP * sin(_t * 2.0) * 0.25 * amount
		"spin":
			t.basis = _base.basis * Basis(Vector3.UP, _t * 0.8 * amount)
		"pulse":
			t.basis = _base.basis.scaled(Vector3.ONE * (1.0 + sin(_t * 2.5) * 0.06 * amount))
		"sweep":
			t.basis = _base.basis * Basis(Vector3.UP, sin(_t * 0.6) * 0.9 * amount)
	_target.transform = t
