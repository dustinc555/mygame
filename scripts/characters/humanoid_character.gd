extends CharacterBody3D

class_name HumanoidCharacter

const WORLD_TEXT_NOTICE_SCENE = preload("res://scenes/world/effects/world_text_notice.tscn")

enum OrderType {
	NONE,
	MOVE,
	MINE,
	OPEN_CONTAINER,
	TRADE,
	TALK,
	ATTACK,
	HEAL,
	FINISH_OFF,
	CARRY,
}

@export var member_name := "Character"
@export var stable_id := ""
@export var move_speed := 3.2
@export var acceleration := 10.0
@export var interact_distance := 1.8
@export var inventory_columns := 10
@export var inventory_rows := 6
@export var max_carry_weight := 60.0
@export var show_inventory_weight := true
@export var overhead_text_height := 2.4
@export var show_nameplate := true
@export var starting_items: Array[Resource] = []

@export var faction_name := "Player"
@export var squad_name := "Default"
@export var hostile_factions: PackedStringArray = PackedStringArray()
@export var conversation_definition: Resource

@export var hunger_enabled := false
@export_range(0, 2, 1) var hunger_stage := NpcRules.HungerStage.WELL_NOURISHED
@export var hunger := 100.0
@export var hunger_drain_rate := 0.08
@export var fatigue_enabled := true
@export_range(0, 2, 1) var fatigue_stage := NpcRules.FatigueStage.WELL_RESTED
@export var fatigue := 100.0
@export var running := false
@export var sneaking := false
@export_range(0, 2, 1) var combat_stance := NpcRules.CombatStance.DEFENSIVE

@export var max_hp := 100.0
@export var hp := 100.0
@export var max_blood := 100.0
@export var blood := 100.0

@export var trade_interaction_distance := 3.0
@export var aggressive_scan_radius := NpcRules.AGGRO_RANGE
@export var assist_scan_radius := NpcRules.ASSIST_RANGE
@export var attack_range := 1.8
@export var attack_cooldown_seconds := 1.2
@export var base_attack_damage := 18.0
@export_range(0.0, 1.0, 0.01) var attack_cut_ratio := 0.05
@export var base_dodge_chance := 0.08
@export var base_block_chance := 0.06
@export var block_damage_multiplier := 0.4
@export var carry_move_speed_multiplier := 0.6

var inventory: InventoryData
var is_inspected := false
var is_selected := false
var is_focused := false
var player_party_member := false
var life_state := NpcRules.LifeState.ALIVE
var gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float

var _move_target := Vector3.ZERO
var _has_move_target := false
var _current_order_type: int = OrderType.NONE
var _order_was_player_issued := false

var _current_mining_node
var _mining_progress_by_node: Dictionary = {}
var _mining_active := false
var _current_container_target
var _current_trade_target
var _current_conversation_target
var _current_attack_target: HumanoidCharacter
var _current_heal_target: HumanoidCharacter
var _current_finish_off_target: HumanoidCharacter
var _current_carry_target: HumanoidCharacter
var _carried_by: HumanoidCharacter
var _carried_character: HumanoidCharacter

var _current_blunt_damage := 0.0
var _current_open_cut_damage := 0.0
var _current_bandaged_cut_damage := 0.0
var _bleed_rate := 0.0
var _pending_nourishment := 0.0
var _combat_cooldown_remaining := 0.0
var _ai_tick_remaining := 0.0
var _downed_recover_delay_remaining := 0.0
var _downed_target_rotation_z := 0.0
var _downed_is_settled := false
var _stored_collision_layer := 1
var _stored_collision_mask := 1

var _personal_hostile_ids: Dictionary = {}
var _last_direct_attacker_id := 0
var _assigned_talkers: Dictionary = {}
var _pending_talker_ids: Dictionary = {}

var _nameplate: Label3D
var _inspect_ring: MeshInstance3D
var _inspect_ring_material := StandardMaterial3D.new()
var _rng := RandomNumberGenerator.new()
var _work_inventory_override: InventoryData
var _active_job_provider
var _active_job_label := ""

signal inventory_changed
signal mining_changed
signal state_changed
signal combat_state_changed
signal container_reached(member, container)
signal trade_target_reached(member, target)
signal conversation_target_reached(member, target)


func _ready() -> void:
	_rng.randomize()
	inventory = InventoryData.new(inventory_columns, inventory_rows, max_carry_weight, true)
	inventory.changed.connect(_on_inventory_data_changed)
	_seed_starting_inventory()
	_setup_nameplate()
	_setup_inspect_ring()
	add_to_group("humanoid_character")
	add_to_group("npc_character")
	_sync_party_membership_group()
	hunger = clampf(hunger, 0.0, 100.0)
	fatigue = clampf(fatigue, 0.0, 100.0)
	_recalculate_vitals()


func _process(delta: float) -> void:
	if _carried_by != null:
		_update_carried_transform()
		return
	if _combat_cooldown_remaining > 0.0:
		_combat_cooldown_remaining = maxf(0.0, _combat_cooldown_remaining - delta)
	_process_needs(delta)
	_process_bleeding(delta)
	_process_recovery(delta)
	_process_ai(delta)
	_recalculate_vitals()


func _physics_process(delta: float) -> void:
	if _carried_by != null:
		velocity = Vector3.ZERO
		return
	if life_state != NpcRules.LifeState.ALIVE and _downed_is_settled and is_on_floor():
		velocity = Vector3.ZERO
		return
	_process_movement(delta)
	if life_state != NpcRules.LifeState.ALIVE:
		return
	match _current_order_type:
		OrderType.MINE:
			_process_mining(delta)
		OrderType.OPEN_CONTAINER:
			_process_container_interaction()
		OrderType.TRADE:
			_process_trade_interaction()
		OrderType.TALK:
			_process_conversation_interaction()
		OrderType.ATTACK:
			_process_attack_interaction()
		OrderType.HEAL:
			_process_heal_interaction()
		OrderType.FINISH_OFF:
			_process_finish_off_interaction()
		OrderType.CARRY:
			_process_carry_interaction()


func set_move_target(target: Vector3, issued_by_player: bool = true) -> void:
	_set_order(OrderType.MOVE, issued_by_player)
	_move_target = target
	_has_move_target = true


func stop_mining_assignment() -> void:
	if _current_mining_node != null:
		_current_mining_node.release_miner(self)
	_current_mining_node = null
	_mining_active = false
	if _current_order_type == OrderType.MINE:
		_current_order_type = OrderType.NONE
	mining_changed.emit()


func stop_container_interaction() -> void:
	if _current_container_target != null and _current_container_target.has_method("release_interactor"):
		_current_container_target.release_interactor(self)
	_current_container_target = null
	if _current_order_type == OrderType.OPEN_CONTAINER:
		_current_order_type = OrderType.NONE


