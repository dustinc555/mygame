extends GutTest

const POST = preload("res://features/settlements/bridge/venues/facility_guard_post.gd")
const DUTY = preload("res://features/settlements/bridge/guard_duty_projection.gd")
const JOB_STATE = preload("res://features/settlements/sim/c_game_job_system_state.gd")

class Town extends Node3D:
	func get_settlement_id() -> String: return "canyon"

class Facility extends Node3D:
	var facility_id := "shop"
	func get_facility_id() -> String: return facility_id

class Grants extends Node:
	var granted := true
	func can_execute_assignment_duty(_actor: Node) -> bool: return granted

class Population extends Node:
	var lookups: Array[String] = []
	func get_live_actor(id: String) -> WorldActor:
		lookups.append(id)
		return null

class Guard extends WorldActor:
	var target := Vector3.INF
	var moves := 0
	var ordered := false
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func has_active_player_order() -> bool: return ordered
	func is_in_combat() -> bool: return false
	func set_move_target(destination: Vector3, _player: bool = true, _continue_order: bool = false) -> void:
		target = destination
		moves += 1
	func has_move_target() -> bool: return target.is_finite()
	func get_move_target() -> Vector3: return target
	func _clear_actor_move_target() -> void: target = Vector3.INF

func _fixture() -> Dictionary:
	var town := Town.new()
	add_child_autofree(town)
	var jobs := Grants.new()
	town.add_child(jobs)
	var guard := Guard.new()
	guard.stable_id = "guard"
	town.add_child(guard)
	var duty := DUTY.new()
	duty.assignments.guard = "town:canyon"
	return {"town": town, "jobs": jobs, "guard": guard, "duty": duty}

func _post(f: Dictionary, id: String, position: Vector3) -> FacilityGuardPost:
	var post := POST.new()
	post.post_id = id
	post.position = position
	f.town.add_child(post)
	f.duty.register_post(post)
	return post

func test_town_patrol_crosses_buildings_and_rotates_only_after_arrival_hold() -> void:
	var f := _fixture()
	var first := _post(f, "gate", Vector3(10, 0, 0))
	var second := _post(f, "jail", Vector3(20, 0, 0))
	first.hold_minutes = 5.0
	f.duty.step(f.guard, f.jobs, 100.0)
	f.duty.step(f.guard, f.jobs, 110.0)
	assert_eq(f.guard.moves, 1, "An unchanged commute must not repath")
	assert_eq(first.get_assigned_worker(), f.guard)
	f.guard.position = first.position
	f.duty.step(f.guard, f.jobs, 110.0)
	assert_almost_eq(-f.guard.global_basis.z, first.get_facing_direction(), Vector3.ONE * 0.001)
	assert_eq(f.duty.patrols.guard.leave_minute, 115.0)
	f.duty.step(f.guard, f.jobs, 114.0)
	assert_null(second.get_assigned_worker())
	f.duty.step(f.guard, f.jobs, 115.0)
	assert_null(first.get_assigned_worker())
	assert_eq(second.get_assigned_worker(), f.guard)
	f.duty.step(f.guard, f.jobs, 115.0)
	assert_eq(f.guard.target, second.position)

func test_private_posts_share_character_owner_not_building_or_town() -> void:
	var f := _fixture()
	var building := Facility.new()
	f.town.add_child(building)
	var private := POST.new()
	private.guard_scope = "Private Security"
	building.add_child(private)
	assert_eq(private.get_pool_key({"shop": "pearl"}), "character:pearl")
	private.employer_actor_id = "other"
	assert_eq(private.get_pool_key({"shop": "pearl"}), "character:other")
	f.duty.register_post(private)
	f.duty.step(f.guard, f.jobs, 0.0)
	assert_null(private.get_assigned_worker(), "Town guards cannot take private posts")
	f.duty.assignments.guard = "character:other"
	f.duty.step(f.guard, f.jobs, 0.0)
	assert_eq(private.get_assigned_worker(), f.guard)

