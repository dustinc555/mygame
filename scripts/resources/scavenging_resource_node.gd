extends StaticBody3D

class_name ScavengingResourceNode

const WORLD_ITEM_SCENE = preload("res://scenes/world/items/world_item.tscn")

enum PileSize {
	SMALL,
	MEDIUM,
	LARGE,
}

@export var display_name := "Scrap Pile"
@export_enum("Small", "Medium", "Large") var pile_size: int = PileSize.MEDIUM
@export var scavenging_difficulty := 10
@export var slow_scavenge_seconds := 12.0
@export var fast_scavenge_seconds := 5.0
@export var levels_to_fast_speed := 30
@export var randomize_charges_on_ready := true
@export var current_charges := -1
@export_range(0.0, 1.0, 0.01) var min_useful_chance := 0.05
@export_range(0.0, 1.0, 0.01) var max_useful_chance := 0.82
@export_range(0.0, 1.0, 0.01) var junk_chance_on_failure := 0.55
@export_range(0.0, 1.0, 0.01) var base_rare_chance := 0.03
@export_range(0.0, 1.0, 0.01) var max_rare_chance := 0.22
@export var robotics_difficulty := 10
@export var scavenge_noise_radius := 10.0
@export var interaction_radius := 1.8
@export var slot_distance := 2.4
@export var slot_count := 6
@export var resource_node_id := ""
@export var show_charge_count := false:
	set(value):
		show_charge_count = value
		_update_label()
@export var useful_loot: Array[Resource] = []
@export var rare_loot: Array[Resource] = []
@export var junk_loot: Array[Resource] = []

const STRENGTH_SPEED_BONUS_CAP := 0.08
const STRENGTH_SPEED_BONUS_CURVE := 45.0

var _assigned_slots: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _label: Label3D


func _ready() -> void:
	add_to_group("scavenging_resource")
	_rng.randomize()
	_label = get_node_or_null("Label3D") as Label3D
	if randomize_charges_on_ready or current_charges < 0:
		_roll_charges()
	_update_label()


func get_world_context_actions(_actor = null) -> Array:
	if is_depleted():
		return [{"key": "depleted", "label": "Depleted"}]
	return [{"key": "scavenge", "label": "Scavenge"}]


func perform_world_context_action(key: String, actors: Array = []) -> String:
	if key == "depleted" or is_depleted():
		return "Depleted"
	if key != "scavenge":
		return ""
	var assigned := 0
	for actor in actors:
		if actor != null and actor.has_method("assign_scavenging_resource"):
			actor.assign_scavenging_resource(self)
			assigned += 1
	return "Select someone to scavenge" if assigned == 0 else ""


func get_scavenging_position(member: HumanoidCharacter) -> Vector3:
	var slot_index := _get_slot_index(member)
	var angle := TAU * float(slot_index) / float(max(slot_count, 1))
	return global_position + Vector3(cos(angle), 0.0, sin(angle)) * slot_distance


func get_resource_progress_key() -> String:
	return resource_node_id.strip_edges()


func register_scavenger(member: HumanoidCharacter) -> void:
	_get_slot_index(member)


func release_scavenger(member: HumanoidCharacter) -> void:
	_assigned_slots.erase(member.get_instance_id())


func is_depleted() -> bool:
	return current_charges <= 0


func set_show_charge_count(value: bool) -> void:
	show_charge_count = value
	_update_label()


func reset_charges() -> void:
	_roll_charges()
	_update_label()


func get_scavenging_level(actor) -> int:
	if actor != null and actor.has_method("get_skill_level"):
		return actor.get_skill_level(SkillRules.LABOR_SCAVENGING)
	return SkillRules.get_default_level(SkillRules.LABOR_SCAVENGING)


func get_effective_scavenge_duration(actor) -> float:
	var relative_level := maxf(float(get_scavenging_level(actor) - scavenging_difficulty), 0.0)
	var speed_ratio := 1.0 if levels_to_fast_speed <= 0 else clampf(relative_level / float(levels_to_fast_speed), 0.0, 1.0)
	var skill_seconds := lerpf(slow_scavenge_seconds, fast_scavenge_seconds, speed_ratio)
	var strength_bonus := _get_strength_speed_bonus(actor)
	return maxf(skill_seconds / (1.0 + strength_bonus), 0.1)


func get_useful_loot_chance(actor) -> float:
	var scavenging_level := float(get_scavenging_level(actor))
	var perception_bonus := _get_skill_bonus(actor, SkillRules.ATTRIBUTE_PERCEPTION, 5.0, 40.0)
	var dexterity_bonus := _get_skill_bonus(actor, SkillRules.ATTRIBUTE_DEXTERITY, 4.0, 40.0)
	var score := scavenging_level + perception_bonus + dexterity_bonus
	var ratio := clampf((score - float(scavenging_difficulty) + 20.0) / 55.0, 0.0, 1.0)
	return lerpf(min_useful_chance, max_useful_chance, ratio)


func get_rare_loot_chance(actor) -> float:
	if rare_loot.is_empty():
		return 0.0
	var robotics_bonus := _get_skill_bonus_above(actor, SkillRules.TECH_ROBOTICS, robotics_difficulty, max_rare_chance - base_rare_chance, 40.0)
	var perception_bonus := _get_skill_bonus(actor, SkillRules.ATTRIBUTE_PERCEPTION, 0.04, 45.0)
	return clampf(base_rare_chance + robotics_bonus + perception_bonus, 0.0, max_rare_chance)


