extends Resource

class_name CombatAttackAnimation

@export var attack_id := ""
@export var animation_names: PackedStringArray = PackedStringArray()
@export var weight := 1.0
@export_range(0.0, 1.0, 0.01) var impact_ratio := 0.45
@export var hit_reaction_names: PackedStringArray = PackedStringArray()


func get_animation_names() -> Array[String]:
	var result: Array[String] = []
	for animation_name in animation_names:
		result.append(String(animation_name))
	return result


func get_hit_reaction_names() -> Array[String]:
	var result: Array[String] = []
	for animation_name in hit_reaction_names:
		result.append(String(animation_name))
	return result


func has_required_animations(animation_player: AnimationPlayer) -> bool:
	if animation_player == null:
		return false
	for animation_name in animation_names:
		if not animation_player.has_animation(String(animation_name)):
			return false
	return true
