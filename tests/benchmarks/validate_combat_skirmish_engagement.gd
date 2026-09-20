extends Node

## Gameplay benchmark with combat/order correctness checks, not a unit test.
## Run: python3 tests/run_validation.py --benchmarks --filter combat_skirmish
## Normal scene startup preserves project autoloads, real actors and physics.
## Five-second warmup, 32-second sample, all 40 actors, minimum 40 FPS.
## Headless process-frame timing is not rendered gameplay FPS.
## Prior 40-actor run: avg 44.84 / min 20.72 FPS, worst frame 48.27 ms; editor open.

const SCENE_PATH := "res://scenes/test_levels/combat_skirmish_20v20_armory.tscn"
const FPS_FLOOR := 40.0
const WARMUP_SECONDS := 5.0
const SAMPLE_SECONDS := 32.0

var _elapsed := 0.0
var _sampling := false
var _sample_time := 0.0
var _frames := 0
var _min_fps := INF
var _worst_delta := 0.0
var _peak_in_combat := 0
var _peak_animated_actions := 0
# Player-order override check: mid-fight, order the whole party to retreat, then
# verify they disengage (no combat targets) while the order runs.
const ORDER_ISSUE_TIME := 8.0
const ORDER_CHECK_TIME := 12.0
var _order_issued := false
var _order_checked := false
var _ordered_members_still_fighting := -1
# Carry-order check: late in the run a living member is ordered to carry a downed
# body; by report time they must be carrying someone.
const CARRY_ORDER_TIME := 14.0
# Attack-order check: while the retreat order is still held, command one member to
# attack a specific raider — the attack must override the order suppression.
const ATTACK_ORDER_TIME := 10.5
const ATTACK_CHECK_TIME := 13.0
var _attack_member: Node = null
var _attack_member_id := ""
var _attack_target_id := ""
var _attack_impact: Dictionary = {}
var _floor_y := 0.0
var _attack_sequence_before := 0
var _retreat_orders: Dictionary = {}
var _carry_visual_verified := false
var _combat_idle_checked := false
var _combat_idle_seen := false
var _attack_result := "not_attempted"
const CARRY_DROP_TIME := 26.0
var _carry_member: Node = null
var _carry_result := "no_downed_target"
var _dropped_body: Node = null
var _drop_attempted := false
var _watched: Node3D
var _watch_last_pos := Vector3.ZERO
var _watch_total_moved := 0.0
var _watch_frames := 0
var _watch_frames_with_velocity := 0


func _ready() -> void:
	Engine.max_fps = 120
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("Could not load %s" % SCENE_PATH)
		get_tree().quit(1)
		return
	var arena := packed.instantiate()
	add_child(arena)
	var floor_shape := arena.get_node("Floor/CollisionShape3D") as CollisionShape3D
	_floor_y = floor_shape.to_global(Vector3(0.0, (floor_shape.shape as BoxShape3D).size.y * 0.5, 0.0)).y


