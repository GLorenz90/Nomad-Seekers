class_name WaveData
extends Resource
## One wave of a WaveRoom: the enemies that spawn together. Each enemy takes
## the next spawn point in order (wrapping around).
##
## Level editor waves (Part 13a) use `placements` instead: one dictionary per
## enemy from combat.json (enemy id, position, yaw, spawn delay, wander and
## chase leashes; see Enemy.configure and docs/level_format.md).

@export var enemies: Array[EnemyData] = []
@export var placements: Array[Dictionary] = []


func size() -> int:
	return placements.size() if not placements.is_empty() else enemies.size()