func stop_trade_interaction() -> void:
	if _current_trade_target != null and _current_trade_target.has_method("release_trader"):
		_current_trade_target.release_trader(self)
	_current_trade_target = null
	if _current_order_type == OrderType.TRADE:
		_current_order_type = OrderType.NONE


func stop_conversation_interaction() -> void:
	if _current_conversation_target != null and _current_conversation_target.has_method("release_talker"):
		_current_conversation_target.release_talker(self)
	_current_conversation_target = null
	if _current_order_type == OrderType.TALK:
		_current_order_type = OrderType.NONE


func stop_attack_assignment() -> void:
	_current_attack_target = null
	if _current_order_type == OrderType.ATTACK:
		_current_order_type = OrderType.NONE
	combat_state_changed.emit()


func stop_heal_assignment() -> void:
	_current_heal_target = null
	if _current_order_type == OrderType.HEAL:
		_current_order_type = OrderType.NONE


func stop_finish_off_assignment() -> void:
	_current_finish_off_target = null
	if _current_order_type == OrderType.FINISH_OFF:
		_current_order_type = OrderType.NONE


func stop_carry_assignment() -> void:
	_current_carry_target = null
	if _current_order_type == OrderType.CARRY:
		_current_order_type = OrderType.NONE


func assign_open_container(container, issued_by_player: bool = true) -> void:
	if container == null:
		return
	_set_order(OrderType.OPEN_CONTAINER, issued_by_player)
	if _current_container_target != null and _current_container_target != container and _current_container_target.has_method("release_interactor"):
		_current_container_target.release_interactor(self)
	_current_container_target = container
	if _current_container_target.has_method("register_interactor"):
		_current_container_target.register_interactor(self)
	_move_target = _current_container_target.get_interaction_position(self)
	_has_move_target = true


func assign_trade_target(target_character, issued_by_player: bool = true) -> void:
	if target_character == null:
		return
	_set_order(OrderType.TRADE, issued_by_player)
	if _current_trade_target != null and _current_trade_target != target_character and _current_trade_target.has_method("release_trader"):
		_current_trade_target.release_trader(self)
	_current_trade_target = target_character
	if _current_trade_target.has_method("register_trader"):
		_current_trade_target.register_trader(self)
	_move_target = _current_trade_target.get_interaction_position(self)
	_has_move_target = true


func assign_conversation_target(target_character, issued_by_player: bool = true) -> void:
	if target_character == null or not target_character.has_conversation_definition():
		return
	_set_order(OrderType.TALK, issued_by_player)
	if _current_conversation_target != null and _current_conversation_target != target_character and _current_conversation_target.has_method("release_talker"):
		_current_conversation_target.release_talker(self)
	_current_conversation_target = target_character
	if _current_conversation_target.has_method("register_talker"):
		_current_conversation_target.register_talker(self)
	_move_target = _current_conversation_target.get_interaction_position(self)
	_has_move_target = true


func assign_mining_resource(resource_node, issued_by_player: bool = true) -> void:
	if resource_node == null:
		return
	_set_order(OrderType.MINE, issued_by_player)
	if _current_mining_node != null and _current_mining_node != resource_node:
		_current_mining_node.release_miner(self)
	_current_mining_node = resource_node
	_current_mining_node.register_miner(self)
	_mining_active = false
	_move_target = _current_mining_node.get_mining_position(self)
	_has_move_target = true
	mining_changed.emit()


func assign_attack_target(target_character: HumanoidCharacter, issued_by_player: bool = true, notify_target: bool = true, notify_allies: bool = true) -> void:
	if target_character == null or target_character == self or not is_instance_valid(target_character):
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	if target_character.life_state != NpcRules.LifeState.ALIVE:
		return
	if _current_attack_target == target_character and _current_order_type == OrderType.ATTACK:
		return
	_set_order(OrderType.ATTACK, issued_by_player)
	_current_attack_target = target_character
	mark_hostile(target_character)
	target_character.mark_hostile(self)
	if notify_target:
		target_character.notify_incoming_attack(self)
	if notify_allies:
		_notify_defensive_allies_of_engagement(target_character)
	combat_state_changed.emit()


func assign_heal_target(target_character: HumanoidCharacter, issued_by_player: bool = true) -> void:
	if target_character == null or target_character == self:
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	_set_order(OrderType.HEAL, issued_by_player)
	_current_heal_target = target_character


func assign_finish_off_target(target_character: HumanoidCharacter, issued_by_player: bool = true) -> void:
	if target_character == null or target_character == self:
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	if target_character.life_state != NpcRules.LifeState.UNCONSCIOUS:
		return
	_set_order(OrderType.FINISH_OFF, issued_by_player)
	_current_finish_off_target = target_character


func assign_carry_target(target_character: HumanoidCharacter, issued_by_player: bool = true) -> void:
	if target_character == null or target_character == self:
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	if not target_character.can_be_carried_by(self) or _carried_character != null:
		return
	_set_order(OrderType.CARRY, issued_by_player)
	_current_carry_target = target_character


func has_mining_assignment() -> bool:
	return _current_mining_node != null


func get_assigned_mining_node():
	return _current_mining_node


func is_actively_mining() -> bool:
	return _mining_active


func get_mining_progress_ratio() -> float:
	if _current_mining_node == null:
		return 0.0
	return minf(_get_stored_mining_progress(_current_mining_node) / _current_mining_node.mine_duration, 1.0)


func can_eat_item(definition: ItemDefinition) -> bool:
	return definition != null and definition.nutrition_value > 0.0 and hunger_enabled


func eat_item(definition: ItemDefinition) -> bool:
	if not can_eat_item(definition):
		return false
	if not inventory.remove_item_count(definition, 1):
		return false
	_pending_nourishment += definition.nutrition_value
	return true


func begin_job_assignment(provider, job_label: String, work_inventory: InventoryData) -> void:
	if _work_inventory_override != null and _work_inventory_override.changed.is_connected(_on_inventory_data_changed):
		_work_inventory_override.changed.disconnect(_on_inventory_data_changed)
	_active_job_provider = provider
	_active_job_label = job_label
	_work_inventory_override = work_inventory
	if _work_inventory_override != null and not _work_inventory_override.changed.is_connected(_on_inventory_data_changed):
		_work_inventory_override.changed.connect(_on_inventory_data_changed)
	inventory_changed.emit()
	state_changed.emit()


func end_job_assignment() -> void:
	if _work_inventory_override != null and _work_inventory_override.changed.is_connected(_on_inventory_data_changed):
		_work_inventory_override.changed.disconnect(_on_inventory_data_changed)
	_active_job_provider = null
	_active_job_label = ""
	_work_inventory_override = null
	inventory_changed.emit()
	state_changed.emit()


func get_active_job_provider():
	return _active_job_provider


func get_inventory_for_display() -> InventoryData:
	if _work_inventory_override != null:
		return _work_inventory_override
	return inventory


