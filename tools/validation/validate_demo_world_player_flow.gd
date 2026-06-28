extends Node

## Scene-mode probe for the demo-world PLAYER flow — the exact live path:
## spawn the created character late (post-boot, like the character creator does),
## verify it registers into GECS centrally, shows hunger, and that an attack
## command on a town NPC actually engages. Guards the "works in test level,
## broken in demo world" bug class.

const DEMO_WORLD := "res://scenes/worlds/demo_world/demo_world.tscn"
const SPAWN_TIME := 4.0
const TOWN_TIME := 6.0
const ATTACK_TIME := 14.0
const ENGAGE_CHECK_TIME := 19.0
const RETREAT_TIME := 20.0
const KO_TIME := 34.0
const REPORT_TIME := 75.0
var _moved_to_town := false
var _engaged_seen := false
var _assist_seen := false
var _retreat_ordered := false
var _retreat_position := Vector3.ZERO
var _next_trace_time := 21.0
var _ko_applied := false
var _retreat_verdict := -1
var _carried_seen := false
var _jailed_seen := false

var _world: Node
var _elapsed := 0.0
var _spawned_member: Node = null
var _attack_target: Node = null
var _attack_ordered := false
var _failures := 0


func _ready() -> void:
	# The demo world opens the character creator and pauses the tree; the probe
	# must keep processing and unpauses after bypassing the UI with a direct spawn.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var packed: PackedScene = load(DEMO_WORLD)
	_world = packed.instantiate()
	add_child(_world)


func _process(_delta: float) -> void:
	_elapsed += _delta
	if _spawned_member == null and _elapsed >= SPAWN_TIME:
		_spawn_member()
	if _spawned_member != null and not _moved_to_town and _elapsed >= TOWN_TIME:
		_moved_to_town = true
		var town: Node = get_tree().get_first_node_in_group("settlement_town")
		if town is Node3D:
			(_spawned_member as Node3D).global_position = (town as Node3D).global_position + Vector3(4.0, 0.5, 4.0)
	if _spawned_member != null and not _attack_ordered and _elapsed >= ATTACK_TIME:
		_order_attack()
	if _attack_ordered and not _retreat_ordered and _elapsed >= ENGAGE_CHECK_TIME:
		var member := _spawned_member as WorldActor
		if member != null and member.is_in_combat():
			_engaged_seen = true
		_check_guard_assist()
	if not _retreat_ordered and _elapsed >= RETREAT_TIME:
		_retreat_ordered = true
		var member := _spawned_member as WorldActor
		if member != null and _attack_target != null and is_instance_valid(_attack_target):
			_retreat_position = member.global_position + (member.global_position - (_attack_target as Node3D).global_position).normalized() * 25.0
			member.set_move_target(_retreat_position)
	if _retreat_ordered and _elapsed >= _next_trace_time:
		_next_trace_time += 3.0
		var m := _spawned_member as WorldActor
		var t := _attack_target as WorldActor
		if m != null and t != null and is_instance_valid(t):
			print("DEMO_TRACE t=%.1f member_pos=%s dist_to_enemy=%.1f dist_to_retreat=%.1f member_combat=%s member_order=%s enemy_grudges_member=%s enemy_combat=%s" % [
				_elapsed, m.global_position, m.global_position.distance_to(t.global_position),
				m.global_position.distance_to(_retreat_position), m.is_in_combat(),
				m.has_active_player_order(), t.is_hostile_to(m), t.is_in_combat()])
	if not _ko_applied and _elapsed >= KO_TIME:
		_ko_applied = true
		# Record the retreat/boomerang verdict BEFORE the KO changes everything.
		var m := _spawned_member as WorldActor
		_retreat_verdict = 1 if (m != null and m.get_current_combat_target() == _attack_target) else 0
		_force_down_member()
	if _ko_applied and _elapsed < REPORT_TIME:
		var m := _spawned_member as WorldActor
		if m != null:
			if m.is_carried():
				_carried_seen = true
			if m.is_in_cell_custody():
				_jailed_seen = true
			if fmod(_elapsed, 6.0) < get_process_delta_time():
				var soldiers_alive := 0
				var soldier_info := ""
				for node in get_tree().get_nodes_in_group("faction_soldier"):
					var soldier := node as WorldActor
					if soldier != null and soldier.life_state == NpcRules.LifeState.ALIVE:
						soldiers_alive += 1
						soldier_info += "%s(order=%d carrying=%s dist=%.0f) " % [soldier.member_name, soldier.get_current_order_type(), soldier.get_carried_character() != null, soldier.global_position.distance_to(m.global_position)]
				var law := BootstrapContext.service(LawOrderController.SERVICE_ID) as LawOrderController
				var warrant_states := ""
				if law != null:
					for actor_key in law.warrants.keys():
						for faction_id in law.warrants[actor_key].keys():
							warrant_states += str(law.warrants[actor_key][faction_id].get("state", "?")) + " "
				var custody_diag := ""
				if law != null and not law.warrants.is_empty():
					var record: Dictionary = law.warrants.values()[0].values()[0]
					var settlement: Node = law._find_settlement_for_warrant(m, record)
					var jail: Node = law._find_jail_by_id(str(record.get("custody_jail_id", "")))
					var guard = law._find_custody_guard(m, record, settlement)
					var cell = jail.call("get_available_cell", m, m) if jail != null and jail.has_method("get_available_cell") else null
					custody_diag = "settlement=%s jail=%s guard=%s cell=%s downed=%s" % [settlement != null, jail != null, guard.member_name if guard != null else "NONE", cell != null, m.is_downed_state()]
				var hauler_diag := ""
				for node in get_tree().get_nodes_in_group("faction_soldier"):
					var hauler := node as WorldActor
					if hauler != null and hauler.get_carried_character() != null:
						hauler_diag = "HAULER %s move=%s target=%s sitting=%s vel=%.2f pos=%s" % [hauler.member_name, hauler.get("_has_move_target"), hauler.get("_move_target"), hauler.is_sitting(), hauler.velocity.length(), hauler.global_position]
				if not hauler_diag.is_empty():
					print(hauler_diag)
				var clip_diag := ""
				var mbody := m.get_body_projection() as HumanoidBodyProjection
				if mbody != null:
					clip_diag = "clip=%s playing=%s ragdoll=%s" % [mbody.get_current_clip(), mbody.is_current_clip_playing(), mbody.is_ragdoll_active()]
				print("ARREST_TRACE t=%.0f life=%d carried=%s jailed=%s %s soldiers=%d [%s] warrants=[%s] %s" % [_elapsed, m.life_state, m.is_carried(), m.is_in_cell_custody(), clip_diag, soldiers_alive, soldier_info, warrant_states, custody_diag])
	if _elapsed >= REPORT_TIME:
		_report()


