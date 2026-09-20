extends Node

## Demo integration, not a synthetic controller fixture: late creation through
## the production startup, real GECS identity/hunger, attack dispatcher and
## completed retreat. Furnished-jail custody lives in validate_law_order_jail.
const DEMO_WORLD := "res://scenes/worlds/demo_world/demo_world.tscn"
var _world: Node3D
var _member: HumanoidCharacter
var _target: HumanoidCharacter
var _failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	_world = load(DEMO_WORLD).instantiate()
	_world.auto_open_character_creator = false
	get_tree().root.add_child(_world)
	get_tree().current_scene = _world
	if not await _wait_for(_navigation_ready, 60.0):
		_fail("Demo navigation/bootstrap did not become ready in 60 seconds")
		await _finish()
		return
	var nav = BootstrapContext.service(&"world_navigation")
	_expect(nav != null and nav.baked_tile_count() > 0, "demo has usable tiled navigation, not an empty released gate")
	_member = _world.spawn_default_character()
	_expect(_member != null, "production late character creation returns a member")
	if _member == null:
		await _finish()
		return
	var gecs = BootstrapContext.service(&"gecs_world")
	_expect(await _wait_for(func(): return gecs.get_actor_by_stable_id(_member.stable_id) == _member, 5.0), "actual generated stable_id maps back to this created member")
	_expect(_member.stable_id.begins_with("player.created.") and _member.shows_hunger_vital(), "late-created member owns generated identity and hunger vital")
	var town := _world.get_node_or_null("Zones/DemoZone/Towns/SurfCity") as Node3D
	_expect(town != null, "Surf City target town exists")
	if town == null:
		await _finish()
		return
	var realization = BootstrapContext.service(&"population_realization")
	if realization != null:
		realization.set_process(false)
	var settlements = BootstrapContext.service(&"settlements")
	if settlements == null:
		settlements = get_tree().get_first_node_in_group("settlement_controller")
	for slot in settlements.get_assignment_slots_for_realization(town.get_settlement_id()):
		if bool(slot.get("filled", false)):
			settlements.realize_assignment_slot(town.get_settlement_id(), str(slot.assignment_domain), str(slot.slot_id))
	# This is setup, not a travel assertion: move the late player to the
	# intended town and wait for a real roster target instead of a 6s guess.
	_member.global_position = town.global_position + Vector3(4, 0.5, 4)
	if not await _wait_for(func():
		_target = _find_town_target(town)
		return _target != null and not town.get_guard_actors().is_empty(), 20.0):
		_fail("Surf City did not realize a living NPC and guard subjects")
		await _finish()
		return
	var map := _world.get_world_3d().navigation_map
	_member.global_position = NavigationServer3D.map_get_closest_point(map, _target.global_position + Vector3(3, 0, 0))
	_member.velocity = Vector3.ZERO
	_world.get_node("PartyManager").select_only(_member)
	var dispatcher = BootstrapContext.service(&"world_interaction")
	dispatcher._assign_attack_to_selection(_target)
	_expect(await _wait_for(func(): return _member.is_in_combat(), 10.0), "production attack dispatcher engages the real town target")
	var law = BootstrapContext.service(&"law_order")
	_expect(law != null and not law.warrants.is_empty(), "dispatcher assault creates a warrant")
	var retreat := NavigationServer3D.map_get_closest_point(map, _member.global_position + Vector3(12, 0, 0))
	var retreat_start := _member.global_position
	_member.set_move_target(retreat)
	_expect(await _wait_for(func(): return not _member.has_move_target(), 15.0), "retreat movement must terminate")
	var retreat_delta := _member.global_position - retreat
	_expect(_member.global_position.distance_to(retreat_start) > 1.0 and Vector2(retreat_delta.x, retreat_delta.z).length() <= _member.navigation_target_desired_distance + 0.05 and absf(retreat_delta.y) < 0.8, "retreat physically arrives, not merely clears an order after partial movement")
	print("DEMO_RETREAT start=%s target=%s final=%s" % [retreat_start, retreat, _member.global_position])
	_expect(_member.get_current_combat_target() != _target, "retreat must not reacquire its old enemy")
	var entity = gecs.get_actor_entity(_member)
	_expect(entity != null and entity.get_component(CGameActorVitals) != null, "late-created actor retains authoritative vitals after player orders")
	# Demo facilities now instantiate deliberately unfurnished catalog shells:
	# settlement_jail.tscn has no cells. Do not synthesize a cage in the demo
	# or silently bypass placement. Real guard carrying, cell admission and
	# IdleToLay/no-ragdoll are covered by validate_law_order_jail.gd's
	# _validate_witnessed_theft_jail_release in its authored furnished jail.
	await _finish()

func _navigation_ready() -> bool:
	var nav = BootstrapContext.service(&"world_navigation")
	return nav != null and nav._mode != 0 and nav.is_idle() and not nav.is_initial_navigation_pending() and not get_tree().paused and NavigationServer3D.map_get_iteration_id(_world.get_world_3d().navigation_map) > 0

func _find_town_target(town: Node) -> HumanoidCharacter:
	for candidate in get_tree().get_nodes_in_group("humanoid_character"):
		if candidate is HumanoidCharacter and town.is_ancestor_of(candidate) and candidate.life_state == NpcRules.LifeState.ALIVE and not candidate.is_player_party_member():
			return candidate
	return null

func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		if condition.call():
			return true
	return false

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)

func _finish() -> void:
	get_tree().paused = false
	_world.queue_free()
	await get_tree().process_frame
	print("DEMO_FLOW_%s failures=%d" % ["OK" if _failures.is_empty() else "FAILED", _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)