func is_displaying_work_inventory() -> bool:
	return _work_inventory_override != null


func get_inventory_display_title() -> String:
	if is_displaying_work_inventory():
		return "%s Work Inventory" % member_name
	return "%s Inventory" % member_name


func can_transfer_display_inventory_to(_target_owner) -> bool:
	return not is_displaying_work_inventory()


func can_receive_inventory_transfer_from(_source_owner) -> bool:
	return not is_displaying_work_inventory()


func can_eat_inventory_entry(entry) -> bool:
	if entry == null:
		return false
	var display_inventory := get_inventory_for_display()
	return can_eat_item(entry.definition) and display_inventory != null and display_inventory.entries.has(entry)


func consume_inventory_entry(entry) -> bool:
	if not can_eat_inventory_entry(entry):
		return false
	var display_inventory := get_inventory_for_display()
	if not display_inventory.remove_item_count(entry.definition, 1):
		return false
	_pending_nourishment += entry.definition.nutrition_value
	if display_inventory != inventory:
		inventory_changed.emit()
	return true


func get_job_status_text() -> String:
	if _active_job_provider == null:
		return ""
	if _active_job_provider.has_method("get_provider_name"):
		return "Working for %s" % _active_job_provider.get_provider_name()
	return "Working"


func is_authorized_for_owner(owner_character: HumanoidCharacter, owner_faction: String = "") -> bool:
	if owner_character != null and owner_character == self:
		return true
	if _active_job_provider == null:
		return owner_character == null and not owner_faction.is_empty() and faction_name == owner_faction
	if not _active_job_provider.has_method("get_provider_character"):
		return false
	var provider_owner: HumanoidCharacter = _active_job_provider.get_provider_character()
	if owner_character != null:
		return provider_owner == owner_character
	return owner_faction == provider_owner.faction_name


func show_world_notice(message: String, color: Color = Color(1.0, 0.28, 0.28, 1.0), lifetime: float = 1.0) -> void:
	_show_world_notice(message, color, lifetime)


func show_world_speech(message: String, lifetime: float = 5.0) -> void:
	_show_world_notice(message, Color(0.94, 0.92, 0.86, 1.0), lifetime, 0.22)


func can_use_bandage_item(definition: ItemDefinition) -> bool:
	return definition != null and definition.bandage_power > 0.0


func can_bandage_target(target: HumanoidCharacter) -> bool:
	if target == null or not target.can_receive_bandage():
		return false
	for entry in inventory.entries:
		if can_use_bandage_item(entry.definition):
			return true
	return false


func get_inventory_display_name() -> String:
	return member_name


func get_inventory_world_position() -> Vector3:
	return global_position


func get_inventory_cell_size() -> Vector2:
	return Vector2(30.0, 30.0)


func shows_inventory_weight() -> bool:
	if is_displaying_work_inventory():
		return false
	return show_inventory_weight


func set_inspected(value: bool) -> void:
	is_inspected = value
	_update_inspect_visual()


func get_hunger_stage() -> int:
	return hunger_stage


func get_fatigue_stage() -> int:
	return fatigue_stage


func get_total_wound_damage() -> float:
	return _current_blunt_damage + _current_open_cut_damage + _current_bandaged_cut_damage


func get_open_cut_damage() -> float:
	return _current_open_cut_damage


func get_bandaged_cut_damage() -> float:
	return _current_bandaged_cut_damage


func get_blunt_damage() -> float:
	return _current_blunt_damage


func get_bleed_rate() -> float:
	return _bleed_rate


func get_stance_label() -> String:
	return NpcRules.get_stance_label(combat_stance)


func get_life_state_label() -> String:
	return NpcRules.get_life_state_label(life_state)


func get_hunger_stage_label() -> String:
	return NpcRules.get_hunger_stage_label(get_hunger_stage())


func get_fatigue_stage_label() -> String:
	return NpcRules.get_fatigue_stage_label(get_fatigue_stage())


func _apply_hunger_delta(amount: float) -> void:
	if is_zero_approx(amount):
		return
	var remaining := amount
	while not is_zero_approx(remaining):
		if remaining > 0.0:
			var recoverable := 100.0 - hunger
			var recovery_step := minf(remaining, recoverable)
			hunger += recovery_step
			remaining -= recovery_step
			if hunger >= 100.0 and hunger_stage > NpcRules.HungerStage.WELL_NOURISHED and remaining > 0.0:
				hunger_stage -= 1
				hunger = 0.0
				continue
			break
		var drainable := hunger
		var drain_step := minf(-remaining, drainable)
		hunger -= drain_step
		remaining += drain_step
		if hunger <= 0.0:
			if hunger_stage < NpcRules.HungerStage.STARVING:
				hunger_stage += 1
				hunger = 100.0
				continue
			if life_state != NpcRules.LifeState.DEAD:
				hunger = 0.0
				_enter_dead_state()
			break
		break
	hunger = clampf(hunger, 0.0, 100.0)


func _apply_fatigue_delta(amount: float) -> void:
	if is_zero_approx(amount):
		return
	var remaining := amount
	while not is_zero_approx(remaining):
		if remaining > 0.0:
			var recoverable := 100.0 - fatigue
			var recovery_step := minf(remaining, recoverable)
			fatigue += recovery_step
			remaining -= recovery_step
			if fatigue >= 100.0 and fatigue_stage > NpcRules.FatigueStage.WELL_RESTED and remaining > 0.0:
				fatigue_stage -= 1
				fatigue = 0.0
				continue
			break
		var drainable := fatigue
		var drain_step := minf(-remaining, drainable)
		fatigue -= drain_step
		remaining += drain_step
		if fatigue <= 0.0:
			if fatigue_stage < NpcRules.FatigueStage.EXHAUSTED:
				fatigue_stage += 1
				fatigue = 100.0
				continue
			fatigue = 0.0
			if life_state == NpcRules.LifeState.ALIVE:
				_enter_unconscious_state()
			break
		break
	fatigue = clampf(fatigue, 0.0, 100.0)


func is_running_enabled() -> bool:
	return running and can_continue_running()


func can_continue_running() -> bool:
	if life_state != NpcRules.LifeState.ALIVE:
		return false
	if fatigue_stage < NpcRules.FatigueStage.EXHAUSTED:
		return true
	return fatigue > NpcRules.FATIGUE_RUN_LOCKOUT_THRESHOLD


func can_enable_running() -> bool:
	return can_continue_running()


func is_in_combat() -> bool:
	return _current_order_type == OrderType.ATTACK and _current_attack_target != null


func get_current_combat_target() -> HumanoidCharacter:
	return _current_attack_target


func has_bandageable_wounds() -> bool:
	return _current_open_cut_damage > 0.0 or _bleed_rate > 0.0


func can_receive_bandage() -> bool:
	return life_state != NpcRules.LifeState.DEAD and has_bandageable_wounds()


