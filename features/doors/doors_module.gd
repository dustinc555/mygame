extends RefCounted

const DOOR_CONTROLLER := preload("res://features/doors/sim/door_controller.gd")
const DOOR_INTERACTION := preload("res://features/doors/bridge/door_interaction_controller.gd")

const CORE := []
const PROJECTION := []
const SIM := [
	{"name": "DoorController", "script": DOOR_CONTROLLER, "service": DOOR_CONTROLLER.SERVICE_ID},
]
const BRIDGE := [
	{"name": "DoorInteractionController", "script": DOOR_INTERACTION, "service": DOOR_INTERACTION.SERVICE_ID},
]
