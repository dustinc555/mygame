extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await load("res://tests/validation/puglin_runtime_projection_cases.gd").new().run(self)