func can_be_carried() -> bool:
	return can_be_carried_by(null)


func can_be_carried_by(carrier: HumanoidCharacter) -> bool:
	if _carried_by != null:
		return false
	if carrier != null and carrier.faction_name == faction_name:
		return true
	return life_state == NpcRules.LifeState.ASLEEP or life_state == NpcRules.LifeState.UNCONSCIOUS or life_state == NpcRules.LifeState.DEAD


func is_carried() -> bool:
	return _carried_by != null


func is_carrying_someone() -> bool:
	return _carried_character != null


func get_carried_character() -> HumanoidCharacter:
	return _carried_character


func has_hostility_with(other: HumanoidCharacter) -> bool:
	return is_hostile_to(other) or other.is_hostile_to(self)


func is_hostile_to(other: HumanoidCharacter) -> bool:
	if other == null or other == self:
		return false
	if _personal_hostile_ids.has(other.get_instance_id()):
		return true
	return hostile_factions.has(other.faction_name)


func mark_hostile(other: HumanoidCharacter) -> void:
	if other == null or other == self:
		return
	_personal_hostile_ids[other.get_instance_id()] = true


func clear_personal_hostility(other: HumanoidCharacter) -> void:
	if other == null:
		return
	_personal_hostile_ids.erase(other.get_instance_id())


func set_running_enabled(value: bool) -> bool:
	if value:
		sneaking = false
		running = can_enable_running()
	else:
		running = false
	state_changed.emit()
	return running == value


func set_sneaking_enabled(value: bool) -> void:
	if value:
		running = false
	sneaking = value and life_state == NpcRules.LifeState.ALIVE
	state_changed.emit()


func notify_incoming_attack(attacker: HumanoidCharacter) -> void:
	if attacker == null or attacker == self:
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	mark_hostile(attacker)
	attacker.mark_hostile(self)
	_last_direct_attacker_id = attacker.get_instance_id()
	_notify_defensive_allies_of_attack(attacker)
	if combat_stance == NpcRules.CombatStance.PASSIVE:
		return
	_try_start_self_defense(attacker)


func set_combat_stance(value: int) -> void:
	if value <= NpcRules.CombatStance.AGGRESSIVE:
		combat_stance = NpcRules.CombatStance.AGGRESSIVE
	elif value >= NpcRules.CombatStance.PASSIVE:
		combat_stance = NpcRules.CombatStance.PASSIVE
	else:
		combat_stance = NpcRules.CombatStance.DEFENSIVE
	state_changed.emit()


func receive_attack(attacker: HumanoidCharacter, blunt_damage: float, cut_damage: float) -> String:
	if attacker == null or life_state == NpcRules.LifeState.DEAD:
		return "ignored"
	mark_hostile(attacker)
	attacker.mark_hostile(self)
	_last_direct_attacker_id = attacker.get_instance_id()
	if _rng.randf() <= get_stat_value("dodge_chance"):
		_show_world_notice("Dodge", Color(0.74, 0.94, 1.0, 1.0))
		_try_start_self_defense(attacker)
		return "dodged"
	var final_blunt := maxf(blunt_damage, 0.0)
	var final_cut := maxf(cut_damage, 0.0)
	if _rng.randf() <= get_stat_value("block_chance"):
		final_blunt *= block_damage_multiplier
		final_cut *= block_damage_multiplier
		_show_world_notice("Block", Color(0.86, 0.9, 1.0, 1.0))
	_current_blunt_damage += final_blunt
	_current_open_cut_damage += final_cut
	_bleed_rate += final_cut * 0.12
	_show_world_notice("Hit", Color(1.0, 0.42, 0.42, 1.0))
	_recalculate_vitals()
	_try_start_self_defense(attacker)
	return "hit"


func apply_bandage_from(actor: HumanoidCharacter) -> bool:
	if actor == null or not can_receive_bandage() or not actor.can_bandage_target(self):
		return false
	var bandage_definition := actor._get_best_bandage_definition()
	if bandage_definition == null:
		return false
	if not actor.inventory.remove_item_count(bandage_definition, 1):
		return false
	_current_bandaged_cut_damage += _current_open_cut_damage
	_current_open_cut_damage = 0.0
	_bleed_rate = maxf(0.0, _bleed_rate - bandage_definition.bandage_power)
	if _bleed_rate <= 0.01:
		_bleed_rate = 0.0
	_recalculate_vitals()
	return true


func get_interaction_position(member: HumanoidCharacter) -> Vector3:
	var slot_index := _get_talker_slot(member)
	var angle := TAU * float(slot_index) / 6.0
	return global_position + Vector3(cos(angle), 0.0, sin(angle)) * interact_distance


func get_combat_approach_position(attacker: HumanoidCharacter) -> Vector3:
	var away := global_position - attacker.global_position
	away.y = 0.0
	if away.length_squared() <= 0.0001:
		away = Vector3.FORWARD
	return global_position - away.normalized() * maxf(attack_range - 0.2, 0.9)


func _process_movement(delta: float) -> void:
	if life_state != NpcRules.LifeState.ALIVE:
		_process_downed_movement(delta)
		if _downed_is_settled and is_on_floor():
			return
		move_and_slide()
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if _has_move_target and life_state == NpcRules.LifeState.ALIVE:
		var to_target := _move_target - global_position
		to_target.y = 0.0
		if to_target.length() <= 0.1:
			_has_move_target = false
			if _current_order_type == OrderType.MOVE:
				_current_order_type = OrderType.NONE
			horizontal_velocity = Vector3.ZERO
		else:
			var direction := to_target.normalized()
			var target_speed := _get_current_move_speed()
			horizontal_velocity = horizontal_velocity.lerp(direction * target_speed, min(1.0, acceleration * delta))
			look_at(global_position + direction, Vector3.UP)
	else:
		horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, min(1.0, acceleration * delta))
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	move_and_slide()
	rotation.x = lerp_angle(rotation.x, 0.0, minf(1.0, 10.0 * delta))
	rotation.z = lerp_angle(rotation.z, 0.0, minf(1.0, 10.0 * delta))


func _process_downed_movement(delta: float) -> void:
	if _downed_is_settled and is_on_floor():
		velocity = Vector3.ZERO
		rotation.z = _downed_target_rotation_z
		rotation.x = 0.0
		return
	velocity.y -= gravity * delta
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, minf(1.0, 9.0 * delta))
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	rotation.z = lerp_angle(rotation.z, _downed_target_rotation_z, minf(1.0, 10.0 * delta))
	rotation.x = lerp_angle(rotation.x, 0.0, minf(1.0, 7.5 * delta))
	if is_on_floor():
		var floor_is_flat := get_floor_normal().dot(Vector3.UP) >= 0.98
		var horizontal_speed := Vector2(velocity.x, velocity.z).length()
		var rotation_delta := absf(wrapf(rotation.z - _downed_target_rotation_z, -PI, PI))
		if floor_is_flat and horizontal_speed <= 0.08 and absf(velocity.y) <= 0.15 and rotation_delta <= 0.04:
			_downed_is_settled = true
			velocity = Vector3.ZERO
			rotation.z = _downed_target_rotation_z


