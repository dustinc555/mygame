extends VBoxContainer

const OVERLAY = preload("res://features/combat/projection/combat_debug_overlay.gd")
var _settings = preload("res://features/combat/resources/combat_pursuit_settings.tres")

func _ready() -> void:
	name = "CombatDebug"
	add_theme_constant_override("separation", 8)
	var overlay := OVERLAY.new()
	overlay.name = "CombatLeashes"
	add_child(overlay)
	var check := CheckButton.new()
	check.name = "ShowPursuitLeashes"
	check.text = "Show pursuit leashes"
	check.toggled.connect(overlay.set_enabled)
	add_child(check)
	var caption := Label.new()
	caption.text = "NPC pursuit leash (meters)"
	add_child(caption)
	var distance := SpinBox.new()
	distance.name = "PursuitLeashDistance"
	distance.min_value = 1.0
	distance.max_value = 500.0
	distance.step = 1.0
	distance.suffix = "m"
	distance.value = _settings.leash_distance
	distance.value_changed.connect(func(value: float) -> void:
		_settings.leash_distance = value
		overlay.refresh()
	)
	add_child(distance)
	var help := Label.new()
	help.text = "Cyan: fighter to current opponent.\nGold: pursuit boundary around the fighter.\nShows up to 32 nearby fighters; off by default.\n\nLeash is not the enemy detection radius.\nDefend and explicit player orders stay unchanged.\nChanges apply on the next target check (runtime only).\nSaved default: combat_pursuit_settings.tres"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 300.0
	add_child(help)
