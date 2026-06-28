class_name RustdeadHumanoidCharacter
extends HumanoidCharacter

@export var fresh_skin_color := Color(0.64, 0.19, 0.16, 1.0)
@export var cinder_burn_duration_seconds := 2.0
@export var rustdead_tier_definition: Resource
@export var rustdead_tier_id := "fresh"
@export_range(0.0, 2.0, 0.01) var rustdead_passive_bonus := 0.2


## Rustdead do not stay dead without burning. The full cinder-burn destruction flow
## (burn timers, charred visuals, tier application) is pending restoration; downed
## rustdead accept the cinder action so the right-click menu offers it.
func requires_fire_to_die() -> bool:
	return true


func can_be_destroyed_by_cinder() -> bool:
	return is_downed_state()


func set_rustdead_tier_definition(tier_definition: Resource) -> void:
	rustdead_tier_definition = tier_definition
	if tier_definition != null:
		rustdead_tier_id = str(tier_definition.get("tier_id"))


func get_rustdead_tier_definition() -> Resource:
	return rustdead_tier_definition


func get_rustdead_tier_id() -> String:
	return rustdead_tier_id
