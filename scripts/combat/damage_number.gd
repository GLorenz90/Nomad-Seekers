class_name DamageNumber
extends Label3D
## Floating number shown where a hit lands. Colored by damage type.


static func spawn(parent: Node, at: Vector3, amount: float, type: Element.Type, crit: bool) -> void:
	var n := DamageNumber.new()
	n.text = ("%d!" if crit else "%d") % roundi(amount)
	n.modulate = Element.color_of(type)
	n.font_size = 72 if crit else 54
	n.outline_size = 14
	n.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	n.no_depth_test = true
	n.render_priority = 2
	parent.add_child(n)
	n.global_position = at + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))

	var tween := n.create_tween().set_parallel(true)
	tween.tween_property(n, "global_position:y", n.global_position.y + 1.2, 0.8) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(n, "modulate:a", 0.0, 0.35).set_delay(0.45)
	tween.chain().tween_callback(n.queue_free)


## A word instead of a number ("Miss").
static func spawn_text(parent: Node, at: Vector3, text: String) -> void:
	var n := DamageNumber.new()
	n.text = text
	n.modulate = Color(0.85, 0.85, 0.85)
	n.font_size = 48
	n.outline_size = 12
	n.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	n.no_depth_test = true
	n.render_priority = 2
	parent.add_child(n)
	n.global_position = at
	var tween := n.create_tween().set_parallel(true)
	tween.tween_property(n, "global_position:y", at.y + 0.8, 0.6)
	tween.tween_property(n, "modulate:a", 0.0, 0.3).set_delay(0.3)
	tween.chain().tween_callback(n.queue_free)
