extends RefCounted

## UI feature module.
##
## Projection: the navigation loading gate that pauses the game behind a
## LOADING veil until the first navmesh bake of the session is usable.
## Bridge: the humanoid details controller that maps a selected actor's live state
## onto its inspector panel on the HUD.
##
## Installed by GameBootstrap into ProjectionRoot and BridgeRoot.

const HUMANOID_DETAILS := preload("res://features/ui/bridge/humanoid_details_controller.gd")
const NAVIGATION_LOADING := preload("res://features/ui/projection/navigation_loading_overlay.gd")

const CORE := []
const PROJECTION := [
	{"name": "NavigationLoadingOverlay", "script": NAVIGATION_LOADING, "service": NAVIGATION_LOADING.SERVICE_ID},
]
const SIM := []
const BRIDGE := [
	{"name": "HumanoidDetailsController", "script": HUMANOID_DETAILS, "service": HUMANOID_DETAILS.SERVICE_ID},
]
