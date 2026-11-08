class_name Health
extends Node
## Hit points for anything that can be damaged. Attach as a child named "Health".

signal damaged(info: DamageInfo, amount: float)
signal died
signal restored
signal healed(amount: float)

@export var max_hp := 200.0

## Damage multiplier per Element.Type (missing = 1.0).
var multipliers: Dictionary = {}
var hp := 0.0


func _ready() -> void:
	hp = max_hp


func is_dead() -> bool:
	return hp <= 0.0


func take_damage(info: DamageInfo) -> float:
	if is_dead():
		return 0.0
	var amount: float = info.amount * float(multipliers.get(info.damage_type, 1.0))
	hp = maxf(hp - amount, 0.0)
	damaged.emit(info, amount)
	if is_dead():
		died.emit()
	return amount


## Restores up to amount HP. Returns how much was restored.
func heal(amount: float) -> float:
	if is_dead() or amount <= 0.0:
		return 0.0
	var before := hp
	hp = minf(hp + amount, max_hp)
	healed.emit(hp - before)
	return hp - before


func restore_full() -> void:
	hp = max_hp
	restored.emit()


static func find(node: Node) -> Health:
	if node == null:
		return null
	if node is Health:
		return node
	return node.get_node_or_null("Health") as Health