func _process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		push_error("Combat sample contains a nonfinite/nonpositive frame delta")
		get_tree().quit(1)
		return
	_elapsed += delta
	if not _sampling:
		if _elapsed >= WARMUP_SECONDS:
			_sampling = true
		return
	_sample_time += delta
	_frames += 1
	if delta > 0.0:
		_min_fps = minf(_min_fps, 1.0 / delta)
	_worst_delta = maxf(_worst_delta, delta)
	if _frames % 30 == 0:
		_peak_in_combat = maxi(_peak_in_combat, _count_in_combat())
		_peak_animated_actions = maxi(_peak_animated_actions, _count_animated_actions())
	if not _order_issued and _sample_time >= ORDER_ISSUE_TIME:
		_order_issued = true
		for node in get_tree().get_nodes_in_group("party_member"):
			var member := node as WorldActor
			if member != null and member.life_state == NpcRules.LifeState.ALIVE:
				var destination := member.get_floor_aligned_origin_position(Vector3(member.global_position.x - 12.0, _floor_y, member.global_position.z))
				_retreat_orders[member.get_instance_id()] = {"actor": weakref(member), "destination": destination, "arrived": false}
				member.set_move_target(destination, true)
	for entry in _retreat_orders.values():
		var retreating = entry["actor"].get_ref()
		if is_instance_valid(retreating) and not retreating.has_move_target() and retreating.global_position.distance_to(entry["destination"]) <= 1.0:
			entry["arrived"] = true
	if not _combat_idle_checked and _sample_time >= 6.0:
		_combat_idle_checked = true
		var clip_counts := {}
		for node in get_tree().get_nodes_in_group("humanoid_character"):
			var fighter := node as WorldActor
			if fighter == null or fighter.life_state != NpcRules.LifeState.ALIVE or not fighter.is_in_combat():
				continue
			var fighter_body = fighter.get_body_projection()
			if fighter_body == null:
				continue
			var clip: String = fighter_body.get_current_clip()
			clip_counts[clip] = int(clip_counts.get(clip, 0)) + 1
		print("COMBAT_DIAG engaged_clips=%s" % [clip_counts])
		var combat_idles := int(clip_counts.get("Sword_Idle", 0)) + int(clip_counts.get("Unarmed_Combat_Idle", 0)) + int(clip_counts.get("Idle_Shield_Loop", 0))
		_combat_idle_seen = combat_idles > 0
	if _attack_member == null and _sample_time >= ATTACK_ORDER_TIME:
		var raider_target: Node = null
		for node in get_tree().get_nodes_in_group("world_actor"):
			var candidate := node as WorldActor
			if candidate != null and candidate.faction_name == "Raiders" and candidate.life_state == NpcRules.LifeState.ALIVE:
				raider_target = candidate
				break
		if raider_target != null:
			for node in get_tree().get_nodes_in_group("party_member"):
				var member := node as WorldActor
				if member != null and member.life_state == NpcRules.LifeState.ALIVE and member.has_active_player_order():
					var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
					var resolution := gecs.find_child("GameCombatResolutionSystem", true, false)
					if resolution == null or not resolution.has_signal("impact_resolved"):
						push_error("Skirmish benchmark requires authoritative impact attribution")
						get_tree().quit(1)
						return
					resolution.connect("impact_resolved", _on_attack_impact_resolved)
					_attack_member = member
					_attack_member_id = member.stable_id
					_attack_target_id = str(raider_target.get("stable_id"))
					var entity = gecs.get_actor_entity(member)
					_attack_sequence_before = entity.get_component(C_COMBAT_ACTION_SCRIPT).action_sequence
					_attack_result = "ordered"
					if not member.assign_attack_target(raider_target):
						_attack_result = "refused"
					break
	if _carry_member == null and _sample_time >= CARRY_ORDER_TIME:
		var downed_target: Node = null
		for node in get_tree().get_nodes_in_group("world_actor"):
			var candidate := node as HumanoidCharacter
			if candidate == null or not candidate.is_downed_state():
				continue
			downed_target = candidate
			# Prefer DEAD targets: unconscious ones can recover mid-carry-order,
			# which legitimately cancels the order and flakes the check.
			if candidate.life_state == NpcRules.LifeState.DEAD:
				break
		if downed_target != null:
			var nearest: HumanoidCharacter = null
			var nearest_distance := INF
			for node in get_tree().get_nodes_in_group("party_member"):
				var member := node as HumanoidCharacter
				if member == null or member.life_state != NpcRules.LifeState.ALIVE or member.is_carrying_someone() or member.is_carried():
					continue
				# Do not cancel the separate attack scenario before its actual hit.
				if member == _attack_member and _attack_result != "impact_completed":
					continue
				var distance := member.global_position.distance_to((downed_target as Node3D).global_position)
				if distance < nearest_distance:
					nearest_distance = distance
					nearest = member
			if nearest != null:
				nearest.assign_carry_target(downed_target)
				_carry_member = nearest
				_carry_result = "ordered"
	if not _drop_attempted and _sample_time >= CARRY_DROP_TIME and _carry_member != null and is_instance_valid(_carry_member):
		var carrier := _carry_member as HumanoidCharacter
		if carrier.is_carrying_someone():
			var carried := carrier.get_carry().get_carried_character() as HumanoidCharacter
			var carried_view := carried.get_body_projection() as HumanoidBodyProjection
			var offset := carried.global_position - carrier.global_position
			var expected := CarryPoseSolver.solve_carried_transform(carrier.get_body_projection(), carrier, carrier.get_carry().carry_pose_profile, carried_view, carried)
			_carry_visual_verified = carried_view != null and not carried_view.is_ragdoll_active() and offset.y >= 0.5 and offset.length() <= 4.0 and carried.global_position.distance_to(expected.origin) <= 0.2
			_dropped_body = carried
			carrier.drop_carried_character()
			_drop_attempted = true
			_carry_result = "carrying"
	if _carry_member != null and _carry_result == "ordered" and not _drop_attempted and is_instance_valid(_carry_member):
		var carry_actor := _carry_member as WorldActor
		if carry_actor.get_current_order_type() != InteractionCapability.ORDER_TYPE_CARRY and not carry_actor.is_carrying_someone():
			var target_ref = carry_actor.get_interaction().current_carry_target
			print("COMBAT_DIAG carry_dropped at t=%.1f: order=%d target=%s carried=%s in_combat=%s player_order=%s" % [
				_sample_time, carry_actor.get_current_order_type(), target_ref,
				carry_actor.is_carrying_someone(), carry_actor.is_in_combat(), carry_actor.has_active_player_order()])
			_carry_result = "order_dropped"
	if _order_issued and not _order_checked and _sample_time >= ORDER_CHECK_TIME:
		_order_checked = true
		_ordered_members_still_fighting = 0
		for node in get_tree().get_nodes_in_group("party_member"):
			var member := node as WorldActor
			if member != null and member.life_state == NpcRules.LifeState.ALIVE and member.has_active_player_order() and member.is_in_combat():
				_ordered_members_still_fighting += 1
	if _watched == null:
		for node in get_tree().get_nodes_in_group("world_actor"):
			if node is Node3D:
				_watched = node
				_watch_last_pos = _watched.global_position
				break
	elif is_instance_valid(_watched):
		_watch_frames += 1
		_watch_total_moved += (_watched.global_position - _watch_last_pos).length()
		_watch_last_pos = _watched.global_position
		var body := _watched as CharacterBody3D
		if body != null and body.velocity.length_squared() > 0.01:
			_watch_frames_with_velocity += 1
	if _sample_time >= SAMPLE_SECONDS:
		_report_and_quit()