func test_patrol_release_preserves_player_move_and_releases_occupancy() -> void:
	var f := _fixture()
	var post := _post(f, "gate", Vector3(10, 0, 0))
	f.duty.step(f.guard, f.jobs, 0.0)
	f.guard.ordered = true
	f.guard.target = Vector3(30, 0, 0)
	f.duty.step(f.guard, f.jobs, 1.0)
	assert_null(post.get_assigned_worker())
	assert_eq(f.guard.target, Vector3(30, 0, 0))
	assert_true(f.duty._claims.is_empty())

func test_unloaded_post_releases_owned_navigation_and_another_post_is_claimed() -> void:
	var f := _fixture()
	var first := _post(f, "gate", Vector3(10, 0, 0))
	var second := _post(f, "jail", Vector3(20, 0, 0))
	f.duty.step(f.guard, f.jobs, 0.0)
	f.duty.unregister_post(first)
	f.town.remove_child(first)
	assert_false(f.guard.has_move_target())
	f.duty.step(f.guard, f.jobs, 1.0)
	assert_eq(second.get_assigned_worker(), f.guard)
	first.free()

func test_saved_patrol_survives_initial_assignment_registration_and_gecs_roundtrip() -> void:
	var f := _fixture()
	var duty := DUTY.new()
	var saved := {"guard": {"post_id": "gate", "leave_minute": 120.0}}
	var component := JOB_STATE.new()
	component.apply_state({"guard_patrols": saved})
	duty.restore(component.to_state().guard_patrols, null)
	duty.set_settlement("canyon", {"assignment_slots": {"guard": {
		"assignment_domain": "employment", "role_id": "guard", "filled": true,
		"occupant_actor_id": "guard", "authority_scope": "settlement_authority"}}}, null)
	assert_eq(duty.patrols, saved)
	assert_eq(duty.assignments.guard, "town:canyon")
	var post := _post(f, "gate", Vector3.ZERO)
	duty.register_post(post)
	duty.step(f.guard, f.jobs, 110.0)
	assert_eq(duty.patrols.guard.leave_minute, 120.0, "Reload must not restart hold time")

func test_assignment_owner_change_releases_private_claim() -> void:
	var f := _fixture()
	var private := _post(f, "private", Vector3.ZERO)
	private.guard_scope = "Private Security"
	private.employer_actor_id = "pearl"
	f.duty.register_post(private)
	var state := {"facilities": {"shop": {"owner_role_id": "trader"}}, "assignment_slots": {
		"owner": {"facility_id": "shop", "role_id": "trader", "filled": true, "occupant_actor_id": "pearl"},
		"guard": {"facility_id": "shop", "assignment_domain": "employment", "role_id": "guard", "filled": true, "occupant_actor_id": "guard"}}}
	f.duty.set_settlement("canyon", state, null)
	f.duty.step(f.guard, f.jobs, 0.0)
	assert_eq(private.get_assigned_worker(), f.guard)
	state.assignment_slots.owner.occupant_actor_id = "new_owner"
	f.duty.set_settlement("canyon", state, null)
	assert_null(private.get_assigned_worker())
	assert_eq(f.duty.assignments.guard, "character:new_owner")

func test_facing_uses_rotated_parent_and_stays_horizontal() -> void:
	var parent := Node3D.new()
	add_child_autofree(parent)
	parent.rotation.y = PI * 0.5
	var post := POST.new()
	parent.add_child(post)
	post.rotation.y = PI * 0.5
	assert_true(post.has_method("get_facing_direction"), "Posts must expose authored facing")
	if not post.has_method("get_facing_direction"):
		return
	assert_almost_eq(post.get_facing_direction(), Vector3(0, 0, -1), Vector3.ONE * 0.001)

