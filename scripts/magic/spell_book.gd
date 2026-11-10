class_name SpellBook
extends RefCounted
## Every spell and Goluman trap (Part 6), from Grayson's spell grid
## (2026-11-08). Names are Esperanto: fajro fire, glacio ice, fulmo lightning,
## arbo nature, lumo light, malbo dark; mez- burst, gran- area, dau- sustained,
## bona- buff, mala- debuff, pas- aura.
##
## Numbers follow PSO's techniques where Grayson named one ("exactly like
## Foie" uses Foie's power table); the rest are best guesses in the same
## shape, marked "guess". Tune them here.
##
## Power tables (PSO technique base power, Ephinea wiki): Vector2(base, growth)
## for levels 1-15, then levels 16-30.

const FOIE := [Vector2(110, 50), Vector2(-85, 65)]
const GIFOIE := [Vector2(260, 26), Vector2(30, 42)]
const RAFOIE := [Vector2(350, 22), Vector2(370, 21)]
const BARTA := [Vector2(50, 50), Vector2(-125, 63)]
const GIBARTA := [Vector2(231, 23), Vector2(0, 40)]
const RABARTA := [Vector2(399, 20), Vector2(470, 15)]
const ZONDE := [Vector2(80, 50), Vector2(5, 55)]
const GIZONDE := [Vector2(200, 22), Vector2(-30, 38)]
const RAZONDE := [Vector2(450, 16), Vector2(550, 9)]
const GRANTS := [Vector2(1180, 75), Vector2(1400, 60)]
## Guesses for what PSO doesn't have.
const MEGID := [Vector2(90, 55), Vector2(0, 60)]          ## PSU-style damage Megid
const GI_AVERAGE := [Vector2(230, 24), Vector2(0, 40)]    ## Gifoie / Gibarta / Gizonde
const RA_AVERAGE := [Vector2(400, 19), Vector2(463, 15)]  ## Rafoie / Rabarta / Razonde
const CHANNEL := [Vector2(40, 6), Vector2(-5, 9)]         ## per tick (4 ticks a second)
const AURA := [Vector2(20, 4), Vector2(0, 5)]             ## per tick (2 ticks a second)
const RESTA := [Vector2(50, 5), Vector2(50, 5)]
const TRAP_DAMAGE := [Vector2(300, 22), Vector2(320, 21)] ## like Rafoie
const TRAP_STATUS := [Vector2(80, 10), Vector2(50, 12)]

static var _all: Array[SpellDef] = []
static var _by_id := {}


static func all() -> Array[SpellDef]:
	if _all.is_empty():
		_build()
	return _all


static func get_spell(id: StringName) -> SpellDef:
	if _all.is_empty():
		_build()
	return _by_id.get(id)


static func spells_only() -> Array[SpellDef]:
	return all().filter(func(s: SpellDef) -> bool: return not s.is_trap())


static func traps_only() -> Array[SpellDef]:
	return all().filter(func(s: SpellDef) -> bool: return s.is_trap())


static func _add(s: SpellDef) -> SpellDef:
	_all.append(s)
	_by_id[s.id] = s
	return s


static func _make(id: String, element: Element.Type, kind: SpellDef.Kind, shape: SpellDef.Shape,
		req: int, table: Array) -> SpellDef:
	var s := SpellDef.new()
	s.id = StringName(id)
	s.display_name = id.capitalize()
	s.element = element
	s.kind = kind
	s.shape = shape
	s.req_base = req
	s.power_low = table[0]
	s.power_high = table[1]
	return _add(s)


static func _build() -> void:
	_all.clear()
	_by_id.clear()
	var roots := {
		Element.Type.FIRE: "fajro", Element.Type.ICE: "glacio", Element.Type.LIGHTNING: "fulmo",
		Element.Type.NATURE: "arbo", Element.Type.LIGHT: "lumo", Element.Type.DARK: "malbo",
	}
	# SOL tiers from the grid: Fire / Ice / Lightning, then Nature / Light / Dark.
	for element in roots:
		var root: String = roots[element]
		var late: bool = element in [Element.Type.NATURE, Element.Type.LIGHT, Element.Type.DARK]
		var bolt_req := 80 if late else 40
		var mid_req := 120 if late else 100
		var big_req := 180 if late else 130
		var support_req := 100 if late else 60
		_bolt(element, root, bolt_req)
		_burst(element, root, mid_req)
		_area(element, root, big_req)
		_sustained(element, root, mid_req)
		_buff(element, root, support_req)
		_debuff(element, root, support_req)
		_aura(element, root, big_req)
	_typeless()
	_traps()


# --- Single target ---------------------------------------------------------------