func _on_attack_impact_resolved(attacker_id: String, target_id: String, sequence: int, outcome: String, damage: float) -> void:
	# Latch the immutable event: reaction state can disappear or be overwritten,
	# and a resolved dodge or refused attempt does not prove positive damage.
	if _attack_result != "ordered" or attacker_id != _attack_member_id or target_id != _attack_target_id:
		return
	if sequence <= _attack_sequence_before or not is_finite(damage) or damage <= 0.0:
		return
	_attack_impact = {"attacker_id": attacker_id, "target_id": target_id, "sequence": sequence, "outcome": outcome, "damage": damage}
	_attack_result = "impact_completed"


const C_COMBAT_STATE_SCRIPT := preload("res://features/combat/sim/c_game_combat_state.gd")
const C_COMBAT_ACTION_SCRIPT := preload("res://features/combat/sim/c_game_combat_action.gd")
const C_MOVEMENT_STATE_SCRIPT := preload("res://features/actors/sim/c_game_movement_state.gd")
const C_COMBAT_CONFIG_SCRIPT := preload("res://features/combat/sim/c_game_combat_config.gd")
const C_FACTION_SCRIPT := preload("res://features/actors/sim/c_game_actor_faction.gd")
const TARGETING_QUERY_COMPONENTS := {
	"node": preload("res://features/actors/bridge/c_game_actor_node.gd"),
	"identity": preload("res://features/actors/sim/c_game_actor_identity.gd"),
	"spatial": preload("res://features/actors/sim/c_game_actor_spatial.gd"),
	"vitals": preload("res://features/actors/sim/c_game_actor_vitals.gd"),
	"faction": preload("res://features/actors/sim/c_game_actor_faction.gd"),
	"config": preload("res://features/combat/sim/c_game_combat_config.gd"),
	"state": preload("res://features/combat/sim/c_game_combat_state.gd"),
	"slot": preload("res://features/combat/sim/c_game_combat_slot_state.gd"),
}


