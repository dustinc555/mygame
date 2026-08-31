extends "res://addons/gecs/ecs/system.gd"

class_name GameDoorSystem

const C_DOOR_COMMAND := preload("res://features/doors/sim/c_game_door_command.gd")
const FIXED_DOOR_TICK_SECONDS := 1.0 / 20.0
const MAX_FIXED_STEPS_PER_FRAME := 8

var controller: Node
var _fixed_accumulator := 0.0


func query() -> QueryBuilder:
	return q.with_all([C_DOOR_COMMAND]).iterate([C_DOOR_COMMAND])


func process(entities: Array, components: Array, delta: float) -> void:
	# Resolving a command removes its entity from the archetype immediately.
	# Snapshot the live component column alongside System's entity snapshot so
	# concurrent completions cannot shift indices underneath this fixed-step loop.
	var commands: Array = (components[0] as Array).duplicate()
	if commands.is_empty() or controller == null:
		return
	var command_count := mini(entities.size(), commands.size())
	_fixed_accumulator = minf(_fixed_accumulator + maxf(delta, 0.0), FIXED_DOOR_TICK_SECONDS * float(MAX_FIXED_STEPS_PER_FRAME))
	var steps := 0
	while _fixed_accumulator >= FIXED_DOOR_TICK_SECONDS and steps < MAX_FIXED_STEPS_PER_FRAME:
		for index in range(command_count):
			var entity = entities[index]
			if entity == null or not is_instance_valid(entity):
				continue
			var command = commands[index]
			if command != null:
				_tick_command(entity, command, FIXED_DOOR_TICK_SECONDS)
		_fixed_accumulator -= FIXED_DOOR_TICK_SECONDS
		steps += 1


func _tick_command(entity, command, delta: float) -> void:
	if command.phase != command.Phase.PERFORMING:
		return
	command.remaining_seconds = maxf(0.0, command.remaining_seconds - delta)
	if command.remaining_seconds > 0.0:
		return
	controller.resolve_performing_command(entity, command)
