extends RefCounted

## Actors feature module.
##
## Projection: the appearance pipeline that builds character visuals on live
## bodies. Bridge: perception, the live-actor sense layer other systems read.
##
## A module is pure declaration: const arrays of {name, script, service} specs,
## one per layer. GameBootstrap installs PROJECTION into ProjectionRoot and
## BRIDGE into BridgeRoot, registers each as a service, then injects the context.

const CHARACTER_APPEARANCE := preload("res://features/actors/projection/appearance/character_appearance_controller.gd")
const PERCEPTION := preload("res://features/actors/bridge/perception/perception_controller.gd")
const DEBUG_CHARACTER_CREATION := preload("res://features/actors/bridge/debug_character_creation_controller.gd")

const CORE := []
const PROJECTION := [
	{"name": "CharacterAppearanceController", "script": CHARACTER_APPEARANCE, "service": CHARACTER_APPEARANCE.SERVICE_ID},
]
const SIM := []
const BRIDGE := [
	{"name": "PerceptionController", "script": PERCEPTION, "service": PERCEPTION.SERVICE_ID},
	{"name": "DebugCharacterCreationController", "script": DEBUG_CHARACTER_CREATION, "service": DEBUG_CHARACTER_CREATION.SERVICE_ID},
]
