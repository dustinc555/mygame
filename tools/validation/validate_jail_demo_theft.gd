extends Node

## Theft law-loop validator on the REAL jail_law_demo scene: Mira steals the
## faction-owned vase in front of the witness; a warrant must open and law
## consequences must reach her (combat/KO/carry/jail) within the sample window.

var _world: Node
var _elapsed := 0.0
var _stolen := false
var _warned_then_stole := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_world = (load("res://scenes/test_levels/jail_law_demo.tscn") as PackedScene).instantiate()
	add_child(_world)

func _process(delta: float) -> void:
	_elapsed += delta
	get_tree().paused = false
	if _elapsed >= 3.0 and _warned_then_stole < 1:
		_attempt_steal()
	if _elapsed >= 50.0:
		_report()
	elif fmod(_elapsed, 4.0) < delta and _elapsed > 8.0:
		var m := _world.get_node_or_null("PartyMembers/Mira") as WorldActor
		if m != null:
			var carry_diag := ""
			if m.is_carried():
				var carry := m.get_carry()
				var carrier := carry.get_carrier() as Node3D
				var body := m.get_body_projection() as HumanoidBodyProjection
				var carrier_actor := carrier as WorldActor
				var carrier_body = carrier_actor.get_body_projection() if carrier_actor != null else null
				var anchor: Variant = CarryPoseSolver._bone_global_position(carrier_body, PackedStringArray(["upperarm_r", "clavicle_r", "spine_03"]), Vector3.ZERO, "carrier") if carrier_body != null else null
				var skel: Skeleton3D = carrier_body.get_skeleton() if carrier_body != null else null
				var bone_names := ""
				if skel != null:
					for bi in range(mini(skel.get_bone_count(), 6)):
						bone_names += skel.get_bone_name(bi) + ","
				# Formula check: the carried transform must equal the calibrator-authored
				# shoulder-local transform (WYSIWYG contract with the tuning tool).
				var solver_error := -1.0
				if carrier_actor != null and carrier_body != null:
					var expected: Transform3D = CarryPoseSolver.solve_carried_transform(carrier_body, carrier_actor, m.get_carry().carry_pose_profile, m.get_body_projection(), m)
					solver_error = m.global_position.distance_to(expected.origin)
				var carried_body_v = m.get_body_projection()
				var cskel: Skeleton3D = carried_body_v.get_skeleton() if carried_body_v != null else null
				var drape := ""
				if cskel != null and anchor is Vector3:
					cskel.force_update_all_bone_transforms()
					var minv := m.global_transform.affine_inverse()
					for probe_bone in ["pelvis", "spine_02", "foot_l"]:
						var bi := cskel.find_bone(probe_bone)
						if bi >= 0:
							var bone_pos: Vector3 = cskel.global_transform * cskel.get_bone_global_pose(bi).origin
							drape += "%s_dy=%.2f local=%s " % [probe_bone, bone_pos.y - (anchor as Vector3).y, minv * bone_pos]
				print("CARRY_ANCHOR anchor=%s solver_error=%.3f drape[%s]" % [anchor, solver_error, drape])
				if solver_error > 0.2:
					push_error("Carried transform diverges %.2fm from the calibrated profile pose" % solver_error)
				carry_diag = " CARRY carrier=%s dist=%.2f clip=%s mira_y=%.2f carrier_y=%.2f basis_up=%.2f" % [
					carrier.name if carrier != null else "?",
					m.global_position.distance_to(carrier.global_position) if carrier != null else -1.0,
					body.get_current_clip() if body != null else "?",
					m.global_position.y, carrier.global_position.y if carrier != null else 0.0,
					m.global_transform.basis.y.dot(Vector3.UP)]
			print("THEFT_TRACE t=%.0f life=%d combat=%s carried=%s jailed=%s%s" % [_elapsed, m.life_state, m.is_in_combat(), m.is_carried(), m.is_in_cell_custody(), carry_diag])

func _attempt_steal() -> void:
	_warned_then_stole += 1
	var mira := _world.get_node_or_null("PartyMembers/Mira") as WorldActor
	var vase: Node3D = null
	for node in _world.find_children("*", "", true, false):
		if node.has_method("try_pickup") and node.has_method("get_theft_value"):
			vase = node
			break
	if mira == null or vase == null:
		push_error("missing mira=%s vase=%s" % [mira != null, vase != null])
		get_tree().quit(1)
		return
	mira.global_position = vase.global_position + Vector3(0.8, 0.2, 0.0)
	var ownership := BootstrapContext.service(OwnershipController.SERVICE_ID) as OwnershipController
	if ownership != null:
		var legal: bool = ownership._can_take_legally(mira, vase)
		var witnesses: Array = ownership._find_theft_witnesses(mira, vase)
		var suspicious = ownership._find_theft_suspicion_witness(mira, vase)
		print("THEFT_PROBE legal=%s witnesses=%d suspicious=%s" % [legal, witnesses.size(), suspicious != null])
	var result: bool = vase.call("try_pickup", mira)
	print("THEFT_PROBE attempt=%d picked_up=%s mira_appearance=%s" % [_warned_then_stole, result, (mira.get("appearance_data") != null)])

func _report() -> void:
	set_process(false)
	var mira := _world.get_node_or_null("PartyMembers/Mira") as WorldActor
	var law := BootstrapContext.service(&"law_order") as LawOrderController
	var warrant_open: bool = law != null and not law.warrants.is_empty()
	if law != null and mira != null and not law.warrants.is_empty():
		var record: Dictionary = law.warrants.values()[0].values()[0]
		var settlement: Node = law._find_settlement_for_warrant(mira, record)
		var should_alert: bool = law._should_alert_authority_guards(mira, record, settlement)
		var guards: Array = law._find_authority_guards("Farmers", settlement)
		var in_scope := 0
		for guard in guards:
			if law._is_guard_in_authority_alert_scope(guard, record, mira):
				in_scope += 1
		print("THEFT_PROBE settlement=%s should_alert=%s guards=%d in_scope=%d state=%s" % [settlement != null, should_alert, guards.size(), in_scope, record.get("state")])
		var in_border: bool = settlement.call("contains_town_border_position", mira.global_position) if settlement != null and settlement.has_method("contains_town_border_position") else false
		print("THEFT_PROBE mira_pos=%s life=%d downed=%s in_border=%s border_radius=%s auto=%s town_pos=%s" % [mira.global_position, mira.life_state, law._actor_is_downed(mira), in_border, settlement.get("town_border_radius"), settlement.get("auto_town_border_from_footprint"), (settlement as Node3D).global_position])
	var attacked := false
	for node in get_tree().get_nodes_in_group("humanoid_character"):
		var npc := node as WorldActor
		if npc != null and npc != mira and npc.is_hostile_to(mira):
			attacked = true
	var consequences: bool = mira != null and (mira.is_in_cell_custody() or mira.is_carried() or mira.life_state != NpcRules.LifeState.ALIVE or mira.is_in_combat())
	print("THEFT_PROBE warrant_open=%s witness_hostile=%s consequences=%s jailed=%s" % [warrant_open, attacked, consequences, mira.is_in_cell_custody() if mira != null else false])
	get_tree().quit(0 if (warrant_open and consequences) else 1)