func _print_gecs_combat_diagnostics() -> void:
	var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	if gecs == null or gecs.world == null:
		print("COMBAT_DIAG gecs_world=absent")
		return
	var total_entities: int = gecs.world.entities.size()
	var with_state: int = gecs.world.query.with_all([C_COMBAT_STATE_SCRIPT]).execute().size()
	var with_config: int = gecs.world.query.with_all([C_COMBAT_CONFIG_SCRIPT]).execute().size()
	print("COMBAT_DIAG entities=%d with_combat_state=%d with_combat_config=%d" % [total_entities, with_state, with_config])
	var samples_by_faction := {}
	for entity in gecs.world.query.with_all([C_FACTION_SCRIPT]).execute():
		var faction = entity.get_component(C_FACTION_SCRIPT)
		var faction_id: String = str(faction.faction_id) if faction != null else "-"
		samples_by_faction[faction_id] = int(samples_by_faction.get(faction_id, 0)) + 1
		if samples_by_faction[faction_id] > 2:
			continue
		var config = entity.get_component(C_COMBAT_CONFIG_SCRIPT)
		var state = entity.get_component(C_COMBAT_STATE_SCRIPT)
		var spatial = entity.get_component(TARGETING_QUERY_COMPONENTS["spatial"])
		var vitals = entity.get_component(TARGETING_QUERY_COMPONENTS["vitals"])
		var slot = entity.get_component(TARGETING_QUERY_COMPONENTS["slot"])
		var action = entity.get_component(C_COMBAT_ACTION_SCRIPT)
		print("COMBAT_DIAG entity=%s pos=%s life=%s range=%s slot_state=%s slot_target=%s engage=%s leash=%s tempo_wait=%s action_active=%s cooldown=%s target=%s" % [
			entity.name.get_slice("_", entity.name.get_slice_count("_") - 1),
			str(spatial.world_position) if spatial != null else "-",
			str(vitals.life_state) if vitals != null else "-",
			str(config.attack_range) if config != null else "-",
			str(slot.slot_state) if slot != null else "-",
			str(slot.slot_target_actor_id).get_slice("_", 99) if slot != null else "-",
			str(slot.engage_distance) if slot != null else "-",
			str(slot.leash_distance) if slot != null else "-",
			str(slot.tempo_wait_remaining) if slot != null else "-",
			str(action.action_active) if action != null else "no_action",
			str(action.cooldown_remaining) if action != null else "-",
			str(state.system_target_actor_id).right(12) if state != null else "-",
		])
		var movement = entity.get_component(C_MOVEMENT_STATE_SCRIPT)
		var node_comp = entity.get_component(TARGETING_QUERY_COMPONENTS["node"])
		var actor_node := (node_comp.actor if node_comp != null else null) as WorldActor
		print("COMBAT_DIAG   move: has_component=%s sys_active=%s settled=%s desired_vel=%s | node: sys_active=%s desired=%s velocity=%s" % [
			str(movement != null),
			str(movement.system_movement_active) if movement != null else "-",
			str(movement.combat_settled) if movement != null else "-",
			str(movement.desired_velocity) if movement != null else "-",
			str(actor_node._system_move_active) if actor_node != null else "-",
			str(actor_node._system_desired_velocity) if actor_node != null else "-",
			str(actor_node.velocity) if actor_node != null else "-",
		])
		if actor_node != null:
			print("COMBAT_DIAG   node2: settled=%s on_floor=%s physics_on=%s process_mode=%s in_tree=%s has_move_target=%s" % [
				str(actor_node._system_move_settled),
				str(actor_node.is_on_floor()),
				str(actor_node.is_physics_processing()),
				str(actor_node.process_mode),
				str(actor_node.is_inside_tree()),
				str(actor_node._has_move_target),
			])
	var full_query_count: int = gecs.world.query.with_all(TARGETING_QUERY_COMPONENTS.values()).execute().size()
	print("COMBAT_DIAG entities_matching_full_targeting_query=%d" % full_query_count)