func _process_needs(delta: float) -> void:
	if hunger_enabled:
		if _pending_nourishment > 0.0:
			var nourishment_step := minf(_pending_nourishment, NpcRules.NOURISHMENT_APPLY_RATE * delta * 100.0)
			_pending_nourishment -= nourishment_step
			_apply_hunger_delta(nourishment_step)
		else:
			_apply_hunger_delta(-get_stat_value("hunger_drain_rate") * NpcRules.WORLD_HUNGER_DRAIN_MULTIPLIER * delta)

	if fatigue_enabled:
		var was_running := running
		var fatigue_delta := 0.0
		if life_state != NpcRules.LifeState.ALIVE:
			fatigue_delta += get_stat_value("fatigue_recovery_rate") * delta
		elif _is_working():
			fatigue_delta -= NpcRules.FATIGUE_WORK_DRAIN * delta
		elif is_in_combat():
			fatigue_delta -= NpcRules.FATIGUE_COMBAT_DRAIN * delta
		elif is_running_enabled() and _has_move_target:
			fatigue_delta -= NpcRules.FATIGUE_RUN_DRAIN * delta
		else:
			fatigue_delta += get_stat_value("fatigue_recovery_rate") * delta
		_apply_fatigue_delta(fatigue_delta)
		if running and not can_continue_running():
			running = false
		if was_running != running:
			state_changed.emit()


func _process_bleeding(delta: float) -> void:
	if _bleed_rate <= 0.0 or life_state == NpcRules.LifeState.DEAD:
		return
	blood = clampf(blood - _bleed_rate * NpcRules.BLEED_TO_BLOOD_RATE * delta, 0.0, max_blood)
	if blood <= 0.0:
		_enter_dead_state()


func _process_recovery(delta: float) -> void:
	if life_state == NpcRules.LifeState.DEAD:
		return
	var healing_step := get_stat_value("healing_rate") * delta
	if healing_step <= 0.0:
		return
	_current_blunt_damage = maxf(0.0, _current_blunt_damage - healing_step)
	_current_bandaged_cut_damage = maxf(0.0, _current_bandaged_cut_damage - healing_step * 0.8)
	_current_open_cut_damage = maxf(0.0, _current_open_cut_damage - healing_step * 0.35)
	if _bleed_rate > 0.0:
		_bleed_rate = maxf(0.0, _bleed_rate - healing_step * 0.02)
	if life_state == NpcRules.LifeState.UNCONSCIOUS:
		_downed_recover_delay_remaining = maxf(0.0, _downed_recover_delay_remaining - delta)
	_recalculate_vitals()


func _process_ai(delta: float) -> void:
	if life_state != NpcRules.LifeState.ALIVE:
		return
	if _current_order_type == OrderType.HEAL and (_current_heal_target == null or not is_instance_valid(_current_heal_target)):
		stop_heal_assignment()
	if _current_order_type == OrderType.FINISH_OFF and (_current_finish_off_target == null or not is_instance_valid(_current_finish_off_target) or _current_finish_off_target.life_state != NpcRules.LifeState.UNCONSCIOUS):
		stop_finish_off_assignment()
	if _current_order_type == OrderType.CARRY and (_current_carry_target == null or not is_instance_valid(_current_carry_target) or not _current_carry_target.can_be_carried_by(self)):
		stop_carry_assignment()
	if _current_order_type == OrderType.ATTACK and (_current_attack_target == null or not is_instance_valid(_current_attack_target) or _current_attack_target.life_state != NpcRules.LifeState.ALIVE):
		stop_attack_assignment()
	_ai_tick_remaining -= delta
	if _ai_tick_remaining > 0.0:
		return
	_ai_tick_remaining = 0.35 + _rng.randf_range(0.0, 0.15)
	if _should_seek_combat_target():
		var target := _find_ai_target()
		if target != null:
			assign_attack_target(target, false)


func _process_mining(delta: float) -> void:
	if _current_mining_node == null:
		return
	var mining_position: Vector3 = _current_mining_node.get_mining_position(self)
	if global_position.distance_to(mining_position) > interact_distance:
		_move_target = mining_position
		_has_move_target = true
		_mining_active = false
		mining_changed.emit()
		return
	if _has_move_target:
		return
	_mining_active = true
	var progress := _get_stored_mining_progress(_current_mining_node) + delta
	var duration := maxf(_current_mining_node.mine_duration, 0.01)
	var mining_inventory := _work_inventory_override if _work_inventory_override != null else inventory
	if progress >= duration:
		if mining_inventory.add_item(_current_mining_node.item_definition):
			progress = 0.0
		else:
			progress = duration
			_mining_active = false
	_store_mining_progress(_current_mining_node, progress)
	mining_changed.emit()


func _process_container_interaction() -> void:
	if _current_container_target == null:
		return
	var interaction_position: Vector3 = _current_container_target.get_interaction_position(self)
	if global_position.distance_to(interaction_position) > interact_distance:
		_move_target = interaction_position
		_has_move_target = true
		return
	if _has_move_target:
		return
	var container = _current_container_target
	_current_container_target = null
	_current_order_type = OrderType.NONE
	container_reached.emit(self, container)


func _process_trade_interaction() -> void:
	if _current_trade_target == null:
		return
	var interaction_position: Vector3 = _current_trade_target.get_interaction_position(self)
	var target_position: Vector3 = _current_trade_target.global_position
	if global_position.distance_to(target_position) > trade_interaction_distance:
		_move_target = interaction_position
		_has_move_target = true
		return
	_has_move_target = false
	var target = _current_trade_target
	_current_trade_target = null
	_current_order_type = OrderType.NONE
	trade_target_reached.emit(self, target)


func _process_conversation_interaction() -> void:
	if _current_conversation_target == null:
		return
	var interaction_position: Vector3 = _current_conversation_target.get_interaction_position(self)
	var target_position: Vector3 = _current_conversation_target.global_position
	if global_position.distance_to(target_position) > interact_distance:
		_move_target = interaction_position
		_has_move_target = true
		return
	_has_move_target = false
	var target = _current_conversation_target
	_current_conversation_target = null
	_current_order_type = OrderType.NONE
	conversation_target_reached.emit(self, target)


