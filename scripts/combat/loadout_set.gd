class_name LoadoutSet
extends Resource
## The Seeker's saved loadouts plus the options that affect them. Saved to
## user://loadouts.tres when the loadout menu closes.

const SLOT_COUNT := 8
const SAVE_PATH := "user://loadouts.tres"

@export var loadouts: Array[Loadout] = []
## Placeholder for the armor augment (North Star §5.1). Armor arrives later;
## for now the loadout menu toggles it.
@export var double_heavy_augment := false
## No longer used: powerstanced pairs always twin-attack now. Kept so loadouts
## saved by the first Part 3 build still load.
@export var powerstance_default := false


func ensure_slots() -> void:
	while loadouts.size() < SLOT_COUNT:
		loadouts.append(Loadout.new())


func save() -> void:
	ResourceSaver.save(self, SAVE_PATH)


static func load_or_default(defaults: LoadoutSet) -> LoadoutSet:
	if ResourceLoader.exists(SAVE_PATH):
		var saved := ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as LoadoutSet
		if saved:
			saved.ensure_slots()
			return saved
	defaults.ensure_slots()
	return defaults
