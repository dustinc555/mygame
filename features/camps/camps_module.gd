extends RefCounted

const CAMPS := preload("res://features/camps/sim/camp_controller.gd")
const REALIZATION := preload("res://features/camps/bridge/camp_realization_controller.gd")
const CORE := []
const PROJECTION := []
const SIM := [{"name": "CampController", "script": CAMPS, "service": CAMPS.SERVICE_ID}]
const BRIDGE := [{"name": "CampRealizationController", "script": REALIZATION, "service": REALIZATION.SERVICE_ID}]
