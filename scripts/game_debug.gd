extends Node

class_name GameDebugSettings

## Global game-level debug switch for dev-only UI and visualization.
## Set this false for non-dev builds.
@export var debug := true


func is_debug_enabled() -> bool:
	return debug
