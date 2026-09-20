extends "res://features/actors/bridge/capabilities/actor_capability.gd"

var setup_calls := 0
var ready_calls := 0
var process_calls := 0
var physics_process_calls := 0
var teardown_calls := 0
var setup_actor: Node
var process_delta := 0.0
var physics_delta := 0.0


func _init() -> void:
	super._init(&"test")
	process_enabled = true
	physics_process_enabled = true


func setup(target_actor: Node) -> void:
	super.setup(target_actor)
	setup_calls += 1
	setup_actor = target_actor


func ready() -> void:
	ready_calls += 1


func process(delta: float) -> void:
	process_calls += 1
	process_delta += delta


func physics_process(delta: float) -> void:
	physics_process_calls += 1
	physics_delta += delta


func teardown() -> void:
	teardown_calls += 1
	super.teardown()
