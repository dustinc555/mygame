extends "res://src/actors/bridge/world_actor.gd"

class_name RobotActor

const ROBOT_OIL = preload("res://resources/bleed_fluids/robot_oil.tres")

const CUT_TO_BLUNT_DAMAGE_MULTIPLIER := 0.5
const OIL_HIT_LOSS_PER_DAMAGE := 0.12
const OIL_HIT_SPLASH_MIN_DAMAGE := 0.05
const OIL_HIT_SPLASH_VISUAL_DAMAGE_FLOOR := 24.0
const OIL_LEAK_HULL_RATIO := 0.75
const OIL_LEAK_MIN_PER_SECOND := 0.03
const OIL_LEAK_MAX_PER_SECOND := 0.55
const OIL_LEAK_VISUAL_BLEED_MIN_RATE := 8.0
const OIL_LEAK_VISUAL_BLEED_MAX_RATE := 22.0

var _bleed_splotch_controller: Node
var _bleed_splotch_controller_lookup_cooldown := 0.0
var _bleed_drip_progress := 0.0
var _bleed_pool_progress := 0.0


func receive_attack(attacker: Node, blunt_damage: float, cut_damage: float, attack_id: String = "", hit_reaction_names: Array[String] = [], is_critical := false) -> String:
	var converted_blunt := maxf(blunt_damage, 0.0) + maxf(cut_damage, 0.0) * CUT_TO_BLUNT_DAMAGE_MULTIPLIER
	var combat_capability := get_actor_capability(&"combat") as CombatCapability
	return combat_capability.receive_attack(attacker, converted_blunt, 0.0, attack_id, hit_reaction_names, is_critical) if combat_capability != null else "ignored"


func transform_system_incoming_damage(_attacker: Node, blunt_damage: float, cut_damage: float) -> Dictionary:
	return {"blunt_damage": maxf(blunt_damage, 0.0) + maxf(cut_damage, 0.0) * CUT_TO_BLUNT_DAMAGE_MULTIPLIER, "cut_damage": 0.0}


func get_bleed_fluid() -> Resource:
	var race = get("character_race")
	if race != null and race.get("bleed_fluid") != null:
		return race.get("bleed_fluid") as Resource
	return ROBOT_OIL


func get_vital_fluid_label() -> String:
	var fluid := get_bleed_fluid()
	if fluid != null:
		var display_name := str(fluid.get("display_name")).strip_edges()
		if not display_name.is_empty():
			return display_name
	return super.get_vital_fluid_label()


func get_health_vital_label() -> String:
	return "Hull"


func get_vital_fluid_bar_color(fallback_color: Color) -> Color:
	var fluid := get_bleed_fluid()
	if fluid != null and bool(fluid.get("uses_custom_ui_color")):
		var color_value = fluid.get("ui_bar_color")
		if color_value is Color:
			return color_value
	return fallback_color


func get_vital_fluid_glow_color(fallback_color: Color) -> Color:
	var fluid := get_bleed_fluid()
	if fluid != null and bool(fluid.get("uses_custom_ui_color")):
		var color_value = fluid.get("ui_glow_color")
		if color_value is Color:
			return color_value
	return fallback_color


func get_vital_fluid_blink_strength() -> float:
	return clampf((_get_hull_damage_ratio() - (1.0 - OIL_LEAK_HULL_RATIO)) / OIL_LEAK_HULL_RATIO, 0.0, 1.0)


func get_vital_fluid_blink_speed() -> float:
	return lerpf(0.22, 0.62, get_vital_fluid_blink_strength())


func get_vital_fluid_blink_color(_fallback_color: Color) -> Color:
	return Color(0.72, 0.64, 0.24, 1.0)


func can_receive_bandage() -> bool:
	return false


func get_life_state_label() -> String:
	if life_state == NpcRules.LifeState.UNCONSCIOUS or life_state == NpcRules.LifeState.RECOVERY_COMA:
		return "Offline"
	return super.get_life_state_label()


func _recalculate_vitals() -> void:
	hp = max_hp - get_total_wound_damage()
	if life_state == NpcRules.LifeState.DEAD:
		return
	if hp <= get_death_point(max_hp):
		_enter_dead_state()
		return
	if blood <= 0.0 or hp <= 0.0:
		if life_state != NpcRules.LifeState.UNCONSCIOUS:
			_enter_unconscious_state()
		return
	var getting_up = get("_is_getting_up")
	if getting_up != null and bool(getting_up):
		return


func _process_recovery(delta: float) -> void:
	if life_state == NpcRules.LifeState.DEAD:
		return
	_bleed_splotch_controller_lookup_cooldown = maxf(0.0, _bleed_splotch_controller_lookup_cooldown - delta)
	var leak_rate := get_robot_oil_leak_rate()
	if leak_rate <= 0.0 or blood <= get_blood_death_point():
		return
	var oil_loss := leak_rate * delta
	_apply_blood_loss(oil_loss)
	_process_bleed_splotches(_get_robot_oil_leak_visual_bleed_rate(), oil_loss, delta)
	_recalculate_vitals()


func get_robot_oil_leak_rate() -> float:
	var leak_strength := get_vital_fluid_blink_strength()
	if leak_strength <= 0.0:
		return 0.0
	return lerpf(OIL_LEAK_MIN_PER_SECOND, OIL_LEAK_MAX_PER_SECOND, leak_strength)


