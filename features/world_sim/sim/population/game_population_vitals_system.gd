extends "res://addons/gecs/ecs/system.gd"

class_name GamePopulationVitalsSystem

signal life_state_changed(entity, previous_state: int, next_state: int)

const C_POPULATION = preload("res://features/world_sim/sim/population/c_game_population_record.gd")
const C_VITALS = preload("res://features/actors/sim/c_game_actor_vitals.gd")
const C_VITALS_INPUTS = preload("res://features/actors/sim/c_game_actor_vitals_inputs.gd")
const C_ACTIVE = preload("res://features/world_sim/sim/population/c_game_active_population_vitals.gd")
const FIXED_VITALS_TICK_SECONDS := 1.0 / 20.0
const MAX_FIXED_STEPS_PER_FRAME := 8

var _fixed_accumulator := 0.0


func _init() -> void:
	process_empty = true


func query() -> QueryBuilder:
	return q.with_all([C_POPULATION, C_VITALS, C_VITALS_INPUTS, C_ACTIVE]).iterate([C_POPULATION, C_VITALS, C_VITALS_INPUTS])


func process(entities: Array, components: Array, delta: float) -> void:
	if entities.is_empty():
		_fixed_accumulator = 0.0
		return
	var population: Array = components[0]
	var vitals: Array = components[1]
	var inputs: Array = components[2]
	var completed := {}
	_fixed_accumulator = minf(_fixed_accumulator + maxf(delta, 0.0), FIXED_VITALS_TICK_SECONDS * float(MAX_FIXED_STEPS_PER_FRAME))
	while _fixed_accumulator >= FIXED_VITALS_TICK_SECONDS:
		_fixed_accumulator -= FIXED_VITALS_TICK_SECONDS
		_process_fixed_step(entities, population, vitals, inputs, completed)
	for entity in completed:
		if is_instance_valid(entity):
			entity.remove_component(C_ACTIVE)


func _process_fixed_step(entities: Array, population: Array, vitals: Array, inputs: Array, completed: Dictionary) -> void:
	for index in range(entities.size()):
		var entity = entities[index]
		var person = population[index]
		var v = vitals[index]
		var inp = inputs[index]
		if person.realization_state == "realized":
			continue
		var previous_state: int = int(v.life_state)
		v.held_externally_hold = false
		VitalsStateMachine.tick(v, inp.toughness, inp.healing_rate, FIXED_VITALS_TICK_SECONDS)
		person.life_state = v.life_state
		if previous_state != v.life_state:
			life_state_changed.emit(entity, previous_state, v.life_state)
		if not v.needs_active_simulation():
			completed[entity] = true


func catch_up_seconds(duration_seconds: float) -> void:
	if duration_seconds <= 0.0:
		return
	var completed: Array = []
	for entity in query().execute():
		var person = entity.get_component(C_POPULATION)
		var v = entity.get_component(C_VITALS)
		var inp = entity.get_component(C_VITALS_INPUTS)
		if person == null or v == null or inp == null or person.realization_state == "realized":
			continue
		var previous_state: int = int(v.life_state)
		v.held_externally_hold = false
		VitalsStateMachine.catch_up(v, inp.toughness, inp.healing_rate, duration_seconds)
		person.life_state = v.life_state
		if previous_state != v.life_state:
			life_state_changed.emit(entity, previous_state, v.life_state)
		if not v.needs_active_simulation():
			completed.append(entity)
	for entity in completed:
		if is_instance_valid(entity):
			entity.remove_component(C_ACTIVE)
