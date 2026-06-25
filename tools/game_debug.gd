extends Node

class_name GameDebugSettings

## Global game-level debug switch for dev-only UI and visualization.
## Set this false for non-dev builds.
@export var debug := OS.is_debug_build()


func is_debug_enabled() -> bool:
	return debug