## Counts active GECS combat actions that carry animation clip names — proof the
## attack-spec hooks (get_system_combat_attack_spec) are feeding real animations.
func _count_animated_actions() -> int:
	var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	if gecs == null or gecs.world == null:
		return 0
	var animated := 0
	for entity in gecs.world.query.with_all([C_COMBAT_ACTION_SCRIPT]).execute():
		var action = entity.get_component(C_COMBAT_ACTION_SCRIPT)
		if action != null and bool(action.action_active) and not (action.action_names as PackedStringArray).is_empty():
			animated += 1
	return animated


func _count_in_combat() -> int:
	var in_combat := 0
	for node in get_tree().get_nodes_in_group("world_actor"):
		var actor := node as WorldActor
		if actor != null and actor.is_in_combat():
			in_combat += 1
	return in_combat


func _report_and_quit() -> void:
	var alive := 0
	var total := 0
	for node in get_tree().get_nodes_in_group("world_actor"):
		var actor := node as WorldActor
		if actor == null:
			continue
		total += 1
		if actor.life_state == NpcRules.LifeState.ALIVE:
			alive += 1
	_peak_in_combat = maxi(_peak_in_combat, _count_in_combat())
	var avg := float(_frames) / maxf(_sample_time, 0.0001)
	print("COMBAT_ENGAGEMENT_PROBE avg_fps=%.2f min_fps=%.2f worst_frame_ms=%.2f alive=%d total=%d peak_in_combat=%d" % [
		avg, _min_fps, _worst_delta * 1000.0, alive, total, _peak_in_combat])
	print("COMBAT_DIAG watched_moved_total=%.3f frames=%d frames_with_velocity=%d peak_animated_actions=%d" % [_watch_total_moved, _watch_frames, _watch_frames_with_velocity, _peak_animated_actions])
	for node in get_tree().get_nodes_in_group("party_member"):
		var member := node as PartyMember
		if member == null:
			continue
		var ring := member.get_node_or_null("SelectionRing") as MeshInstance3D
		print("COMBAT_DIAG selection: member=%s is_selected=%s is_focused=%s ring_found=%s ring_visible=%s ring_y=%.3f" % [
			member.name, member.is_selected, member.is_focused, ring != null, ring.visible if ring != null else false,
			ring.global_position.y if ring != null else -99.0])
		print("COMBAT_DIAG needs: shows_hunger=%s hunger=%.1f (%s) shows_fatigue=%s fatigue=%.1f (%s) hair=%s body_type=%s" % [
			member.shows_hunger_vital(), member.hunger, member.get_hunger_stage_label(),
			member.shows_fatigue_vital(), member.fatigue, member.get_fatigue_stage_label(),
			member.appearance_data != null and member.appearance_data.hair_style != null,
			str(member.appearance_data.visual_body_type) if member.appearance_data != null else "-"])
		break
	for node in get_tree().get_nodes_in_group("humanoid_character"):
		var sample := node as HumanoidCharacter
		if sample == null:
			continue
		var sample_body := sample.get_body_projection() as HumanoidBodyProjection
		var player := sample_body.get_primary_animation_player() if sample_body != null else null
		if player != null:
			var evadeish := PackedStringArray()
			for animation_name in player.get_animation_list():
				var lower := str(animation_name).to_lower()
				if lower.contains("dodge") or lower.contains("roll") or lower.contains("evade") or lower.contains("jump") or lower.contains("step"):
					evadeish.append(animation_name)
			print("COMBAT_DIAG anims: total=%d evade_candidates=%s" % [player.get_animation_list().size(), str(evadeish)])
			if evadeish.is_empty():
				print("COMBAT_DIAG anims full list: %s" % str(player.get_animation_list()))
		break
	var downed_samples := 0
	for node in get_tree().get_nodes_in_group("world_actor"):
		var actor := node as HumanoidCharacter
		if actor == null or actor.life_state == NpcRules.LifeState.ALIVE:
			continue
		var body := actor.get_body_projection() as HumanoidBodyProjection
		var lowest_bone_y := INF
		var bone_count := 0
		if body != null:
			for bone in body.find_children("*", "PhysicalBone3D", true, false):
				bone_count += 1
				lowest_bone_y = minf(lowest_bone_y, (bone as Node3D).global_position.y)
		print("COMBAT_DIAG downed: actor=%s life=%d actor_y=%.3f ragdoll=%s bones=%d lowest_bone_y=%s" % [
			actor.name, actor.life_state, actor.global_position.y,
			str(body.is_ragdoll_active()) if body != null else "no_body",
			bone_count, ("%.3f" % lowest_bone_y) if bone_count > 0 else "n/a"])
		downed_samples += 1
		if downed_samples >= 3:
			break
	_print_gecs_combat_diagnostics()
	var failures := 0
	if not is_finite(_min_fps) or _frames <= 0 or _sample_time < SAMPLE_SECONDS or _min_fps < FPS_FLOOR:
		push_error("Combat skirmish min FPS %.2f fell below floor %.2f" % [_min_fps, FPS_FLOOR])
		failures += 1
	if total != 40:
		push_error("20v20 workload must retain all 40 actor identities; got %d" % total)
		failures += 1
	if _peak_in_combat == 0 and alive == total:
		push_error("Combat never engaged: no actor entered combat and nobody died in a 20v20 skirmish")
		failures += 1
	print("COMBAT_DIAG ordered_members_still_fighting=%d (-1 = check never ran)" % _ordered_members_still_fighting)
	if _carry_member != null and not _drop_attempted and is_instance_valid(_carry_member):
		var carrier := _carry_member as HumanoidCharacter
		if carrier.is_carrying_someone():
			_carry_result = "carrying"
		else:
			_carry_result = "ordered_but_not_carrying"
	print("COMBAT_DIAG combat_idle_seen=%s" % _combat_idle_seen)
	if _combat_idle_checked and not _combat_idle_seen:
		push_error("No engaged fighter held a combat idle stance (fists up / weapon guard)")
		failures += 1
	print("COMBAT_DIAG attack_order=%s impact=%s" % [_attack_result, _attack_impact])
	if _attack_result != "impact_completed":
		push_error("Attack order failed: no completed impact against the commanded actor (%s)" % _attack_result)
		failures += 1
	print("COMBAT_DIAG carry_order=%s" % _carry_result)
	if _drop_attempted:
		if _dropped_body == null or not is_instance_valid(_dropped_body):
			print("COMBAT_DIAG drop: BODY FREED/INVALID")
			push_error("Dropped body vanished: node freed or invalid")
			failures += 1
		else:
			var dropped := _dropped_body as HumanoidCharacter
			var dropped_view := dropped.get_body_projection() as HumanoidBodyProjection
			var visual := dropped_view.get_visual_root() if dropped_view != null else null
			if dropped.is_carried() or (_carry_member as WorldActor).is_carrying_someone() or not dropped.is_inside_tree() or visual == null or not visual.visible:
				push_error("Drop must release both carry links and retain a visible body in the world")
				failures += 1
			var lowest_bone := INF
			if dropped_view != null:
				for bone in dropped_view.find_children("*", "PhysicalBone3D", true, false):
					lowest_bone = minf(lowest_bone, (bone as Node3D).global_position.y)
			print("COMBAT_DIAG drop: pos=%s in_tree=%s visual=%s visible=%s ragdoll=%s lowest_bone=%s" % [
				dropped.global_position, dropped.is_inside_tree(),
				visual != null, visual.visible if visual != null else false,
				dropped_view.is_ragdoll_active() if dropped_view != null else "-",
				("%.2f" % lowest_bone) if lowest_bone != INF else "none"])
			if dropped.global_position.y < -5.0 or (lowest_bone != INF and lowest_bone < -5.0):
				push_error("Dropped body fell through the world")
				failures += 1
	if _carry_result == "carrying":
		var carrier_hc := _carry_member as HumanoidCharacter
		var carried := carrier_hc.get_carry().get_carried_character() as HumanoidCharacter
		if carried != null:
			var carried_body := carried.get_body_projection() as HumanoidBodyProjection
			var offset: Vector3 = carried.global_position - carrier_hc.global_position
			print("COMBAT_DIAG carry_visual: carried_ragdoll=%s offset=%.2f rel_height=%.2f" % [
				carried_body.is_ragdoll_active() if carried_body != null else "no_body", offset.length(), offset.y])
			if carried_body != null and carried_body.is_ragdoll_active():
				push_error("Carried body still ragdolling on the ground")
				failures += 1
			# The tuned drape pose holds the carried origin high over the shoulder;
			# failure means still lying at ground level or detached entirely.
			if offset.y < 0.5 or offset.length() > 4.0:
				push_error("Carried body not seated on carrier (offset %.2fm, height %.2f)" % [offset.length(), offset.y])
				failures += 1
	if _carry_member != null and is_instance_valid(_carry_member):
		var cm := _carry_member as WorldActor
		print("COMBAT_DIAG carry_state: order_type=%d target_valid=%s in_combat=%s player_order=%s pos=%s" % [
			cm.get_current_order_type(), is_instance_valid(cm.get_interaction().current_carry_target) if cm.get_interaction().current_carry_target != null else false,
			cm.is_in_combat(), cm.has_active_player_order(), cm.global_position])
		print("COMBAT_DIAG carry_move: has_move_target=%s move_target=%s velocity=%s interaction=%s carrying_blocked=%s" % [
			cm._has_move_target, cm._move_target, cm.velocity, cm.get_interaction() != null,
			cm._carried_character != null])
	if not _drop_attempted or not _carry_visual_verified:
		push_error("Carry/drop phases must complete with a seated carried body before drop; state=%s" % _carry_result)
		failures += 1
	if _retreat_orders.is_empty() or not _order_checked:
		push_error("Retreat order/check phase was not exercised")
		failures += 1
	var completed_retreats := 0
	for entry in _retreat_orders.values():
		var member = entry["actor"].get_ref()
		if bool(entry["arrived"]):
			completed_retreats += 1
		elif member != _attack_member and member != _carry_member:
			push_error("Retreat command did not reach its destination")
			failures += 1
	if completed_retreats == 0:
		push_error("No retreat command physically completed")
		failures += 1
	if _ordered_members_still_fighting > 0:
		push_error("Player order override failed: %d ordered party members kept fighting" % _ordered_members_still_fighting)
		failures += 1
	print("COMBAT_ENGAGEMENT_%s" % ("OK" if failures == 0 else "FAILED count=%d" % failures))
	get_tree().quit(0 if failures == 0 else 1)