func _process_attack_interaction() -> void:
	if _current_attack_target == null or not is_instance_valid(_current_attack_target):
		stop_attack_assignment()
		return
	if _current_attack_target.life_state != NpcRules.LifeState.ALIVE:
		stop_attack_assignment()
		return
	var target_position := _current_attack_target.get_combat_approach_position(self)
	var target_distance := global_position.distance_to(_current_attack_target.global_position)
	if target_distance > attack_range:
		_move_target = target_position
		_has_move_target = true
		return
	_has_move_target = false
	look_at(_current_attack_target.global_position, Vector3.UP)
	if _combat_cooldown_remaining > 0.0:
		return
	var total_damage := get_stat_value("attack_damage")
	var cut_damage := total_damage * get_stat_value("cut_ratio")
	var blunt_damage := total_damage - cut_damage
	_current_attack_target.receive_attack(self, blunt_damage, cut_damage)
	_combat_cooldown_remaining = maxf(0.2, get_stat_value("attack_cooldown"))


func _process_heal_interaction() -> void:
	if _current_heal_target == null or not is_instance_valid(_current_heal_target):
		stop_heal_assignment()
		return
	if not _current_heal_target.can_receive_bandage():
		show_world_speech("They don't need bandaging", 5.0)
		stop_heal_assignment()
		return
	if _get_best_bandage_definition() == null:
		show_world_speech("I don't have anything to heal with", 5.0)
		stop_heal_assignment()
		return
	var target_position := _current_heal_target.get_combat_approach_position(self)
	if global_position.distance_to(_current_heal_target.global_position) > interact_distance:
		_move_target = target_position
		_has_move_target = true
		return
	_has_move_target = false
	if _current_heal_target.apply_bandage_from(self):
		stop_heal_assignment()


func _process_finish_off_interaction() -> void:
	if _current_finish_off_target == null or not is_instance_valid(_current_finish_off_target):
		stop_finish_off_assignment()
		return
	if _current_finish_off_target.life_state != NpcRules.LifeState.UNCONSCIOUS:
		stop_finish_off_assignment()
		return
	var target_position := _current_finish_off_target.get_combat_approach_position(self)
	if global_position.distance_to(_current_finish_off_target.global_position) > interact_distance:
		_move_target = target_position
		_has_move_target = true
		return
	_has_move_target = false
	_current_finish_off_target.force_kill(self)
	_show_world_notice("Finished", Color(0.95, 0.2, 0.2, 1.0))
	stop_finish_off_assignment()


func _process_carry_interaction() -> void:
	if _current_carry_target == null or not is_instance_valid(_current_carry_target):
		stop_carry_assignment()
		return
	if not _current_carry_target.can_be_carried_by(self) or _carried_character != null:
		stop_carry_assignment()
		return
	var target_position := _current_carry_target.global_position
	if global_position.distance_to(target_position) > interact_distance:
		_move_target = target_position
		_has_move_target = true
		return
	_has_move_target = false
	_attach_carried_character(_current_carry_target)
	_show_world_notice("Carrying %s" % _current_carry_target.member_name, Color(0.86, 0.92, 1.0, 1.0))
	stop_carry_assignment()


func _get_stored_mining_progress(resource_node) -> float:
	return _mining_progress_by_node.get(resource_node.get_instance_id(), 0.0)


func _store_mining_progress(resource_node, progress: float) -> void:
	_mining_progress_by_node[resource_node.get_instance_id()] = progress


func _on_inventory_data_changed() -> void:
	inventory_changed.emit()


func has_conversation_definition() -> bool:
	return conversation_definition != null


func get_conversation_definition():
	return conversation_definition


func register_talker(member: HumanoidCharacter) -> void:
	_get_talker_slot(member)
	_pending_talker_ids[member.get_instance_id()] = true


func release_talker(member: HumanoidCharacter) -> void:
	_pending_talker_ids.erase(member.get_instance_id())
	_assigned_talkers.erase(member.get_instance_id())


func resolve_talk(member: HumanoidCharacter) -> bool:
	if member == null:
		return false
	var actor_id := member.get_instance_id()
	if not _pending_talker_ids.has(actor_id):
		return false
	_pending_talker_ids.clear()
	return true


func _get_talker_slot(member: HumanoidCharacter) -> int:
	var key := member.get_instance_id()
	if _assigned_talkers.has(key):
		return _assigned_talkers[key]
	for slot_index in range(6):
		if not _assigned_talkers.values().has(slot_index):
			_assigned_talkers[key] = slot_index
			return slot_index
	_assigned_talkers[key] = 0
	return 0


func is_player_party_member() -> bool:
	return player_party_member


func set_player_party_member(value: bool) -> void:
	player_party_member = value
	_sync_party_membership_group()


func set_selected(value: bool) -> void:
	is_selected = value
	_update_selection_state()


func set_focused(value: bool) -> void:
	is_focused = value
	_update_selection_state()


func _update_selection_state() -> void:
	_update_inspect_visual()


func _sync_party_membership_group() -> void:
	if player_party_member:
		add_to_group("party_member")
	else:
		remove_from_group("party_member")


func _setup_nameplate() -> void:
	if not show_nameplate:
		return
	_nameplate = get_node_or_null("Nameplate")
	if _nameplate == null:
		_nameplate = Label3D.new()
		_nameplate.name = "Nameplate"
		add_child(_nameplate)
	_nameplate.text = member_name
	_nameplate.position = Vector3(0.0, 2.15, 0.0)
	_nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nameplate.no_depth_test = false
	_nameplate.font_size = 50
	_nameplate.modulate = Color(0.56, 0.56, 0.6, 0.96)
	_nameplate.outline_size = 0
	_nameplate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _setup_inspect_ring() -> void:
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.74
	ring_mesh.bottom_radius = 0.74
	ring_mesh.height = 0.04
	ring_mesh.radial_segments = 24
	ring_mesh.rings = 2
	_inspect_ring = MeshInstance3D.new()
	_inspect_ring.name = "InspectRing"
	_inspect_ring.mesh = ring_mesh
	_inspect_ring.position = Vector3(0.0, 0.025, 0.0)
	_inspect_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_inspect_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_inspect_ring_material.albedo_color = Color(0.72, 0.72, 0.76, 0.95)
	_inspect_ring.material_override = _inspect_ring_material
	_inspect_ring.visible = false
	add_child(_inspect_ring)


func _update_inspect_visual() -> void:
	if _inspect_ring != null:
		_inspect_ring.visible = is_inspected


func _set_order(order_type: int, issued_by_player: bool) -> void:
	if issued_by_player and _active_job_provider != null and _active_job_provider.has_method("pause_worker_job"):
		_active_job_provider.pause_worker_job(self, true)
	_cancel_non_matching_assignments(order_type)
	_current_order_type = int(order_type)
	_order_was_player_issued = issued_by_player
	if order_type != OrderType.MINE:
		_mining_active = false
		mining_changed.emit()


