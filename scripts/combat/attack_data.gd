class_name AttackData
extends Resource
## One attack: a single step of a weapon's combo, or one spell cast.
##
## All times are seconds from the start of the attack.
##   active_start..active_end   melee hitbox is live / projectile fires at active_start
##   window_open..window_close  pressing either hand here chains the next combo step
##   duration                   the Seeker is committed (can't move) until this
## Pressing before window_open breaks the combo (PSO timing). window_close can
## run past duration, which gives a short grace period after the attack ends.

enum Swing { SLASH_RIGHT, SLASH_LEFT, OVERHEAD, THRUST, SHOT, CAST, SPIN }
## Support spells act on the caster instead of hitting enemies.
enum Support { NONE, HEAL, CURE }

@export var display_name := ""
@export var damage_mult := 1.0
## Overrides the weapon's damage type when set (spells use this).
@export var override_damage_type := false
@export var damage_type: Element.Type = Element.Type.GENERIC
@export var lp_cost := 0.0
## Multiplies the status buildup this attack's elemental damage adds.
@export var status_power := 1.0
@export var swing: Swing = Swing.SLASH_RIGHT

@export_group("Movement")
## 0 = rooted in place for the attack. Above 0 = the Seeker can keep moving at
## this fraction of normal speed (PSU-style moving fire, spells, spins).
@export_range(0.0, 1.0) var move_speed_scale := 0.0
## Mobile attacks normally keep facing their aim (strafe while firing). Set this
## to turn toward the movement direction instead (spins).
@export var face_movement := false

@export_group("Timing")
@export var duration := 0.45
@export var active_start := 0.12
@export var active_end := 0.24
@export var window_open := 0.28
@export var window_close := 0.6

@export_group("Melee")
@export var lunge_distance := 0.5
## Distance from the Seeker's center to the hitbox center.
@export var reach := 1.1
@export var hitbox_size := Vector3(2.2, 1.6, 1.8)
## Pushes targets away (m/s) on hit. Heavy Shield shove uses this.
@export var knockback := 0.0
## Seconds of parry opened when the attack starts (light shield deflect).
@export var opens_parry := 0.0

@export_group("Sustained")
## Sustained attacks only: seconds between hits while the button is held.
@export var sustained_tick := 0.15

@export_group("Projectile")
@export var is_projectile := false
@export var projectile_speed := 32.0
@export var projectile_radius := 0.12
@export var projectile_range := 30.0
@export var projectile_pierce := false
## Pellets per shot (shotguns), fanned across spread_deg.
@export var projectile_count := 1
@export var spread_deg := 0.0
## Downward pull in m/s². Above 0 the shot is lobbed in an arc at its target
## (grenades, launchers).
@export var projectile_gravity := 0.0
## Above 0: explodes on impact (or at the end of its range), hitting every
## target within this radius (bazooka, grenades).
@export var explosion_radius := 0.0
## Boomerang: homes in on up to this many targets, one after another.
@export var lock_targets := 0
## Gigarang: flies to its target (or its range), then comes back, hitting
## everything in its path both ways.
@export var returns := false
## Thrown weapons: step 3 of a chain that used this weapon for all three steps
## throws this many extra projectiles (North Star step-3 finisher).
@export var finisher_volley := 0
## PSO-shotgun targeting (Thrown Daggers, Cards, Burstbow): up to this many
## enemies ahead are picked, and one projectile flies at each. Each projectile
## can only hit its own target, so no enemy is hit twice by one attack.
@export var multi_target := 0
## Thrown weapons that scale off a different stat still count as ranged hits.
@export var ranged_hit := false

@export_group("Support")
@export var support: Support = Support.NONE
## HEAL: fraction of the caster's max HP restored.
@export var support_amount := 0.0