func test_mercenary_uses_employers_private_posts_not_town_or_other_owner() -> void:
	var f := _fixture()
	var town_post := _post(f, "public", Vector3.ZERO)
	var other_post := _post(f, "other", Vector3.ZERO)
	other_post.guard_scope = "Private Security"
	other_post.employer_actor_id = "other"
	f.duty.register_post(other_post)
	var private := _post(f, "shop_post", Vector3(3, 0, 0))
	private.guard_scope = "Private Security"
	private.employer_actor_id = "pearl"
	private.rotation.y = PI * 0.5
	f.duty.register_post(private)
	var state := {"facilities": {"shop": {"owner_role_id": "trader"}}, "assignment_slots": {
		"owner": {"facility_id": "shop", "role_id": "trader", "filled": true, "occupant_actor_id": "pearl"},
		"mercenary": {"facility_id": "shop", "assignment_domain": "employment", "role_id": "mercenary", "filled": true, "occupant_actor_id": "guard"}}}
	f.duty.set_settlement("canyon", state, null)
	assert_eq(f.duty.assignments.get("guard", ""), "character:pearl")
	f.duty.step(f.guard, f.jobs, 0.0)
	assert_eq(private.get_assigned_worker(), f.guard)
	assert_null(town_post.get_assigned_worker())
	assert_null(other_post.get_assigned_worker())
	assert_eq(f.guard.target, private.global_position)
	f.guard.global_position = private.global_position
	f.duty.step(f.guard, f.jobs, 1.0)
	assert_almost_eq(-f.guard.global_basis.z, private.get_facing_direction(), Vector3.ONE * 0.001)
	f.jobs.granted = false
	f.duty.step(f.guard, f.jobs, 2.0)
	assert_null(private.get_assigned_worker(), "Off-duty mercenaries release their spot")
	state.assignment_slots.mercenary.authority_scope = "settlement_authority"
	f.duty.set_settlement("canyon", state, null)
	assert_eq(f.duty.assignments.get("guard", ""), "character:pearl", "Mercenaries never become town guards through an authority flag")
	state.assignment_slots.erase("mercenary")
	f.duty.set_settlement("canyon", state, null)
	assert_false(f.duty.assignments.has("guard"), "Removing employment removes private duty")

func test_post_has_no_runtime_marker_geometry() -> void:
	var post := POST.new()
	add_child_autofree(post)
	await get_tree().process_frame
	assert_eq(post.get_child_count(true), 0)

func test_post_claim_is_exclusive_and_recovers_after_worker_freed() -> void:
	var post := POST.new()
	add_child_autofree(post)
	var first := WorldActor.new()
	var second := WorldActor.new()
	assert_true(post.claim_worker(first))
	assert_false(post.claim_worker(second))
	first.free()
	assert_true(post.claim_worker(second))
	post.release_worker(second)
	assert_true(post.is_available_for(null))
	second.free()

func test_population_work_is_bounded_and_round_robin() -> void:
	var duty := DUTY.new()
	var population := Population.new()
	add_child_autofree(population)
	for index in range(500):
		duty._order.append("guard.%d" % index)
	duty.tick(null, population, 0.0, 0.0)
	assert_eq(population.lookups, ["guard.0", "guard.1", "guard.2", "guard.3"])
	population.lookups.clear()
	duty.tick(null, population, 0.0, 0.01)
	assert_eq(population.lookups, ["guard.4", "guard.5", "guard.6", "guard.7"])

func test_full_pool_keeps_exclusive_post_without_restarting_navigation() -> void:
	var f := _fixture()
	var post := _post(f, "only", Vector3.ZERO)
	post.hold_minutes = 5.0
	f.duty.step(f.guard, f.jobs, 0.0)
	f.duty.step(f.guard, f.jobs, 5.0)
	assert_eq(post.get_assigned_worker(), f.guard)
	assert_eq(f.duty.patrols.guard.leave_minute, 10.0)
	assert_eq(f.guard.moves, 0)

func test_changed_scope_invalidates_old_claim_without_leaking_pool_entry() -> void:
	var f := _fixture()
	var post := _post(f, "gate", Vector3(10, 0, 0))
	f.duty.step(f.guard, f.jobs, 0.0)
	post.guard_scope = "Private Security"
	post.employer_actor_id = "pearl"
	f.duty.register_post(post)
	f.duty.step(f.guard, f.jobs, 1.0)
	assert_null(post.get_assigned_worker())
	assert_false(f.guard.has_move_target())
	assert_true(f.duty._pools["town:canyon"].is_empty())
	assert_eq(f.duty._pools["character:pearl"], [post])