func _cancel_non_matching_assignments(next_order_type: int) -> void:
	if next_order_type != OrderType.MINE:
		stop_mining_assignment()
	if next_order_type != OrderType.OPEN_CONTAINER:
		stop_container_interaction()
	if next_order_type != OrderType.TRADE:
		stop_trade_interaction()
	if next_order_type != OrderType.TALK:
		stop_conversation_interaction()
	if next_order_type != OrderType.ATTACK:
		stop_attack_assignment()
	if next_order_type != OrderType.HEAL:
		stop_heal_assignment()
	if next_order_type != OrderType.FINISH_OFF:
		stop_finish_off_assignment()
	if next_order_type != OrderType.CARRY:
		stop_carry_assignment()


func _seed_starting_inventory() -> void:
	for stock in starting_items:
		if stock != null and stock.item_definition != null and stock.quantity > 0:
			inventory.add_item_count(stock.item_definition, stock.quantity)


func _recalculate_vitals() -> void:
	hp = max_hp - get_total_wound_damage()
	if life_state == NpcRules.LifeState.DEAD:
		return
	if blood <= 0.0:
		if life_state != NpcRules.LifeState.DEAD:
			_enter_dead_state()
		return
	if hp <= -max_hp * NpcRules.DEATH_HP_FACTOR:
		if life_state != NpcRules.LifeState.DEAD:
			_enter_dead_state()
		return
	if hp <= 0.0:
		if life_state == NpcRules.LifeState.ALIVE:
			_enter_unconscious_state()
		return
	if life_state != NpcRules.LifeState.ALIVE and _downed_recover_delay_remaining <= 0.0 and _carried_by == null:
		life_state = NpcRules.LifeState.ALIVE
		_restore_from_downed_state()
		state_changed.emit()


func _enter_unconscious_state() -> void:
	if life_state == NpcRules.LifeState.DEAD or life_state == NpcRules.LifeState.UNCONSCIOUS:
		return
	life_state = NpcRules.LifeState.UNCONSCIOUS
	running = false
	_has_move_target = false
	_downed_is_settled = false
	_clear_all_active_orders()
	if _carried_character != null:
		drop_carried_character()
	if _active_job_provider != null and _active_job_provider.has_method("pause_worker_job"):
		_active_job_provider.pause_worker_job(self, false)
	_downed_recover_delay_remaining = 15.0
	_enter_downed_state(false)
	_show_world_notice("Unconscious", Color(1.0, 0.85, 0.45, 1.0))
	state_changed.emit()


func _enter_dead_state() -> void:
	if life_state == NpcRules.LifeState.DEAD:
		return
	life_state = NpcRules.LifeState.DEAD
	running = false
	_has_move_target = false
	_downed_is_settled = false
	_clear_all_active_orders()
	if _carried_character != null:
		drop_carried_character()
	if _active_job_provider != null and _active_job_provider.has_method("pause_worker_job"):
		_active_job_provider.pause_worker_job(self, false)
	_enter_downed_state(true)
	_show_world_notice("Dead", Color(1.0, 0.2, 0.2, 1.0))
	velocity = Vector3.ZERO
	state_changed.emit()


func _get_base_stat_value(stat_name: String) -> float:
	match stat_name:
		"attack_damage":
			return base_attack_damage
		"attack_cooldown":
			return attack_cooldown_seconds
		"cut_ratio":
			return attack_cut_ratio
		"dodge_chance":
			return base_dodge_chance
		"block_chance":
			return base_block_chance
		"move_speed_multiplier":
			return 1.0
		"run_speed_multiplier":
			return NpcRules.RUN_SPEED_MULTIPLIER
		"hunger_drain_rate":
			return hunger_drain_rate
		"fatigue_recovery_rate":
			return NpcRules.FATIGUE_IDLE_RECOVERY
		"healing_rate":
			return NpcRules.BASE_HEAL_RATE
	return 0.0


func _collect_stat_modifiers() -> Array:
	var modifiers: Array = []
	NpcRules.append_stage_modifiers(modifiers, get_hunger_stage(), get_fatigue_stage(), _current_open_cut_damage, max_hp)
	if life_state == NpcRules.LifeState.UNCONSCIOUS:
		modifiers.append({"stat": "healing_rate", "mul": NpcRules.UNCONSCIOUS_HEAL_MULTIPLIER})
	if running and _has_move_target:
		modifiers.append({"stat": "move_speed_multiplier", "mul": _get_base_stat_value("run_speed_multiplier")})
	if sneaking:
		modifiers.append({"stat": "move_speed_multiplier", "mul": 0.65})
	if is_carrying_someone():
		modifiers.append({"stat": "move_speed_multiplier", "mul": carry_move_speed_multiplier})
	return modifiers


func get_stat_value(stat_name: String, include_secondary_modifiers: bool = true) -> float:
	var value := _get_base_stat_value(stat_name)
	var additive := 0.0
	var multiplier := 1.0
	for modifier in _collect_stat_modifiers():
		if modifier.get("stat", "") != stat_name:
			continue
		additive += modifier.get("add", 0.0)
		multiplier *= modifier.get("mul", 1.0)
	value = (value + additive) * multiplier
	if include_secondary_modifiers:
		match stat_name:
			"dodge_chance", "block_chance", "cut_ratio":
				value = clampf(value, 0.0, 0.95)
			"attack_cooldown":
				value = maxf(0.2, value)
			"move_speed_multiplier", "run_speed_multiplier", "attack_damage", "hunger_drain_rate", "fatigue_recovery_rate", "healing_rate":
				value = maxf(0.0, value)
	return value


func _get_current_move_speed() -> float:
	return move_speed * get_stat_value("move_speed_multiplier")


func _should_seek_combat_target() -> bool:
	if _current_order_type == OrderType.HEAL:
		return false
	if _carried_by != null or is_carrying_someone():
		return false
	if _current_order_type == OrderType.ATTACK and _current_attack_target != null:
		return false
	if _order_was_player_issued and _current_order_type in [OrderType.MOVE, OrderType.MINE, OrderType.OPEN_CONTAINER, OrderType.TRADE]:
		return false
	if combat_stance == NpcRules.CombatStance.PASSIVE and _last_direct_attacker_id == 0:
		return false
	return true


func _find_ai_target() -> HumanoidCharacter:
	if combat_stance == NpcRules.CombatStance.PASSIVE:
		return _get_last_direct_attacker_target()
	if combat_stance == NpcRules.CombatStance.DEFENSIVE:
		var self_defense_target := _get_last_direct_attacker_target()
		if self_defense_target != null:
			return self_defense_target
		return _find_defensive_assist_target()
	return _find_nearest_hostile(aggressive_scan_radius)


func _get_last_direct_attacker_target() -> HumanoidCharacter:
	if _last_direct_attacker_id == 0:
		return null
	for node in get_tree().get_nodes_in_group("npc_character"):
		if node is HumanoidCharacter and node.get_instance_id() == _last_direct_attacker_id and node.life_state == NpcRules.LifeState.ALIVE:
			return node
	return null


