class_name EnemyData
extends Resource
## One enemy kind: stats, how it fights, and its placeholder look.
## The six monster types are from North Star §2.6.

enum EnemyType { BEAST, MUTATED, SYNTHETIC, DARK, ALCHEMIC, LIGHT }
enum AttackStyle { MELEE, RANGED, SPELL }
enum Shape { CAPSULE, BOX, SPHERE }

@export var display_name := ""
@export var enemy_type: EnemyType = EnemyType.BEAST
@export_multiline var notes := ""

@export_group("Stats")
@export var max_hp := 120.0
## Bosses can't be instantly killed or have their HP cut by tag specials.
@export var boss := false
## EXP for defeating it (0 = max_hp / 5).
@export var experience := 0
@export var defense := 10.0   ## vs melee and ranged
@export var resolve := 10.0   ## vs magic
@export var evasion := 60.0   ## EVA: how often Seeker weapon attacks miss (Accuracy)
@export var accuracy := 50.0  ## ATA: how often its attacks land on the Seeker
## Takes double damage of this type (GENERIC = none).
@export var weak_to: Element.Type = Element.Type.GENERIC
## Takes half damage of this type (GENERIC = none).
@export var resists: Element.Type = Element.Type.GENERIC

@export_group("Movement")
@export var move_speed := 3.5
@export var aggro_range := 14.0
## Floats above the ground (sprites, eyes).
@export var hover_height := 0.0

@export_group("Attack")
@export var attack_style: AttackStyle = AttackStyle.MELEE
@export var attack_damage := 15.0
@export var attack_element: Element.Type = Element.Type.GENERIC
@export var status_power := 1.0
## Melee: reach of the hit. Ranged / spell: distance it attacks from.
@export var attack_range := 2.2
## Ranged / spell: backs away if the Seeker gets closer than this.
@export var min_range := 0.0
## Melee: hits inside this arc in front (360 = all around, a slam).
@export var melee_arc_deg := 100.0
## Telegraph (glows in its element's color) before the attack lands.
@export var windup := 0.6
@export var recovery := 0.6
@export var attack_interval := 2.0
@export var projectile_speed := 12.0

@export_group("Look")
@export var shape: Shape = Shape.CAPSULE
@export var color := Color(0.7, 0.3, 0.25)
@export var size := Vector3(0.9, 1.8, 0.9)


func exp_value() -> int:
	return experience if experience > 0 else roundi(max_hp / 5.0)
