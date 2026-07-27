extends RefCounted

## Settlements feature module.
##
## Sim: durable settlement systems -- law/order, item ownership, the job
## system that assigns labor, and runtime construction records (placed
## buildings founding faction settlements). Bridge: the settlement controller
## that maps durable state onto live town content, and the construction
## realizer that turns construction records into placed building scenes and
## town borders.
##
## Installed by GameBootstrap into WorldSimRoot (sim) and BridgeRoot (bridge).

const LAW_ORDER := preload("res://features/settlements/sim/law/law_order_controller.gd")
const CRIME_ALERT := preload("res://features/settlements/sim/law/crime_alert_controller.gd")
const OWNERSHIP := preload("res://features/settlements/sim/ownership_controller.gd")
const JOB_SYSTEM := preload("res://features/settlements/sim/job_system_controller.gd")
const CONSTRUCTION := preload("res://features/settlements/sim/construction_controller.gd")
const CENSUS := preload("res://features/settlements/sim/settlement_census.gd")
const FOOD := preload("res://features/settlements/sim/settlement_food_controller.gd")
const TOWN_LEDGER := preload("res://features/settlements/bridge/town_ledger_controller.gd")
const ITEM_READ := preload("res://features/settlements/bridge/item_read_controller.gd")
const LEDGER_UI := preload("res://features/settlements/bridge/town_ledger_ui_bridge.gd")
const SETTLEMENT := preload("res://features/settlements/bridge/settlement_controller.gd")
const CONSTRUCTION_REALIZER := preload("res://features/settlements/bridge/construction_realizer.gd")
const POPULATION_CHARACTER_REALIZER := preload("res://features/settlements/bridge/population_character_realizer.gd")

const CORE := []
const PROJECTION := []
const SIM := [
	{"name": "CrimeAlertController", "script": CRIME_ALERT, "service": CRIME_ALERT.SERVICE_ID},
	{"name": "LawOrderController", "script": LAW_ORDER, "service": LAW_ORDER.SERVICE_ID},
	{"name": "OwnershipController", "script": OWNERSHIP, "service": OWNERSHIP.SERVICE_ID},
	{"name": "JobSystemController", "script": JOB_SYSTEM, "service": JOB_SYSTEM.SERVICE_ID},
	{"name": "ConstructionController", "script": CONSTRUCTION, "service": CONSTRUCTION.SERVICE_ID},
	{"name": "SettlementCensus", "script": CENSUS, "service": CENSUS.SERVICE_ID},
	{"name": "SettlementFoodController", "script": FOOD, "service": FOOD.SERVICE_ID},
]
const BRIDGE := [
	{"name": "SettlementController", "script": SETTLEMENT, "service": SETTLEMENT.SERVICE_ID},
	{"name": "PopulationCharacterRealizer", "script": POPULATION_CHARACTER_REALIZER, "service": POPULATION_CHARACTER_REALIZER.SERVICE_ID},
	{"name": "ConstructionRealizer", "script": CONSTRUCTION_REALIZER, "service": CONSTRUCTION_REALIZER.SERVICE_ID},
	{"name": "TownLedgerReadModel", "script": TOWN_LEDGER, "service": TOWN_LEDGER.SERVICE_ID},
	{"name": "ItemReadBridge", "script": ITEM_READ, "service": ITEM_READ.SERVICE_ID},
	{"name": "TownLedgerUiBridge", "script": LEDGER_UI, "service": LEDGER_UI.SERVICE_ID},
]
