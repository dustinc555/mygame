extends Resource

class_name CombatAnimationSet

@export var stance_id := "unarmed"
@export var idle_animation_name := ""
@export var block_animation_name := ""
@export var fallback_hit_reaction_names: PackedStringArray = PackedStringArray()
@export var attacks: Array = []


func choose_attack(animation_player: AnimationPlayer, rng: RandomNumberGenerator):
	var available_attacks: Array = []
	var total_weight := 0.0
	for attack in attacks:
		if attack == null or not attack.has_required_animations(animation_player):
			continue
		available_attacks.append(attack)
		total_weight += maxf(attack.weight, 0.0)
	if available_attacks.is_empty() or total_weight <= 0.0:
		return null
	var roll := rng.randf_range(0.0, total_weight)
	for attack in available_attacks:
		roll -= maxf(attack.weight, 0.0)
		if roll <= 0.0:
			return attack
	return available_attacks[available_attacks.size() - 1]


func get_hit_reaction_names(attack_id: String) -> Array[String]:
	for attack in attacks:
		if attack != null and attack.attack_id == attack_id:
			return attack.get_hit_reaction_names()
	var result: Array[String] = []
	for animation_name in fallback_hit_reaction_names:
		result.append(String(animation_name))
	return result


func get_all_animation_names() -> Array[String]:
	var result: Array[String] = []
	_add_unique_animation_name(result, idle_animation_name)
	_add_unique_animation_name(result, block_animation_name)
	for animation_name in fallback_hit_reaction_names:
		_add_unique_animation_name(result, String(animation_name))
	for attack in attacks:
		if attack == null:
			continue
		for animation_name in attack.animation_names:
			_add_unique_animation_name(result, String(animation_name))
		for animation_name in attack.hit_reaction_names:
			_add_unique_animation_name(result, String(animation_name))
	return result


func _add_unique_animation_name(animation_names: Array[String], animation_name: String) -> void:
	if animation_name.is_empty() or animation_names.has(animation_name):
		return
	animation_names.append(animation_name)
