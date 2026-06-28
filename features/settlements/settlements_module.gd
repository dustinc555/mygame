extends RefCounted

## Settlements feature module.
##
## Sim: durable settlement systems -- law/order, item ownership, and the job
## system that assigns labor. Bridge: the settlement controller that maps that
## durable state onto live town content.
##
## Installed by GameBootstrap into WorldSimRoot (sim) and BridgeRoot (bridge).

const LAW_ORDER := preload("res://features/settlements/sim/law/law_order_controller.gd")
const OWNERSHIP := preload("res://features/settlements/sim/ownership_controller.gd")
const JOB_SYSTEM := preload("res://features/settlements/sim/job_system_controller.gd")
const SETTLEMENT := preload("res://features/settlements/bridge/settlement_controller.gd")

const CORE := []
const PROJECTION := []
const SIM := [
	{"name": "LawOrderController", "script": LAW_ORDER, "service": LAW_ORDER.SERVICE_ID},
	{"name": "OwnershipController", "script": OWNERSHIP, "service": OWNERSHIP.SERVICE_ID},
	{"name": "JobSystemController", "script": JOB_SYSTEM, "service": JOB_SYSTEM.SERVICE_ID},
]
const BRIDGE := [
	{"name": "SettlementController", "script": SETTLEMENT, "service": SETTLEMENT.SERVICE_ID},
]
