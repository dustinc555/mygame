extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not ResourceLoader.exists("res://tools/outfitter/outfitter.tscn"):
		push_error("Outfitter scene must exist and realize every canonical race/body")
		quit(1)
		return
	var cases = load("res://tools/outfitter/outfitter_cases.gd").new()
	await cases.run(self)