func _find_defensive_assist_target() -> HumanoidCharacter:
	for node in get_tree().get_nodes_in_group("npc_character"):
		if not (node is HumanoidCharacter):
			continue
		var ally: HumanoidCharacter = node
		if ally == self or ally.life_state == NpcRules.LifeState.DEAD:
			continue
		if not _should_defend_ally(ally):
			continue
		if global_position.distance_to(ally.global_position) > assist_scan_radius:
			continue
		var ally_target := ally.get_current_combat_target()
		if ally_target != null and is_instance_valid(ally_target) and ally_target.life_state == NpcRules.LifeState.ALIVE and has_hostility_with(ally_target):
			return ally_target
	return null


func _should_defend_ally(ally: HumanoidCharacter) -> bool:
	if ally == null:
		return false
	if ally.faction_name != faction_name:
		return false
	if ally.squad_name != squad_name:
		return false
	# Allied faction assistance can expand here once deeper faction relations are added.
	return true


func _find_nearest_hostile(scan_radius: float) -> HumanoidCharacter:
	var best_target: HumanoidCharacter
	var best_distance := scan_radius
	for node in get_tree().get_nodes_in_group("npc_character"):
		if not (node is HumanoidCharacter):
			continue
		var candidate: HumanoidCharacter = node
		if candidate == self or candidate.life_state != NpcRules.LifeState.ALIVE:
			continue
		if not has_hostility_with(candidate):
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best_target = candidate
	return best_target


func _try_start_self_defense(attacker: HumanoidCharacter) -> void:
	if attacker == null or attacker.life_state != NpcRules.LifeState.ALIVE:
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	assign_attack_target(attacker, false, false, false)
	_move_target = attacker.get_combat_approach_position(self)
	_has_move_target = true


func _notify_defensive_allies_of_attack(attacker: HumanoidCharacter) -> void:
	for node in get_tree().get_nodes_in_group("npc_character"):
		if not (node is HumanoidCharacter):
			continue
		var ally: HumanoidCharacter = node
		if ally == self:
			continue
		ally._respond_to_ally_under_attack(self, attacker)


func _notify_defensive_allies_of_engagement(target: HumanoidCharacter) -> void:
	for node in get_tree().get_nodes_in_group("npc_character"):
		if not (node is HumanoidCharacter):
			continue
		var ally: HumanoidCharacter = node
		if ally == self:
			continue
		ally._respond_to_ally_engagement(self, target)


func _respond_to_ally_under_attack(ally: HumanoidCharacter, attacker: HumanoidCharacter) -> void:
	if ally == null or attacker == null:
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	if combat_stance == NpcRules.CombatStance.PASSIVE:
		return
	if not _should_defend_ally(ally):
		return
	if global_position.distance_to(ally.global_position) > assist_scan_radius:
		return
	mark_hostile(attacker)
	attacker.mark_hostile(self)
	assign_attack_target(attacker, false, false, false)


func _respond_to_ally_engagement(ally: HumanoidCharacter, target: HumanoidCharacter) -> void:
	if ally == null or target == null:
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	if combat_stance == NpcRules.CombatStance.PASSIVE:
		return
	if not _should_defend_ally(ally):
		return
	if global_position.distance_to(ally.global_position) > assist_scan_radius:
		return
	if target.life_state != NpcRules.LifeState.ALIVE:
		return
	mark_hostile(target)
	target.mark_hostile(self)
	assign_attack_target(target, false, false, false)


func _clear_all_active_orders() -> void:
	stop_mining_assignment()
	stop_container_interaction()
	stop_trade_interaction()
	stop_conversation_interaction()
	stop_attack_assignment()
	stop_heal_assignment()
	stop_finish_off_assignment()
	stop_carry_assignment()
	_current_order_type = OrderType.NONE
	_has_move_target = false


func force_kill(_attacker: HumanoidCharacter = null) -> void:
	blood = 0.0
	hp = -max_hp * NpcRules.DEATH_HP_FACTOR
	_enter_dead_state()


func drop_carried_character() -> void:
	if _carried_character == null:
		return
	var carried := _carried_character
	_carried_character = null
	carried._carried_by = null
	carried.collision_layer = carried._stored_collision_layer
	carried.collision_mask = carried._stored_collision_mask
	carried.global_position = global_position - transform.basis.z * 0.9
	carried.velocity = Vector3(transform.basis.z.x, 0.0, transform.basis.z.z) * 0.5
	carried._enter_downed_state(carried.life_state == NpcRules.LifeState.DEAD)
	state_changed.emit()


func _attach_carried_character(target_character: HumanoidCharacter) -> void:
	_carried_character = target_character
	target_character._carried_by = self
	target_character._stored_collision_layer = target_character.collision_layer
	target_character._stored_collision_mask = target_character.collision_mask
	target_character.collision_layer = 0
	target_character.collision_mask = 0
	target_character.velocity = Vector3.ZERO
	target_character.stop_attack_assignment()
	target_character.stop_heal_assignment()
	target_character.stop_finish_off_assignment()
	target_character.stop_carry_assignment()
	target_character._update_carried_transform()
	state_changed.emit()


func _update_carried_transform() -> void:
	if _carried_by == null:
		return
	var offset := Vector3(0.0, 1.8, 0.4)
	global_position = _carried_by.global_position + _carried_by.transform.basis * offset
	rotation = Vector3(0.0, _carried_by.rotation.y, deg_to_rad(88.0))


func _enter_downed_state(is_dead: bool) -> void:
	if _carried_by != null:
		return
	_has_move_target = false
	_downed_is_settled = false
	velocity = transform.basis.z * -0.8
	velocity.y = 0.0
	_downed_target_rotation_z = deg_to_rad(90.0 if _rng.randf() > 0.5 else -90.0)
	if is_dead:
		_downed_target_rotation_z *= 1.0


func _restore_from_downed_state() -> void:
	if _carried_by != null:
		return
	_downed_is_settled = false
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	collision_layer = _stored_collision_layer
	collision_mask = _stored_collision_mask
	_show_world_notice("Recovered", Color(0.5, 1.0, 0.65, 1.0))


func _show_world_notice(message: String, color: Color = Color(1.0, 0.28, 0.28, 1.0), lifetime: float = 1.0, rise_height: float = 0.4) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var notice = WORLD_TEXT_NOTICE_SCENE.instantiate()
	tree.current_scene.add_child(notice)
	if notice.has_method("setup"):
		notice.setup(global_position + Vector3(0.0, overhead_text_height, 0.0), message, color, lifetime, rise_height)


func _is_working() -> bool:
	return _current_order_type == OrderType.MINE and _mining_active


func _get_best_bandage_definition() -> ItemDefinition:
	var best_definition: ItemDefinition
	var best_power := -1.0
	for entry in inventory.entries:
		if not can_use_bandage_item(entry.definition):
			continue
		if entry.definition.bandage_power > best_power:
			best_definition = entry.definition
			best_power = entry.definition.bandage_power
	return best_definition