func _get_robot_oil_leak_visual_bleed_rate() -> float:
	var leak_strength := get_vital_fluid_blink_strength()
	if leak_strength <= 0.0:
		return 0.0
	return lerpf(OIL_LEAK_VISUAL_BLEED_MIN_RATE, OIL_LEAK_VISUAL_BLEED_MAX_RATE, leak_strength)


func _on_resolved_damage(final_blunt: float, final_cut: float) -> void:
	var total_damage := maxf(0.0, final_blunt) + maxf(0.0, final_cut)
	if total_damage <= 0.0:
		return
	_apply_blood_loss(total_damage * OIL_HIT_LOSS_PER_DAMAGE)
	if total_damage >= OIL_HIT_SPLASH_MIN_DAMAGE:
		_spawn_bleed_hit_splotches(maxf(total_damage, OIL_HIT_SPLASH_VISUAL_DAMAGE_FLOOR))


func _add_bleeding_from_cut(_final_blunt: float, _final_cut: float) -> void:
	pass


func _apply_blood_loss(amount: float) -> void:
	if amount <= 0.0:
		return
	blood = maxf(blood - amount, get_blood_death_point() * NpcRules.BLOOD_LOSS_DEATH_FACTOR)


func _process_bleed_splotches(total_bleed_rate: float, blood_loss_amount: float, delta: float) -> void:
	if life_state == NpcRules.LifeState.DEAD or total_bleed_rate <= 0.0 or blood_loss_amount <= 0.0:
		return
	var blood_loss_per_second := total_bleed_rate * NpcRules.BLEED_TO_BLOOD_RATE
	var severity := clampf(blood_loss_per_second / 8.0, 0.0, 1.0)
	_bleed_drip_progress += delta * clampf(blood_loss_per_second / 2.5, 0.08, 2.2)
	var drip_count := 0
	while _bleed_drip_progress >= 1.0 and drip_count < 3:
		_spawn_bleed_drip_splotch(severity)
		_bleed_drip_progress -= 1.0
		drip_count += 1
	if life_state != NpcRules.LifeState.ALIVE:
		_bleed_pool_progress += delta * clampf(blood_loss_per_second / 4.0, 0.04, 1.25)
		var pool_count := 0
		while _bleed_pool_progress >= 1.0 and pool_count < 2:
			_spawn_bleed_pool_splotch(severity)
			_bleed_pool_progress -= 1.0
			pool_count += 1


func _spawn_bleed_hit_splotches(cut_damage: float) -> void:
	var controller := _get_bleed_splotch_controller()
	if controller != null and controller.has_method("spawn_hit_splash"):
		controller.call("spawn_hit_splash", self, get_bleed_fluid(), cut_damage)


func _spawn_bleed_drip_splotch(severity: float) -> void:
	var controller := _get_bleed_splotch_controller()
	if controller != null and controller.has_method("spawn_bleed_drip"):
		controller.call("spawn_bleed_drip", self, get_bleed_fluid(), severity)


func _spawn_bleed_pool_splotch(severity: float) -> void:
	var controller := _get_bleed_splotch_controller()
	if controller != null and controller.has_method("spawn_bleed_pool"):
		controller.call("spawn_bleed_pool", self, get_bleed_fluid(), severity)


func _get_bleed_splotch_controller() -> Node:
	if _bleed_splotch_controller != null and is_instance_valid(_bleed_splotch_controller):
		return _bleed_splotch_controller
	if _bleed_splotch_controller_lookup_cooldown > 0.0:
		return null
	var tree := get_tree()
	if tree == null:
		return null
	var controllers := tree.get_nodes_in_group("bleed_splotch_controller")
	if not controllers.is_empty():
		_bleed_splotch_controller = controllers[0] as Node
		return _bleed_splotch_controller
	if tree.current_scene == null:
		_bleed_splotch_controller_lookup_cooldown = 0.5
		return null
	_bleed_splotch_controller = tree.current_scene.get_node_or_null("GameBootstrap/BleedSplotchController")
	if _bleed_splotch_controller == null:
		_bleed_splotch_controller_lookup_cooldown = 0.5
	return _bleed_splotch_controller


func _get_hull_damage_ratio() -> float:
	return clampf(get_total_wound_damage() / maxf(max_hp, 1.0), 0.0, 1.0)


func _enter_dead_state() -> void:
	if life_state == NpcRules.LifeState.DEAD:
		return
	var previous_state := life_state
	life_state = NpcRules.LifeState.DEAD
	COMBAT_COORDINATOR.release_character(self)
	running = false
	velocity = Vector3.ZERO
	_clear_actor_move_target()
	life_state_changed.emit(previous_state, life_state)
	died.emit(self)
	state_changed.emit()


func _enter_unconscious_state() -> void:
	if life_state == NpcRules.LifeState.DEAD or life_state == NpcRules.LifeState.UNCONSCIOUS:
		return
	var previous_state := life_state
	life_state = NpcRules.LifeState.UNCONSCIOUS
	COMBAT_COORDINATOR.release_character(self)
	running = false
	velocity = Vector3.ZERO
	_clear_actor_move_target()
	life_state_changed.emit(previous_state, life_state)
	state_changed.emit()
