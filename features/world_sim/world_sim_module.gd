extends RefCounted

## World simulation feature module.
##
## Sim: the durable world-simulation systems that advance far/off-camera state --
## the simulation aggregate, population, territory, roads, world events,
## squads, encounters, and the O(1) ledger (faction identity/diplomacy lives
## in features/factions). Bridge: the world status surface and
## the realization controller that decides which records become live bodies.
##
## A module is pure declaration: const arrays of {name, script, service} specs,
## one per layer. GameBootstrap installs SIM into WorldSimRoot and BRIDGE into
## BridgeRoot, registers each as a service, then injects the context.

const WORLD_SIMULATION := preload("res://features/world_sim/sim/world_simulation_controller.gd")
const POPULATION := preload("res://features/world_sim/sim/population/population_controller.gd")
const TERRITORY := preload("res://features/world_sim/sim/territory_controller.gd")
const ROAD := preload("res://features/world_sim/sim/roads/road_controller.gd")
const WORLD_EVENT_CHOICE := preload("res://features/world_sim/sim/world_event_choice_controller.gd")
const WORLD_SIM_SQUAD := preload("res://features/world_sim/sim/world_sim_squad_controller.gd")
const FACTION_WORLD_SIM := preload("res://features/world_sim/sim/faction_world_sim_controller.gd")
const ENCOUNTER := preload("res://features/world_sim/sim/encounter_controller.gd")
const LEDGER_SIMULATION := preload("res://features/world_sim/sim/ledger_simulation_controller.gd")
const WORLD_STATUS := preload("res://features/world_sim/bridge/world_status_controller.gd")
const POPULATION_REALIZATION := preload("res://features/world_sim/bridge/population_realization_controller.gd")

const CORE := []
const PROJECTION := []
# WorldSimulationController is installed first: the other sim systems resolve the
# simulation aggregate / GECS state during initialize().
const SIM := [
	{"name": "WorldSimulationController", "script": WORLD_SIMULATION, "service": WORLD_SIMULATION.SERVICE_ID},
	{"name": "PopulationController", "script": POPULATION, "service": POPULATION.SERVICE_ID},
	{"name": "TerritoryController", "script": TERRITORY, "service": TERRITORY.SERVICE_ID},
	{"name": "RoadController", "script": ROAD, "service": ROAD.SERVICE_ID},
	{"name": "WorldEventChoiceController", "script": WORLD_EVENT_CHOICE, "service": WORLD_EVENT_CHOICE.SERVICE_ID},
	{"name": "WorldSimSquadController", "script": WORLD_SIM_SQUAD, "service": WORLD_SIM_SQUAD.SERVICE_ID},
	{"name": "FactionWorldSimController", "script": FACTION_WORLD_SIM, "service": FACTION_WORLD_SIM.SERVICE_ID},
	{"name": "EncounterController", "script": ENCOUNTER, "service": ENCOUNTER.SERVICE_ID},
	{"name": "LedgerSimulationController", "script": LEDGER_SIMULATION, "service": LEDGER_SIMULATION.SERVICE_ID},
]
const BRIDGE := [
	{"name": "WorldStatusController", "script": WORLD_STATUS, "service": WORLD_STATUS.SERVICE_ID},
	{"name": "PopulationRealizationController", "script": POPULATION_REALIZATION, "service": POPULATION_REALIZATION.SERVICE_ID},
]
