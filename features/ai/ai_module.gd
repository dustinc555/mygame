extends RefCounted

## AI feature module.
##
## Bridge: the decision-cadence scheduler that controls how often actors think.
## It does not tick every actor every frame -- it gates AI work against GECS state.
##
## Installed by GameBootstrap into BridgeRoot.

const AI_SCHEDULER := preload("res://features/ai/bridge/ai_scheduler_controller.gd")

const CORE := []
const PROJECTION := []
const SIM := []
const BRIDGE := [
	{"name": "AiSchedulerController", "script": AI_SCHEDULER, "service": AI_SCHEDULER.SERVICE_ID},
]
