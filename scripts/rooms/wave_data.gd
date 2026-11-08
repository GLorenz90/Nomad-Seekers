class_name WaveData
extends Resource
## One wave of a WaveRoom: the enemies that spawn together. Each enemy takes
## the next spawn point in order (wrapping around).

@export var enemies: Array[EnemyData] = []
