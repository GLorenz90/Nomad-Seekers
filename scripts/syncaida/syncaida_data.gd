class_name SyncAIDaData
extends Resource
## One SyncAIDa (North Star §7.1, PSO's MAGs). Feeding raises its four stats,
## DEF / STR / DEX / SOL, by experience: every XP_PER_LEVEL in a stat is one
## level of that stat, and the SyncAIDa's level is the sum (max 200). Each
## stat level adds STAT_BONUS to the paired Seeker's matching stat.
##
## Evolution (PSO-style formulas): at level 10 and again at 35 it takes a form
## from its strongest stat, and from 50 on (re-checked every 5 levels) from its
## two strongest stats. Level 100 adds "Prime". Forms depend only on the
## SyncAIDa's own stats, never its Seeker's job, so one character can raise a
## SyncAIDa for another (PSO's mag meta-progression).
##
## Starters: every Seeker picks one of four, each already level 5 in one stat.
## Each evolution milestone unlocks a Sync Burst (up to 3, one active).

const XP_PER_LEVEL := 100.0
const MAX_LEVEL := 200
## Seeker stat points per SyncAIDa stat level.
const STAT_BONUS := 2.0
const STATS: Array[StringName] = [&"def", &"str", &"dex", &"sol"]
const STAT_NAMES := {&"def": "DEF", &"str": "STR", &"dex": "DEX", &"sol": "SOL"}
const STAT_COLORS := {&"def": Color(0.55, 0.7, 0.95), &"str": Color(1.0, 0.4, 0.3),
	&"dex": Color(0.45, 0.95, 0.5), &"sol": Color(0.75, 0.5, 1.0)}

## Milestones: level -> evolution stage.
const MILESTONES := [10, 35, 50]
## Level 10 form by strongest stat.
const FIRST_FORMS := {&"def": "Shell", &"str": "Ember", &"dex": "Flit", &"sol": "Glimmer"}
## Level 35 form by strongest stat.
const STAT_FORMS := {&"def": "Bastion", &"str": "Talon", &"dex": "Kestrel", &"sol": "Wisp"}
## Two strongest stats (sorted by STATS order) -> form.
const PAIR_FORMS := {
	"def+str": "Bulwark", "def+dex": "Sentinel", "def+sol": "Oracle",
	"str+dex": "Falcon", "str+sol": "Pyre", "dex+sol": "Zephyr",
}

enum Burst { LUMEN_NOVA, AEGIS_PULSE, MENDING_BLOOM }
const BURST_NAMES := ["Lumen Nova", "Aegis Pulse", "Mending Bloom"]
const BURST_TEXT := [
	"Light blast: damages every enemy within 8 m",
	"Party buff for 15 s: +30% damage dealt, -30% damage taken",
	"Party heal: 50% HP, 30 LP, and clears statuses",
]
## Burst unlocked by each evolution stage (1, 2, 3).
const STAGE_BURSTS := [Burst.LUMEN_NOVA, Burst.AEGIS_PULSE, Burst.MENDING_BLOOM]

## The four starters: [name, stat], each starting at STARTER_LEVEL in its stat.
const STARTERS := [["Aegi", &"def"], ["Kindle", &"str"], ["Swift", &"dex"], ["Lumi", &"sol"]]
const STARTER_LEVEL := 5

## What feeding each item does (stat XP; negatives as in PSO's mag feeding).
## Consumables come from the inventory, Lumidium from the bank.
const FEEDS := {
	&"hp_gel": {&"def": 40.0, &"sol": 10.0, &"dex": -10.0},
	&"lp_cell": {&"sol": 40.0, &"dex": 10.0, &"str": -10.0},
	&"cure_salt": {&"dex": 30.0, &"def": 20.0, &"sol": -10.0},
	&"fire": {&"str": 60.0, &"def": -15.0},
	&"lightning": {&"str": 40.0, &"dex": 30.0, &"sol": -15.0},
	&"ice": {&"dex": 60.0, &"str": -15.0},
	&"nature": {&"sol": 40.0, &"def": 30.0, &"dex": -15.0},
	&"light": {&"sol": 60.0, &"str": -15.0},
	&"dark": {&"str": 30.0, &"sol": 30.0, &"def": -15.0},
	&"raw": {&"def": 30.0, &"str": 30.0, &"dex": 30.0, &"sol": 30.0},
}

@export var display_name := "SyncAIDa"
@export var form := "Mote"
@export var stage := 0
@export var stat_xp := {&"def": 0.0, &"str": 0.0, &"dex": 0.0, &"sol": 0.0}
## Sync Bursts unlocked so far (Burst values), in unlock order. Max 3.
@export var bursts: Array[int] = []
@export var active_burst := 0
## Sympathetic energy, 0..100. Kept per SyncAIDa, like PSO's photon blast gauge.
@export var gauge := 0.0
## Form at the last check from level 50 on (re-checked every 5 levels).
@export var last_form_level := 0


