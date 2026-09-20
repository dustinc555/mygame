extends GameCombatResolutionSystem

## Test-only RNG control at the real synchronous combat boundaries. Bootstrap
## installs this subclass in the ordinary system slot before GECS initialization.
## All eligibility, slots, timing, damage, law and presentation remain inherited.
## Never seed a physics/process callback: other systems can consume that draw.
const ROLL_SEED := 3
var impact_seed := ROLL_SEED
var impact_boundaries := 0


static func configure_controller(node: Node) -> void:
	if node is GecsWorldController:
		node.set("_combat_resolution_system_script", load("res://tests/validation/helpers/law_combat_resolution_fixture.gd"))


func _start_action(action, actor: Node, target_actor: Node, target_actor_id: String, cfg, spec: Dictionary) -> void:
	seed(ROLL_SEED)
	super._start_action(action, actor, target_actor, target_actor_id, cfg, spec)


func _resolve_action_impact(index: int, nodes: Array, identities: Array, spatials: Array, vitals: Array, configs: Array, actions: Array, slots: Array, actor_index_by_id: Dictionary) -> void:
	# No await, injected damage, changed probability, or retry. Even a disabled
	# damage commit in the parent must still fail the positive-impact oracle.
	seed(impact_seed)
	impact_boundaries += 1
	super._resolve_action_impact(index, nodes, identities, spatials, vitals, configs, actions, slots, actor_index_by_id)


func _roll_initiative(actor_id: String, partner_id: String, actor_index: int, partner_index: int, configs: Array) -> String:
	seed(ROLL_SEED)
	return super._roll_initiative(actor_id, partner_id, actor_index, partner_index, configs)


static func native_draws() -> Vector2:
	seed(ROLL_SEED)
	return Vector2(randf(), randf())
