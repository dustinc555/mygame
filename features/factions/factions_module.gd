extends RefCounted

## Factions feature module.
##
## Sim: FactionController — the runtime authority for faction identity,
## diplomacy, reputation, favor, and outlooks. Faction definitions are
## authored as FactionDefinition resources under
## features/factions/resources/factions and registered at boot through the
## Factions authoring node in the world scene (plus zone/settlement
## definitions that carry their own faction references).

const FACTION := preload("res://features/factions/sim/faction_controller.gd")

const CORE := []
const PROJECTION := []
const SIM := [
	{"name": "FactionController", "script": FACTION, "service": FACTION.SERVICE_ID},
]
const BRIDGE := []
