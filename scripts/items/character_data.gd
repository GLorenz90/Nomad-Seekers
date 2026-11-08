class_name CharacterData
extends Resource
## The Seeker's identity (North Star §2.5, §3). Race, gender and name decide
## the emblem, which decides the drop pool (North Star §7.2, PSO section IDs).
## Placeholder until character creation exists; edit it in the loadout menu.

enum Race { HUMAN, GOLUMAN, LUMERA, CORESIAN }
enum Gender { MALE, FEMALE }
enum Job { STRIKER, RANGER, INVOKER }

## Ten emblem colors (originals, not PSO's section ID names).
const EMBLEMS := ["Crimson", "Amber", "Gold", "Verdant", "Teal",
	"Azure", "Indigo", "Violet", "Rose", "Ivory"]
const EMBLEM_COLORS := [Color(0.85, 0.2, 0.2), Color(1.0, 0.6, 0.15), Color(1.0, 0.85, 0.2),
	Color(0.35, 0.8, 0.3), Color(0.2, 0.75, 0.7), Color(0.25, 0.55, 1.0), Color(0.35, 0.3, 0.85),
	Color(0.65, 0.35, 0.9), Color(1.0, 0.5, 0.7), Color(0.95, 0.93, 0.85)]
const JOB_CODES := ["S", "R", "I"]

@export var seeker_name := "Seeker"
@export var race: Race = Race.HUMAN
@export var gender: Gender = Gender.MALE
@export var job: Job = Job.STRIKER
@export var experience := 0


## PSO-style: the name's character codes plus race and gender, mod 10.
func emblem_index() -> int:
	var total := int(race) * 3 + int(gender) * 7
	for i in seeker_name.length():
		total += seeker_name.unicode_at(i)
	return total % EMBLEMS.size()


func emblem_name() -> String:
	return EMBLEMS[emblem_index()]


func emblem_color() -> Color:
	return EMBLEM_COLORS[emblem_index()]


func job_code() -> String:
	return JOB_CODES[job]


func job_name() -> String:
	return Job.keys()[job].capitalize()


func race_name() -> String:
	return Race.keys()[race].capitalize()