static func _bolt(element: Element.Type, root: String, req: int) -> void:
	var s: SpellDef
	match element:
		Element.Type.FIRE:
			# PSO Foie: a fireball that gets much faster with level.
			s = _make(root, element, SpellDef.Kind.BOLT, SpellDef.Shape.PROJECTILE, req, FOIE)
			s.speed = 12.0
			s.speed_growth = 0.95
			s.radius = 0.25
		Element.Type.ICE:
			# Ice spear through every enemy in a line (PSO Barta's power).
			s = _make(root, element, SpellDef.Kind.BOLT, SpellDef.Shape.PIERCE_LINE, req, BARTA)
			s.speed = 22.0
			s.speed_growth = 0.4
			s.radius = 0.2
			s.pierce = true
		Element.Type.LIGHTNING:
			# PSO Zonde: lightning on the target, instantly.
			s = _make(root, element, SpellDef.Kind.BOLT, SpellDef.Shape.SKY_STRIKE, req, ZONDE)
			s.reach = 14.0
		Element.Type.NATURE:
			# Barta as thorns along the ground through a line.
			s = _make(root, element, SpellDef.Kind.BOLT, SpellDef.Shape.GROUND_LINE, req, BARTA)
			s.speed = 12.0
			s.speed_growth = 0.3
			s.reach = 12.0
		Element.Type.LIGHT:
			# PSU Grants: a long cast, then a beam on one target. The strongest single hit.
			s = _make(root, element, SpellDef.Kind.BOLT, SpellDef.Shape.SKY_STRIKE, req, GRANTS)
			s.reach = 18.0
			s.cast_frames = 30
			s.total_frames = 55
			s.lp_base = 45.0
			s.lp_growth = 1.0
		Element.Type.DARK:
			# PSU Megid: a slow dark orb that homes in. Guess: Zonde-like power.
			s = _make(root, element, SpellDef.Kind.BOLT, SpellDef.Shape.HOMING_ORB, req, MEGID)
			s.speed = 7.0
			s.speed_growth = 0.25
			s.radius = 0.35
			s.reach = 18.0
			s.lp_base = 8.0
			s.lp_growth = 1.4
	s.status_ok = false


# --- Small burst -----------------------------------------------------------------

static func _burst(element: Element.Type, root: String, req: int) -> void:
	var id := "mez" + root
	var s: SpellDef
	match element:
		Element.Type.FIRE:
			# PSO Gifoie: fire spirals out around the caster, each enemy hit once.
			s = _make(id, element, SpellDef.Kind.BURST, SpellDef.Shape.RING_OUT, req, GIFOIE)
			s.radius = 3.5
			s.radius_growth = 0.07
			s.cast_frames = 22
			s.total_frames = 50
		Element.Type.ICE:
			# Ice spear shotgun: a fan of spears that pass through enemies.
			s = _make(id, element, SpellDef.Kind.BURST, SpellDef.Shape.SPEAR_FAN, req, GIBARTA)
			s.speed = 22.0
			s.radius = 0.18
			s.cone_deg = 40.0
			s.max_targets = 5  # spears
			s.reach = 14.0
			s.pierce = true
		Element.Type.LIGHTNING:
			# PSO Gizonde: chains from enemy to enemy.
			s = _make(id, element, SpellDef.Kind.BURST, SpellDef.Shape.CHAIN, req, GIZONDE)
			s.reach = 12.0
			s.radius = 4.5  # hop distance
			s.radius_growth = 0.05
		Element.Type.NATURE:
			# Thorns burst up under every enemy in a 30-degree cone.
			s = _make(id, element, SpellDef.Kind.BURST, SpellDef.Shape.CONE_STRIKE, req, GI_AVERAGE)
			s.cone_deg = 30.0
			s.reach = 9.0
			s.max_targets = 99
		Element.Type.LIGHT:
			# Beams from the sky on up to 10 enemies in a 60-degree cone.
			s = _make(id, element, SpellDef.Kind.BURST, SpellDef.Shape.CONE_STRIKE, req, GI_AVERAGE)
			s.cone_deg = 60.0
			s.reach = 10.0
			s.max_targets = 10
		Element.Type.DARK:
			# A large, slow gravity ball that rolls through enemies.
			s = _make(id, element, SpellDef.Kind.BURST, SpellDef.Shape.BIG_ORB, req, GI_AVERAGE)
			s.speed = 5.0
			s.speed_growth = 0.1
			s.radius = 1.1
			s.reach = 14.0
			s.pierce = true
	s.lp_base = 20.0
	s.lp_growth = 0.37


# --- Large area ------------------------------------------------------------------

