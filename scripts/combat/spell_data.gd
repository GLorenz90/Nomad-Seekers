class_name SpellData
extends Resource
## A spell slotted into a casting item. Tap casts `normal`; holding charges `hard`.

@export var display_name := ""
@export var normal: AttackData
@export var hard: AttackData
