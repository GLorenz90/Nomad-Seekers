class_name Defense
extends RefCounted
## Defense math shared by the Seeker and enemies (North Star §3 stats).
##
## DEF reduces melee damage, RES reduces magic damage, EVA reduces ranged damage
## and also gives every non-magic attack a small chance to miss outright.
## Reduction is 100 / (100 + stat): 20 = 17% less, 50 = 33% less, 100 = half.

## Miss chance per point of EVA (20 EVA = 5%), capped.
const MISS_PER_EVA := 0.0025
const MAX_MISS := 0.35


static func scale_for(kind: DamageInfo.Kind, def: float, res: float, eva: float) -> float:
	var stat := def
	match kind:
		DamageInfo.Kind.MAGIC:
			stat = res
		DamageInfo.Kind.RANGED:
			stat = eva
	return 100.0 / (100.0 + maxf(stat, 0.0))


static func miss_chance(kind: DamageInfo.Kind, eva: float) -> float:
	if kind == DamageInfo.Kind.MAGIC:
		return 0.0  # spells always land
	return clampf(eva * MISS_PER_EVA, 0.0, MAX_MISS)
