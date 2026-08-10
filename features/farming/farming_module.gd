extends RefCounted

const FARM_CONTROLLER := preload("res://features/farming/sim/farm_controller.gd")
const FARM_PLACEMENT := preload("res://features/farming/bridge/farm_placement_bridge.gd")
const FARM_WORK := preload("res://features/farming/bridge/farm_work_bridge.gd")
const FARM_PROJECTION := preload("res://features/farming/bridge/farm_projection_bridge.gd")
const FARM_OBSTRUCTIONS := preload("res://features/farming/bridge/farm_obstruction_bridge.gd")

const CORE := []
const PROJECTION := []
const SIM := [
	{"name": "FarmController", "script": FARM_CONTROLLER, "service": FARM_CONTROLLER.SERVICE_ID},
]
const BRIDGE := [
	{"name": "FarmPlacementBridge", "script": FARM_PLACEMENT, "service": FARM_PLACEMENT.SERVICE_ID},
	{"name": "FarmWorkBridge", "script": FARM_WORK, "service": FARM_WORK.SERVICE_ID},
	{"name": "FarmProjectionBridge", "script": FARM_PROJECTION, "service": FARM_PROJECTION.SERVICE_ID},
	{"name": "FarmObstructionBridge", "script": FARM_OBSTRUCTIONS, "service": FARM_OBSTRUCTIONS.SERVICE_ID},
]