static func _area(element: Element.Type, root: String, req: int) -> void:
	var id := "gran" + root
	var s: SpellDef
	match element:
		Element.Type.FIRE:
			# PSO Rafoie: a quick explosion at the target.
			s = _make(id, element, SpellDef.Kind.AREA, SpellDef.Shape.TARGET_AREA, req, RAFOIE)
		Element.Type.ICE:
			# Ice spear rain on every enemy around the caster.
			s = _make(id, element, SpellDef.Kind.AREA, SpellDef.Shape.AROUND_CASTER, req, RABARTA)
			s.radius = 5.0
			s.radius_growth = 0.1
		Element.Type.LIGHTNING:
			# PSO Razonde: lightning on everything around the target.
			s = _make(id, element, SpellDef.Kind.AREA, SpellDef.Shape.TARGET_AREA, req, RAZONDE)
		Element.Type.NATURE:
			# Rabarta as thorny vines spreading out along the ground.
			s = _make(id, element, SpellDef.Kind.AREA, SpellDef.Shape.RING_OUT, req, RABARTA)
			s.radius = 5.0
			s.radius_growth = 0.1
		Element.Type.LIGHT:
			# Sky beams on every enemy within Granfajro's range of the target.
			s = _make(id, element, SpellDef.Kind.AREA, SpellDef.Shape.TARGET_AREA, req, RA_AVERAGE)
		Element.Type.DARK:
			# A gravity pit at the target that drags enemies in.
			s = _make(id, element, SpellDef.Kind.AREA, SpellDef.Shape.GRAVITY_PIT, req, RA_AVERAGE)
	if s.shape in [SpellDef.Shape.TARGET_AREA, SpellDef.Shape.GRAVITY_PIT]:
		s.radius = 3.0  # Rafoie's blast, growing with level
		s.radius_growth = 0.08
		s.reach = 14.0
	s.cast_frames = 12
	s.total_frames = 32
	s.lp_base = 30.0
	s.lp_growth = 0.25


# --- Sustained (PSU Dam- techniques) ------------------------------------------------

static func _sustained(element: Element.Type, root: String, req: int) -> void:
	var s := _make("dau" + root, element, SpellDef.Kind.SUSTAINED, SpellDef.Shape.CHANNEL, req, CHANNEL)
	var cones := {
		Element.Type.FIRE: [30.0, 6.0], Element.Type.ICE: [50.0, 5.0], Element.Type.LIGHTNING: [15.0, 9.0],
		Element.Type.NATURE: [40.0, 6.0], Element.Type.LIGHT: [10.0, 12.0], Element.Type.DARK: [25.0, 7.0],
	}
	s.cone_deg = cones[element][0]
	s.reach = cones[element][1]
	s.lp_base = 1.5  # per tick
	s.lp_growth = 0.05
	s.cast_frames = 6
	s.total_frames = 18


# --- Buff / debuff / aura -------------------------------------------------------------

## Buff and debuff stats by element (Grayson's grid): Fire STR (Shifta / Jellen),
## Ice DEF (Deband / Zalure), Lightning DEX, Nature SOL, Light accuracy (PSU
## Rentis), Dark evasion (PSU Dizas).
const BUFF_STATS := {
	Element.Type.FIRE: &"strength", Element.Type.ICE: &"defense", Element.Type.LIGHTNING: &"dexterity",
	Element.Type.NATURE: &"soul", Element.Type.LIGHT: &"accuracy", Element.Type.DARK: &"evasion",
}


static func _buff(element: Element.Type, root: String, req: int) -> void:
	var id := "bona" + root if root != "arbo" else "bonarbo"
	var s := _make(id, element, SpellDef.Kind.BUFF, SpellDef.Shape.SELF, req, [Vector2(0, 0), Vector2(0, 0)])
	s.stat = BUFF_STATS[element]
	s.radius = 10.0  # whole nearby party
	s.radius_growth = 0.0
	s.lp_base = 10.0
	s.lp_growth = 0.3
	s.status_ok = false


static func _debuff(element: Element.Type, root: String, req: int) -> void:
	var id := "mala" + root if root != "arbo" else "malarbo"
	var s := _make(id, element, SpellDef.Kind.DEBUFF, SpellDef.Shape.AROUND_CASTER, req, [Vector2(0, 0), Vector2(0, 0)])
	s.stat = BUFF_STATS[element]
	s.radius = 7.0
	s.radius_growth = 0.1
	s.lp_base = 10.0
	s.lp_growth = 0.3
	s.status_ok = false


static func _aura(element: Element.Type, root: String, req: int) -> void:
	var s := _make("pas" + root, element, SpellDef.Kind.AURA, SpellDef.Shape.SELF, req, AURA)
	s.radius = 3.0
	s.radius_growth = 0.05
	s.lp_base = 15.0
	s.lp_growth = 0.3
	# Only the Dark aura can inflict its status (Drain), per the grid.
	s.status_ok = element == Element.Type.DARK


