extends RefCounted

## World feature module.
##
## Projection: camera-facing world presentation (building interior reveal, bleed
## decals, day/night sky + lighting). Bridge: the player's world interaction layer
## that maps input/commands onto live actors and world content.
##
## Installed by GameBootstrap into ProjectionRoot and BridgeRoot respectively.

const BUILDING_VISIBILITY := preload("res://features/world/projection/building_visibility_controller.gd")
const BLEED_SPLOTCH := preload("res://features/world/projection/bleed_splotch_controller.gd")
const DAY_NIGHT_LIGHTING := preload("res://features/world/projection/lighting/day_night_lighting_controller.gd")
const WORLD_INTERACTION := preload("res://features/world/bridge/world_interaction_controller.gd")

const CORE := []
const PROJECTION := [
	{"name": "BuildingVisibilityController", "script": BUILDING_VISIBILITY, "service": BUILDING_VISIBILITY.SERVICE_ID},
	{"name": "BleedSplotchController", "script": BLEED_SPLOTCH, "service": BLEED_SPLOTCH.SERVICE_ID},
	{"name": "DayNightLightingController", "script": DAY_NIGHT_LIGHTING, "service": DAY_NIGHT_LIGHTING.SERVICE_ID},
]
const SIM := []
const BRIDGE := [
	{"name": "WorldInteractionController", "script": WORLD_INTERACTION, "service": WORLD_INTERACTION.SERVICE_ID},
]
