extends RefCounted

## UI feature module.
##
## Bridge: the humanoid details controller that maps a selected actor's live state
## onto its inspector panel on the HUD.
##
## Installed by GameBootstrap into BridgeRoot.

const HUMANOID_DETAILS := preload("res://features/ui/bridge/humanoid_details_controller.gd")

const CORE := []
const PROJECTION := []
const SIM := []
const BRIDGE := [
	{"name": "HumanoidDetailsController", "script": HUMANOID_DETAILS, "service": HUMANOID_DETAILS.SERVICE_ID},
]