## Buff strength: +10% at level 1, +1.2% a level (+44.8% at 30). Guess shaped
## like PSO Shifta / Deband; debuffs are the same downwards but 1% a level.
static func buff_fraction(level: int) -> float:
	return 0.10 + 0.012 * (level - 1)


static func debuff_fraction(level: int) -> float:
	return -(0.10 + 0.01 * (level - 1))


static func buff_seconds(level: int) -> float:
	return 30.0 + 2.0 * (level - 1)


static func debuff_seconds(level: int) -> float:
	return 20.0 + 1.0 * (level - 1)


static func aura_seconds(level: int) -> float:
	return 30.0 + 2.0 * (level - 1)


# --- Typeless -----------------------------------------------------------------------

static func _typeless() -> void:
	# PSO Resta: heals everyone around the caster.
	var heal := _make("heal", Element.Type.GENERIC, SpellDef.Kind.HEAL, SpellDef.Shape.SELF, 50, RESTA)
	heal.display_name = "Heal"
	heal.radius = 3.0
	heal.radius_growth = 0.15
	heal.lp_base = 10.0
	heal.lp_growth = 0.5
	heal.status_ok = false
	# PSO Anti: one level per status, least annoying first; the last also clears debuffs.
	var cure := _make("cure", Element.Type.GENERIC, SpellDef.Kind.CURE, SpellDef.Shape.SELF, 80, RESTA)
	cure.display_name = "Cure"
	cure.max_level = StatusEffects.CURE_ORDER.size() + 1
	cure.req_steps = SpellDef.REQ_CURE
	cure.radius = 4.0
	cure.radius_growth = 0.3
	cure.lp_base = 11.0
	cure.lp_growth = 1.0
	cure.status_ok = false
	# Portal back to the ship (the gym for now). No levels.
	var portal := _make("teleportal", Element.Type.GENERIC, SpellDef.Kind.TELEPORTAL, SpellDef.Shape.SELF, 150, RESTA)
	portal.display_name = "Teleportal"
	portal.max_level = 1
	portal.req_steps = SpellDef.REQ_NONE
	portal.lp_base = 20.0
	portal.lp_growth = 0.0
	portal.status_ok = false
	# PSO Reverser: revives a downed ally with 2.5% max HP per level.
	var revive := _make("revive", Element.Type.GENERIC, SpellDef.Kind.REVIVE, SpellDef.Shape.SELF, 150, RESTA)
	revive.display_name = "Revive"
	revive.max_level = 10
	revive.req_steps = SpellDef.REQ_REVIVE
	revive.radius = 6.0
	revive.radius_growth = 0.0
	revive.lp_base = 20.0
	revive.lp_growth = 1.0
	revive.status_ok = false
	revive.cast_frames = 30
	revive.total_frames = 60


static func revive_fraction(level: int) -> float:
	return 0.025 * clampi(level, 1, 10)


# --- Goluman traps --------------------------------------------------------------------

## [id, name, element, status, DEX for level 1]. Guess: requirement and power.
const TRAPS := [
	["damage_trap", "Damage Trap", Element.Type.FIRE, -1, 40],
	["slow_trap", "Slow Trap", Element.Type.ICE, StatusEffects.Status.SLOW, 40],
	["shock_trap", "Shock Trap", Element.Type.LIGHTNING, StatusEffects.Status.SHOCK, 60],
	["poison_trap", "Poison Trap", Element.Type.NATURE, StatusEffects.Status.POISON, 60],
	["confuse_trap", "Confuse Trap", Element.Type.LIGHT, StatusEffects.Status.BLIND, 80],
	["freeze_trap", "Freeze Trap", Element.Type.ICE, StatusEffects.Status.FREEZE, 100],
	# The id keeps its old name so saves that learned it still have it.
	["paralyze_trap", "Stun Trap", Element.Type.GENERIC, StatusEffects.Status.STUN, 120],
]


static func _traps() -> void:
	for spec in TRAPS:
		var s := _make(spec[0], spec[2], SpellDef.Kind.TRAP, SpellDef.Shape.SELF, spec[4],
			TRAP_DAMAGE if spec[3] < 0 else TRAP_STATUS)
		s.display_name = spec[1]
		s.trap_status = spec[3]
		s.radius = 2.5
		s.radius_growth = 0.05
		s.lp_base = 10.0
		s.lp_growth = 0.3
		s.cast_frames = 10
		s.total_frames = 24


## Status length from a trap: 2 s at level 1, +0.1 s a level.
static func trap_status_seconds(level: int) -> float:
	return 2.0 + 0.1 * (level - 1)
