class_name Defense
extends RefCounted
## Defense math shared by the Seeker and enemies (North Star §3 stats).
##
## DEF reduces melee and ranged damage, RES reduces magic damage. EVA only
## decides whether attacks land (Accuracy, Part 6).
## Reduction is 100 / (100 + stat): 20 = 17% less, 50 = 33% less, 100 = half.

static func scale_for(kind: DamageInfo.Kind, def: float, res: float, _eva: float = 0.0) -> float:
	var stat := def
	match kind:
		DamageInfo.Kind.MAGIC:
			stat = res
	return 100.0 / (100.0 + maxf(stat, 0.0))