## KO the fugitive the way combat resolution does: damage into the GECS vitals
## component (the sim truth), then the vitals/sync systems propagate the state.
func _force_down_member() -> void:
	var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	var entity = gecs.get_actor_entity(_spawned_member) if gecs != null else null
	if entity == null:
		_fail("no GECS entity for member at KO time")
		return
	var vit = entity.get_component(CGameActorVitals)
	if vit == null:
		_fail("member entity has no vitals component")
		return
	# Enough to KO (UNCONSCIOUS), not enough to kill — blunt does not bleed out.
	vit.blunt_damage += minf(vit.max_hp * 0.85, 150.0)
	VitalsStateMachine.recalculate(vit, 0.0)


## Guards (aggressive stance) within assist range must acquire the attacker after
## exchanges land. Soft check: skipped when no guard is realized near the fight.
func _check_guard_assist() -> void:
	if _assist_seen:
		return
	var member := _spawned_member as WorldActor
	if member == null:
		return
	for node in get_tree().get_nodes_in_group("humanoid_character"):
		var npc := node as WorldActor
		if npc == null or npc == member or npc.is_player_party_member() or npc == _attack_target:
			continue
		if npc.combat_stance == NpcRules.CombatStance.AGGRESSIVE and npc.is_hostile_to(member):
			_assist_seen = true
			return


func _spawn_member() -> void:
	var startup: Node = _world if _world.has_method("spawn_created_character") else null
	if startup == null:
		for child in _world.get_children():
			if child.has_method("spawn_created_character"):
				startup = child
				break
	if startup == null:
		_fail("demo world startup node not found")
		_report()
		return
	var appearance := CharacterAppearanceData.new()
	_spawned_member = startup.spawn_created_character(appearance, "ProbeWanderer")
	get_tree().paused = false
	if _spawned_member == null:
		_fail("spawn_created_character returned null")
		_report()