func complete_scavenge_attempt(actor) -> Dictionary:
	if is_depleted():
		_update_label()
		return {"message": "Depleted", "item": null, "quantity": 0, "depleted": true, "useful": false, "dropped": false}
	current_charges = maxi(0, current_charges - 1)
	var result := _roll_loot(actor)
	var definition := result.get("item") as ItemDefinition
	var quantity := int(result.get("quantity", 1))
	var delivery := ""
	if definition != null and quantity > 0:
		delivery = _deliver_loot(actor, definition, quantity)
	var message := _build_result_message(definition, quantity, delivery, bool(result.get("useful", false)))
	_update_label()
	return {
		"message": message,
		"item": definition,
		"quantity": quantity if definition != null else 0,
		"depleted": is_depleted(),
		"useful": bool(result.get("useful", false)),
		"dropped": delivery == "dropped",
	}


func _roll_charges() -> void:
	var charge_range := _get_charge_range()
	current_charges = _rng.randi_range(charge_range.x, charge_range.y)


func _get_charge_range() -> Vector2i:
	match pile_size:
		PileSize.SMALL:
			return Vector2i(1, 2)
		PileSize.LARGE:
			return Vector2i(4, 7)
		_:
			return Vector2i(2, 4)


func _roll_loot(actor) -> Dictionary:
	var useful_chance := get_useful_loot_chance(actor)
	if _rng.randf() <= useful_chance and not useful_loot.is_empty():
		if _rng.randf() <= get_rare_loot_chance(actor):
			return {"item": _pick_loot(rare_loot), "quantity": 1, "useful": true}
		return {"item": _pick_loot(useful_loot), "quantity": 1, "useful": true}
	if _rng.randf() <= junk_chance_on_failure and not junk_loot.is_empty():
		return {"item": _pick_loot(junk_loot), "quantity": 1, "useful": false}
	return {"item": null, "quantity": 0, "useful": false}


func _pick_loot(loot: Array[Resource]) -> ItemDefinition:
	if loot.is_empty():
		return null
	return loot[_rng.randi_range(0, loot.size() - 1)] as ItemDefinition


func _deliver_loot(actor, definition: ItemDefinition, quantity: int) -> String:
	var actor_inventory: InventoryData = actor.inventory if actor != null and actor.get("inventory") != null else null
	if actor_inventory != null and actor_inventory.add_item_count(definition, quantity):
		return "inventory"
	_drop_loot(definition, quantity)
	return "dropped"


func _drop_loot(definition: ItemDefinition, quantity: int) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var parent := tree.current_scene if tree.current_scene != null else get_parent()
	if parent == null:
		return
	var world_item := WORLD_ITEM_SCENE.instantiate() as WorldItem
	parent.add_child(world_item)
	world_item.setup(definition, quantity)
	var angle := _rng.randf_range(0.0, TAU)
	var distance := _rng.randf_range(1.0, 1.8)
	world_item.global_position = global_position + Vector3(cos(angle) * distance, 0.08, sin(angle) * distance)


func _build_result_message(definition: ItemDefinition, quantity: int, delivery: String, useful: bool) -> String:
	if definition == null:
		return "Found nothing useful"
	var prefix := "Recovered" if useful else "Found"
	var item_name := definition.display_name if quantity <= 1 else "%s x%d" % [definition.display_name, quantity]
	if delivery == "dropped":
		return "%s %s, dropped nearby" % [prefix, item_name]
	return "%s %s" % [prefix, item_name]


func _update_label() -> void:
	if _label == null:
		return
	if is_depleted():
		_label.text = "%s\nDepleted" % display_name
	elif show_charge_count:
		_label.text = "%s\n%d charges" % [display_name, current_charges]
	else:
		_label.text = display_name


func _get_strength_speed_bonus(actor) -> float:
	return _get_skill_bonus(actor, SkillRules.ATTRIBUTE_STRENGTH, STRENGTH_SPEED_BONUS_CAP, STRENGTH_SPEED_BONUS_CURVE)


func _get_skill_bonus(actor, skill_id: String, cap: float, curve: float) -> float:
	if actor == null or not actor.has_method("get_skill_level"):
		return 0.0
	var level := maxf(float(actor.get_skill_level(skill_id) - SkillRules.DEFAULT_LEVEL), 0.0)
	return SkillRules.get_diminishing_bonus(level, cap, curve)


func _get_skill_bonus_above(actor, skill_id: String, threshold: int, cap: float, curve: float) -> float:
	if actor == null or not actor.has_method("get_skill_level"):
		return 0.0
	var level := maxf(float(actor.get_skill_level(skill_id) - threshold), 0.0)
	return SkillRules.get_diminishing_bonus(level, cap, curve)


func _get_slot_index(member: HumanoidCharacter) -> int:
	var key: int = member.get_instance_id()
	if _assigned_slots.has(key):
		return _assigned_slots[key]

	var used: Array[int] = []
	for value in _assigned_slots.values():
		used.append(value)

	var best_slot := 0
	var best_distance := INF
	for slot_index in range(slot_count):
		if used.has(slot_index):
			continue
		var slot_position := _slot_position_from_index(slot_index)
		var distance: float = member.global_position.distance_squared_to(slot_position)
		if distance < best_distance:
			best_distance = distance
			best_slot = slot_index

	if best_distance == INF:
		for slot_index in range(slot_count):
			var slot_position := _slot_position_from_index(slot_index)
			var distance: float = member.global_position.distance_squared_to(slot_position)
			if distance < best_distance:
				best_distance = distance
				best_slot = slot_index

	_assigned_slots[key] = best_slot
	return best_slot


func _slot_position_from_index(slot_index: int) -> Vector3:
	var angle := TAU * float(slot_index) / float(max(slot_count, 1))
	return global_position + Vector3(cos(angle), 0.0, sin(angle)) * slot_distance