static func create(name: String) -> SyncAIDaData:
	var s := SyncAIDaData.new()
	s.display_name = name
	s.stat_xp = {&"def": 0.0, &"str": 0.0, &"dex": 0.0, &"sol": 0.0}
	return s


## Starter index 0-3 (STARTERS): level 5 in its stat.
static func starter(index: int) -> SyncAIDaData:
	var spec: Array = STARTERS[clampi(index, 0, STARTERS.size() - 1)]
	var s := create(spec[0])
	s.stat_xp[spec[1]] = STARTER_LEVEL * XP_PER_LEVEL
	return s


static func starter_text(index: int) -> String:
	var spec: Array = STARTERS[index]
	return "%s  (%s Lv %d: +%d %s)" % [spec[0], STAT_NAMES[spec[1]], STARTER_LEVEL,
		roundi(STARTER_LEVEL * STAT_BONUS), STAT_NAMES[spec[1]]]


func stat_level(stat: StringName) -> int:
	return floori(float(stat_xp.get(stat, 0.0)) / XP_PER_LEVEL)


func level() -> int:
	var total := 0
	for stat in STATS:
		total += stat_level(stat)
	return mini(total, MAX_LEVEL)


## Seeker stat bonus: {&"def": points, ...}.
func bonuses() -> Dictionary:
	var out := {}
	for stat in STATS:
		out[stat] = stat_level(stat) * STAT_BONUS
	return out


func dominant_stat() -> StringName:
	var best: StringName = &"def"
	for stat in STATS:
		if float(stat_xp[stat]) > float(stat_xp[best]):
			best = stat
	return best


func top_two() -> String:
	var sorted := STATS.duplicate()
	sorted.sort_custom(func(a: StringName, b: StringName) -> bool:
		return float(stat_xp[a]) > float(stat_xp[b]))
	var pair := [sorted[0], sorted[1]]
	pair.sort_custom(func(a: StringName, b: StringName) -> bool: return STATS.find(a) < STATS.find(b))
	return "%s+%s" % pair


func color() -> Color:
	if level() == 0:
		return Color(0.85, 0.95, 1.0)
	return STAT_COLORS[dominant_stat()]


static func can_eat(item: StringName) -> bool:
	return FEEDS.has(item)


## Feeds one item. Returns the list of events: "level", "evolved", "burst".
func feed(item: StringName) -> Array[String]:
	var events: Array[String] = []
	if not FEEDS.has(item):
		return events
	var before := level()
	var effect: Dictionary = FEEDS[item]
	for stat in effect:
		var gain := float(effect[stat])
		if gain > 0.0 and level() >= MAX_LEVEL:
			continue
		stat_xp[stat] = maxf(float(stat_xp[stat]) + gain, 0.0)
	var after := level()
	if after != before:
		events.append("level")
	if _evolve(after):
		events.append("evolved")
	while bursts.size() < mini(stage, 3):
		bursts.append(STAGE_BURSTS[bursts.size()])
		events.append("burst")
	return events


## PSO-style evolution checks. Returns true if the form changed.
func _evolve(lv: int) -> bool:
	var old_form := form
	while stage < MILESTONES.size() and lv >= MILESTONES[stage]:
		stage += 1
		match stage:
			1:
				form = FIRST_FORMS[dominant_stat()]
			2:
				form = STAT_FORMS[dominant_stat()]
			3:
				form = PAIR_FORMS[top_two()]
				last_form_level = lv
	if stage >= 3 and lv >= last_form_level + 5:
		form = PAIR_FORMS[top_two()]
		last_form_level = lv - lv % 5
	if lv >= 100 and not form.ends_with(" Prime"):
		form += " Prime"
	return form != old_form


func burst_name(index: int = -1) -> String:
	if bursts.is_empty():
		return "none"
	var b := bursts[clampi(active_burst if index < 0 else index, 0, bursts.size() - 1)]
	return BURST_NAMES[b]


func active() -> int:
	if bursts.is_empty():
		return -1
	return bursts[clampi(active_burst, 0, bursts.size() - 1)]


func next_milestone() -> int:
	if stage < MILESTONES.size():
		return MILESTONES[stage]
	return -1


func describe_stats() -> String:
	var parts := PackedStringArray()
	for stat in STATS:
		parts.append("%s %d" % [STAT_NAMES[stat], stat_level(stat)])
	return "   ".join(parts)
