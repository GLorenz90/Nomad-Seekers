class_name Leveling
extends RefCounted
## Character levels (Part 11, Grayson 2026-11-09).
##
## - **EXP curve: PSO's** (North Star §3), levels 1-200. Totals are PSO's own at
##   levels 1-50 and at every 10th level (and 141, 161-164, 199) from the
##   Ephinea PSO wiki's leveling table; the levels between those anchors are
##   filled in with smoothly growing increments that land exactly on the next
##   anchor (Claude's interpolation, never more than a few percent off a level).
## - **Stat growth: seven tables** (Grayson: one per race, one per job, so a new
##   race or job is one more table). A job table holds what that job gains
##   from level 1 to 200; a race table scales each stat. Gain at a level =
##   job gain x race scale x the stat's curve at that level. LCK never grows
##   (PSO).
## - Job tables come from PSO's human classes (level 200 minus level 1, Ephinea
##   wiki class comparison): Striker = HUmar, Ranger = RAmar / RAmarl,
##   Invoker = FOmar / FOmarl (FOmar's ATP / ATA). Race tables are the other
##   races' classes divided by the human ones, averaged over jobs: Lumera =
##   Newman, Coresian = CAST (HUcast / RAcast), Goluman = CASEAL (HUcaseal /
##   RAcaseal). PSO has one ATP; here the job's main attack stat gets it all
##   and the other gets 65% (Invokers 600 each). RES (not in PSO) is 75% of
##   the average of DFP and MST. CASTs have no MST / TP; Coresians (magic up
##   to level 10) and Goluman (no magic, traps) get half LP, and SOL x0.5 /
##   x0.25 (Claude's picks).
## - Curves are PSO's shapes, read off the same tables: attack stats, SOL,
##   LP, EVA and ATA grow early; HP later; DEF / RES latest.
## - The Stats resource is level 1; levels add on top, like materials and
##   race bonuses (Player.apply_bonuses).

const MAX_LEVEL := 200

## Total EXP to reach each level (index 0 = level 1).
const EXP_TABLE: Array[int] = [
	0, 50, 200, 450, 800, 1250, 1800, 2450, 3200, 4050,
	5000, 6050, 7200, 8450, 9848, 11427, 13252, 15364, 17785, 20539,
	23644, 27118, 30979, 35245, 39924, 45022, 50548, 56515, 62935, 69816,
	77165, 84993, 93309, 102126, 111455, 121310, 131698, 142625, 154103, 166145,
	178762, 191962, 205756, 220153, 235166, 250807, 267086, 284012, 301595, 319847,
	338739, 358292, 378531, 399479, 421161, 443602, 466830, 490872, 515757, 541513,
	567975, 595162, 623094, 651792, 681276, 711569, 742691, 774667, 807519, 841271,
	875870, 911338, 947695, 984965, 1023171, 1062335, 1102482, 1143637, 1185825, 1229071,
	1273266, 1318431, 1364587, 1411756, 1459960, 1509222, 1559565, 1611013, 1663590, 1717321,
	1772479, 1829103, 1887231, 1946902, 2008159, 2071044, 2135598, 2201868, 2269898, 2339735,
	2413177, 2490411, 2571632, 2657046, 2746870, 2841331, 2940668, 3045134, 3154993, 3270523,
	3392349, 3520815, 3656282, 3799132, 3949767, 4108611, 4276112, 4452742, 4638998, 4835405,
	5040374, 5254277, 5477505, 5710464, 5953578, 6207289, 6472060, 6748373, 7036730, 7337658,
	7648348, 7969116, 8300289, 8642205, 8995213, 9359672, 9735953, 10124440, 10525530, 10939630,
	11364163, 11800194, 12248033, 12708002, 13180428, 13665648, 14164010, 14675869, 15201591, 15741551,
	16293474, 16857625, 17434275, 18023701, 18626186, 19242020, 19871497, 20514921, 21172600, 21844850,
	22531485, 23232373, 23948794, 24679868, 25426075, 26187728, 26965148, 27758659, 28568596, 29395299,
	30240503, 31104623, 31988081, 32891310, 33814754, 34758863, 35724102, 36710942, 37719867, 38751371,
	39830480, 40959390, 42140400, 43375914, 44668448, 46020633, 47435223, 48915096, 50463267, 52082887,
	53891270, 55910417, 58164890, 60682118, 63492723, 66630898, 70134820, 74047117, 78415384, 83227800,
]

const STATS: Array[StringName] = [&"max_hp", &"max_lp", &"strength", &"dexterity", &"soul",
	&"defense", &"resolve", &"evasion", &"accuracy"]
const STAT_LABELS := {&"max_hp": "HP", &"max_lp": "LP", &"strength": "STR", &"dexterity": "DEX",
	&"soul": "SOL", &"defense": "DEF", &"resolve": "RES", &"evasion": "EVA", &"accuracy": "ATA"}

