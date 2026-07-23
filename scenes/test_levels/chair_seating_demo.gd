extends Node3D

const SETTLER_REALIZER := preload("res://features/world_sim/resources/population_appearance_profiles/settler_common.tres")
const PAIRS := [
	["Chair1", "Actors/Chair1Actor"],
	["Chair3", "Actors/Chair3Actor"],
	["Stool", "Actors/StoolActor"],
	["Throne", "Actors/ThroneActor"],
]

@onready var camera: Camera3D = $Camera3D
var _seat_delay := 1.0


func _enter_tree() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 81423
	for pair in PAIRS:
		var actor := get_node_or_null(pair[1])
		if actor != null:
			SETTLER_REALIZER.apply_to_actor(actor, rng, true)


func _ready() -> void:
	camera.look_at(Vector3(0.0, 0.85, 0.0), Vector3.UP)


func _process(delta: float) -> void:
	_seat_delay -= delta
	if _seat_delay > 0.0:
		return
	set_process(false)
	for pair in PAIRS:
		var seat := get_node_or_null("Chairs/%s" % pair[0])
		var actor := get_node_or_null(pair[1]) as HumanoidCharacter
		var interaction = actor.get_interaction() if actor != null else null
		if seat == null or interaction == null or not interaction.sit_at_seat_immediately(seat):
			push_error("Failed to seat %s" % pair[1])
