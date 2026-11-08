class_name CharacterData
extends Resource
## The Seeker's identity (North Star §2.5, §3). Name, race, gender and job
## decide the emblem, which decides the drop pool (North Star §7.2, PSO section
## IDs). The job is chosen at character creation and can't be changed later
## (unlike PSU). Placeholder until character creation exists: edit it in the
## menu's Character tab (job only through the Levels tab's debug tool).

enum Race { HUMAN, GOLUMAN, LUMERA, CORESIAN }
enum Gender { MALE, FEMALE }
enum Job { STRIKER, RANGER, INVOKER }

## Twelve emblem colors (Grayson's list).
const EMBLEMS := ["Crimson", "Orange", "Gold", "Green", "Teal", "Cyan",
	"Blue", "Purple", "Magenta", "Pink", "White", "Black"]
const EMBLEM_COLORS := [Color(0.82, 0.12, 0.2), Color(1.0, 0.55, 0.1), Color(1.0, 0.82, 0.2),
	Color(0.3, 0.78, 0.3), Color(0.1, 0.6, 0.6), Color(0.3, 0.9, 1.0),
	Color(0.2, 0.4, 1.0), Color(0.55, 0.3, 0.9), Color(0.95, 0.2, 0.8), Color(1.0, 0.6, 0.78),
	Color(0.96, 0.96, 0.96), Color(0.18, 0.18, 0.22)]
const JOB_CODES := ["S", "R", "I"]

@export var seeker_name := "Seeker"
@export var race: Race = Race.HUMAN
@export var gender: Gender = Gender.MALE
@export var job: Job = Job.STRIKER
@export var experience := 0
## Learned spells and traps: id -> level (Part 6). Learned levels are kept even
## if SOL later drops (like PSO).
@export var spells: Dictionary = {}
## Materials used: id -> count (PSO materials, see Materials).
@export var materials: Dictionary = {}


## PSO-style: the name's character codes plus race, gender and job, mod 12.
func emblem_index() -> int:
	var total := int(race) * 3 + int(gender) * 7 + int(job) * 5
	for i in seeker_name.length():
		total += seeker_name.unicode_at(i)
	return total % EMBLEMS.size()


func emblem_name() -> String:
	return EMBLEMS[emblem_index()]


func emblem_color() -> Color:
	return EMBLEM_COLORS[emblem_index()]


## Readable text color for the emblem (Black would vanish on dark menus).
func emblem_text_color() -> Color:
	var c := emblem_color()
	return c.lightened(0.5) if c.get_luminance() > 0.25 else Color(0.62, 0.62, 0.7)


func job_code() -> String:
	return JOB_CODES[job]


func job_name() -> String:
	return Job.keys()[job].capitalize()


func race_name() -> String:
	return Race.keys()[race].capitalize()


# --- Magic (Part 6) ---------------------------------------------------------------

## Highest spell level this Seeker can learn (Grayson, 2026-11-08): 20, +5 for an
## Invoker, +5 for a Lumera, -5 for a Striker, -5 for a Coresian. Goluman can't
## use magic at all (0); their traps use the same cap from Goluman's base.
func spell_level_cap() -> int:
	var cap := 20
	match job:
		Job.INVOKER:
			cap += 5
		Job.STRIKER:
			cap -= 5
	match race:
		Race.LUMERA:
			cap += 5
		Race.CORESIAN:
			cap -= 5
	return cap


func can_use_magic() -> bool:
	return race != Race.GOLUMAN


func can_use_traps() -> bool:
	return race == Race.GOLUMAN


## Max level for one spell or trap: its own maximum and the Seeker's cap.
func level_cap_for(spell: SpellDef) -> int:
	if spell.is_trap() and not can_use_traps():
		return 0
	if not spell.is_trap() and not can_use_magic():
		return 0
	return mini(spell.max_level, spell_level_cap())


func spell_level(id: StringName) -> int:
	return int(spells.get(id, 0))


## "" when this level can be learned with the given stat (SOL, or DEX for traps).
func learn_error(spell: SpellDef, level: int, stat_value: float) -> String:
	if spell.is_trap() and not can_use_traps():
		return "Only Goluman can use traps."
	if not spell.is_trap() and not can_use_magic():
		return "Goluman can't use magic."
	if level > level_cap_for(spell):
		return "%s can reach level %d at most." % [seeker_name, level_cap_for(spell)]
	if stat_value < spell.requirement(level):
		return "Needs %d %s (you have %d)." % [spell.requirement(level), spell.requirement_stat(), roundi(stat_value)]
	if spell_level(spell.id) >= level:
		return "Already known at level %d." % spell_level(spell.id)
	return ""
