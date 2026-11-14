class_name HubLevel
extends DataLevel
## Nomad-2 (scenes/hub.tscn, built by tools/build_hub.gd). The ship itself is
## hand-built; in a quest session the quest's Nomad-2 overlay is laid over it
## (Grayson 2026-11-13: quests place people around Nomad-2): its people,
## props, dialogue and wiring, from the quest folder's nomad2/ (a level
## folder in the usual format; its start, lighting and combat are ignored).
## In free play nothing is added.


func _ready() -> void:
	overlay = true
	map_id = Session.HUB_SCENE
	level_path = String(QuestSession.quest().get("nomad2", ""))
	super._ready()
