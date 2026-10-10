class_name RustdeadHumanoidCharacter
extends HumanoidCharacter

const RUSTDEAD_RACE := preload("res://features/actors/resources/character_races/rustdead.tres")
const RUSTDEAD_TIER_LIBRARY := preload("res://features/actors/projection/rustdead/rustdead_tier_library.gd")

@export var fresh_skin_color := Color(0.64, 0.19, 0.16, 1.0)
@export_range(0.05, 30.0, 0.05, "suffix:s") var cinder_burn_duration_seconds := 2.0
@export var rustdead_tier_definition: Resource
@export var rustdead_tier_id := "fresh"
@export_range(0.0, 2.0, 0.01) var rustdead_passive_bonus := 0.2

# Only the fire effect is transient. DEAD is the durable burned state: Rustdead
# cannot reach it through ordinary wounds, including while simulated off-screen.
var _cinder_burn_remaining := 0.0


func _ready() -> void:
	set_rustdead_tier_definition(rustdead_tier_definition)
	appearance_data = appearance_data.make_copy() if appearance_data != null else CharacterAppearanceData.new()
	appearance_data.character_race = RUSTDEAD_RACE
	if not appearance_data.skin_color_customized:
		appearance_data.skin_color_customized = true
		appearance_data.skin_color = fresh_skin_color
	appearance_data.eyebrow_style = null
	super._ready()


func _create_body_projection() -> BodyProjection:
	return RustdeadBodyProjection.new()


func _process(delta: float) -> void:
	super._process(delta)
	if _cinder_burn_remaining <= 0.0:
		return
	_cinder_burn_remaining = maxf(0.0, _cinder_burn_remaining - delta)
	var body := get_body_projection() as RustdeadBodyProjection
	if body != null:
		body.update_cinder_burn_visuals(_cinder_burn_remaining, cinder_burn_duration_seconds)
		if _cinder_burn_remaining <= 0.0:
			body.finish_cinder_burn_visuals()


func requires_fire_to_die() -> bool:
	return true


func _create_actor_capabilities() -> void:
	super._create_actor_capabilities()
	get_vitals().fire_only_death = true


func can_be_destroyed_by_cinder() -> bool:
	return is_downed_state() and not is_cinder_burned() and not is_fire_destruction_in_progress()


func begin_cinder_burn(_attacker: Node = null) -> bool:
	if not can_be_destroyed_by_cinder():
		return false
	_cinder_burn_remaining = maxf(0.05, cinder_burn_duration_seconds)
	# The normal downed->dead observer preserves the existing ragdoll.
	# Never rebuild or move the body when the flask ignites it.
	get_vitals().set_life_state(NpcRules.LifeState.DEAD)
	stop_movement()
	var body := get_body_projection() as RustdeadBodyProjection
	if body != null:
		body.begin_cinder_burn_visuals()
		body.spawn_cinder_burn_effect(_cinder_burn_remaining, cinder_burn_duration_seconds)
	state_changed.emit()
	return true


func is_fire_destruction_in_progress() -> bool:
	return _cinder_burn_remaining > 0.0


func is_cinder_burned() -> bool:
	return life_state == NpcRules.LifeState.DEAD


func has_cinder_burned_visuals() -> bool:
	var body := get_body_projection() as RustdeadBodyProjection
	return body != null and body.has_cinder_burned_visuals()


func set_rustdead_tier_definition(tier_definition: Resource) -> void:
	rustdead_tier_definition = tier_definition if tier_definition != null else RUSTDEAD_TIER_LIBRARY.get_tier_by_id(rustdead_tier_id)
	rustdead_tier_id = str(rustdead_tier_definition.call("get_id"))
	rustdead_passive_bonus = maxf(0.0, float(rustdead_tier_definition.get("passive_bonus")))


func get_rustdead_tier_definition() -> Resource:
	return rustdead_tier_definition


func get_rustdead_tier_id() -> String:
	return rustdead_tier_id


func get_rustdead_passive_bonus() -> float:
	return rustdead_passive_bonus
