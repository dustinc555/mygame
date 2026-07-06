extends RefCounted

## Core services module.
##
## Engine-level controllers everything else depends on: the time authority, the
## GECS world, and broad actor lookup. Installed by GameBootstrap into
## BootstrapContext.core_services (level above the projection/sim/bridge layers).
##
## A module is pure declaration: const arrays of {name, script, service} specs,
## one array per layer. GameBootstrap reads these directly -- no instantiation,
## no directory scanning, no reflection.

const WORLD_TIME := preload("res://features/core/world_time_controller.gd")
const GECS_WORLD := preload("res://features/core/gecs_world_controller.gd")
const ACTOR_QUERY := preload("res://features/core/actor_query_controller.gd")
const WORLD_NAVIGATION := preload("res://features/core/navigation/world_navigation_controller.gd")

# GECS world is created first: actor lookup and any state-syncing controller
# resolves it during initialize().
const CORE := [
	{"name": "GecsWorldController", "script": GECS_WORLD, "service": GECS_WORLD.SERVICE_ID},
	{"name": "WorldTimeController", "script": WORLD_TIME, "service": WORLD_TIME.SERVICE_ID},
	{"name": "ActorQueryController", "script": ACTOR_QUERY, "service": ACTOR_QUERY.SERVICE_ID},
	{"name": "WorldNavigationController", "script": WORLD_NAVIGATION, "service": WORLD_NAVIGATION.SERVICE_ID},
]
const PROJECTION := []
const SIM := []
const BRIDGE := []
