extends RefCounted

## Discovery is durable GECS state; atlas is a disposable rendering cache.
const EXPLORATION := preload("res://features/world_map/bridge/map_exploration_controller.gd")
const ATLAS := preload("res://features/world_map/bridge/world_atlas_controller.gd")
const CORE := []
const PROJECTION := []
const SIM := []
const BRIDGE := [
	{"name": "MapExplorationController", "script": EXPLORATION, "service": EXPLORATION.SERVICE_ID},
	{"name": "WorldAtlasController", "script": ATLAS, "service": ATLAS.SERVICE_ID},
]