## Job tables: stat gains from level 1 to 200.
const JOB_GROWTH := {
	CharacterData.Job.STRIKER: {&"max_hp": 1380, &"max_lp": 764, &"strength": 898, &"dexterity": 584,
		&"soul": 565, &"defense": 405, &"resolve": 364, &"evasion": 637, &"accuracy": 107},
	CharacterData.Job.RANGER: {&"max_hp": 1389, &"max_lp": 798, &"strength": 488, &"dexterity": 752,
		&"soul": 599, &"defense": 380, &"resolve": 367, &"evasion": 683, &"accuracy": 148},
	CharacterData.Job.INVOKER: {&"max_hp": 1195, &"max_lp": 1662, &"strength": 600, &"dexterity": 600,
		&"soul": 909, &"defense": 326, &"resolve": 463, &"evasion": 497, &"accuracy": 78},
}
## Race tables: each stat's gain is scaled by these.
const RACE_GROWTH := {
	CharacterData.Race.HUMAN: {&"max_hp": 1.0, &"max_lp": 1.0, &"strength": 1.0, &"dexterity": 1.0,
		&"soul": 1.0, &"defense": 1.0, &"resolve": 1.0, &"evasion": 1.0, &"accuracy": 1.0},
	CharacterData.Race.LUMERA: {&"max_hp": 0.95, &"max_lp": 1.27, &"strength": 0.85, &"dexterity": 0.85,
		&"soul": 1.35, &"defense": 1.19, &"resolve": 1.27, &"evasion": 1.06, &"accuracy": 0.85},
	CharacterData.Race.CORESIAN: {&"max_hp": 1.27, &"max_lp": 0.5, &"strength": 1.14, &"dexterity": 1.0,
		&"soul": 0.5, &"defense": 1.3, &"resolve": 0.9, &"evasion": 0.92, &"accuracy": 0.88},
	CharacterData.Race.GOLUMAN: {&"max_hp": 1.21, &"max_lp": 0.5, &"strength": 0.95, &"dexterity": 1.1,
		&"soul": 0.25, &"defense": 1.12, &"resolve": 0.8, &"evasion": 1.03, &"accuracy": 1.0},
}

## Fraction of the level-200 gain reached at levels 1, 20, 40, 80, 150, 200.
const CURVE_LEVELS: Array[int] = [1, 20, 40, 80, 150, 200]
const CURVES := {
	&"early": [0.0, 0.13, 0.27, 0.51, 0.84, 1.0],  # PSO ATP / MST / EVP / TP / ATA
	&"hp": [0.0, 0.07, 0.14, 0.30, 0.70, 1.0],     # PSO HP
	&"late": [0.0, 0.03, 0.10, 0.27, 0.76, 1.0],   # PSO DFP
}
const STAT_CURVE := {&"max_hp": &"hp", &"defense": &"late", &"resolve": &"late"}


# --- EXP ---------------------------------------------------------------------------

static func level_for(experience: int) -> int:
	var lo := 0
	var hi := MAX_LEVEL - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if EXP_TABLE[mid] <= experience:
			lo = mid
		else:
			hi = mid - 1
	return lo + 1


## Total EXP needed to reach `level`.
static func exp_for(level: int) -> int:
	return EXP_TABLE[clampi(level, 1, MAX_LEVEL) - 1]


## 0..1 progress from this level to the next (1 at the cap).
static func progress(experience: int) -> float:
	var level := level_for(experience)
	if level >= MAX_LEVEL:
		return 1.0
	var from := exp_for(level)
	return float(experience - from) / float(exp_for(level + 1) - from)


## EXP still needed for the next level (0 at the cap).
static func to_next(experience: int) -> int:
	var level := level_for(experience)
	return 0 if level >= MAX_LEVEL else exp_for(level + 1) - experience


# --- Stat growth ---------------------------------------------------------------------

static func curve_at(curve: StringName, level: int) -> float:
	var points: Array = CURVES[curve]
	level = clampi(level, 1, MAX_LEVEL)
	for i in range(1, CURVE_LEVELS.size()):
		if level <= CURVE_LEVELS[i]:
			var a := CURVE_LEVELS[i - 1]
			var t := float(level - a) / float(CURVE_LEVELS[i] - a)
			return lerpf(points[i - 1], points[i], t)
	return 1.0


## Everything gained from level 1 up to `level`: stat -> whole points.
static func gains(race: CharacterData.Race, job: CharacterData.Job, level: int) -> Dictionary:
	var job_table: Dictionary = JOB_GROWTH.get(job, {})
	var race_table: Dictionary = RACE_GROWTH.get(race, {})
	var out := {}
	for stat in STATS:
		var full := float(job_table.get(stat, 0)) * float(race_table.get(stat, 1.0))
		out[stat] = float(roundi(full * curve_at(STAT_CURVE.get(stat, &"early"), level)))
	return out


## The level bonus for a character (applied with materials and armor).
static func bonuses(c: CharacterData) -> Dictionary:
	return gains(c.race, c.job, c.level())


## What going from one level to another adds: stat -> points (only stats
## that changed).
static func level_up_gains(c: CharacterData, from_level: int, to_level: int) -> Dictionary:
	var before := gains(c.race, c.job, from_level)
	var after := gains(c.race, c.job, to_level)
	var out := {}
	for stat in STATS:
		var d := float(after[stat]) - float(before[stat])
		if d != 0.0:
			out[stat] = d
	return out


## "HP +12  LP +6  STR +7 ..." in table order.
static func gains_text(g: Dictionary) -> String:
	var parts := PackedStringArray()
	for stat in STATS:
		if g.has(stat):
			parts.append("%s +%d" % [STAT_LABELS[stat], roundi(float(g[stat]))])
	return "  ".join(parts)