func _order_attack() -> void:
	_attack_ordered = true
	var member := _spawned_member as WorldActor
	var nearest: WorldActor = null
	var nearest_distance := INF
	for node in get_tree().get_nodes_in_group("humanoid_character"):
		var npc := node as WorldActor
		if npc == null or npc == member or npc.is_player_party_member() or npc.life_state != NpcRules.LifeState.ALIVE:
			continue
		var distance := member.global_position.distance_to(npc.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = npc
	if nearest == null:
		_fail("no town NPC found to attack (none realized near spawn?)")
		return
	_attack_target = nearest
	# Walk into range first if far, then order the attack (targeting radius 8.5m).
	if nearest_distance > 6.0:
		member.global_position = nearest.global_position + Vector3(3.0, 0.0, 0.0)
	# Same sequence as WorldInteractionController._assign_attack_to_selection:
	# report the crime first (already-hostile pairs are not crimes), then attack.
	var law := BootstrapContext.service(LawOrderController.SERVICE_ID) as LawOrderController
	if law != null:
		law.report_player_assault(member as HumanoidCharacter, nearest as HumanoidCharacter)
	member.assign_attack_target(nearest)


func _report() -> void:
	set_process(false)
	var member := _spawned_member as WorldActor
	if member == null or not is_instance_valid(member):
		_fail("created member invalid at report")
	else:
		var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
		var registered: bool = gecs != null and gecs.get_actor_by_stable_id("player.created") != null
		var shows_hunger: bool = member.shows_hunger_vital()
		var engaged: bool = _engaged_seen or member.is_in_combat()
		var boomeranged := false
		if _retreat_ordered and _attack_target != null and is_instance_valid(_attack_target):
			# The retreat cleared the grudge; the member must NOT have walked back to
			# the old enemy after arriving (defensive: ignore unless re-attacked).
			# Fighting someone ELSE (an aggressive guard pursuing the assault) is the
			# assist design working, not a boomerang.
			# Identity only: with a warrant open, guards legitimately drag the fight
			# anywhere in town — proximity to the old civilian proves nothing.
			# Verdict recorded at KO time (the KO ends all combat states).
			boomeranged = _retreat_verdict == 1
		print("DEMO_FLOW registered=%s shows_hunger=%s hunger=%.1f attack_engaged=%s assist_seen=%s boomerang=%s target=%s" % [
			registered, shows_hunger, member.hunger, engaged, _assist_seen, boomeranged,
			_attack_target.name if _attack_target != null and is_instance_valid(_attack_target) else "none"])
		if not registered:
			_fail("late-spawned member never registered into GECS")
		if not shows_hunger:
			_fail("created character has no hunger bar")
		if _attack_target != null and not engaged:
			_fail("attack command on town NPC never engaged")
		if boomeranged:
			_fail("member returned to the old enemy after a player retreat order")
		var law := BootstrapContext.service(LawOrderController.SERVICE_ID) as LawOrderController
		var warrant_open: bool = law != null and not law.warrants.is_empty()
		print("DEMO_FLOW warrant_open=%s carried_seen=%s jailed=%s" % [warrant_open, _carried_seen, _jailed_seen])
		if _attack_target != null and not warrant_open:
			_fail("assault on a townsperson opened no warrant (law pipeline dead)")
		if _ko_applied and not _jailed_seen:
			_fail("KO'd criminal was never hauled to a jail cell (carried_seen=%s)" % _carried_seen)
		if _jailed_seen and member.is_in_cell_custody() and member.is_downed_state():
			# Presentation contract from main: a downed prisoner holds the frozen
			# IdleToLay cot pose, not ragdoll/downed visuals.
			var body := member.get_body_projection() as HumanoidBodyProjection
			var cot_clip: String = body.get_current_clip() if body != null else ""
			print("DEMO_FLOW cot_clip=%s ragdoll=%s" % [cot_clip, body.is_ragdoll_active() if body != null else "?"])
			if cot_clip != "IdleToLay" or (body != null and body.is_ragdoll_active()):
				_fail("jailed downed prisoner is not holding the IdleToLay cot pose")
	print("DEMO_FLOW_%s" % ("OK" if _failures == 0 else "FAILED count=%d" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _fail(message: String) -> void:
	push_error(message)
	_failures += 1
