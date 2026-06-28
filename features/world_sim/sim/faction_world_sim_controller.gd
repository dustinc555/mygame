extends Node

class_name FactionWorldSimController

const SERVICE_ID := &"faction_world_sim"

## The world-sim "brain" for factions. Runs on a SLOW timer (not per-frame) and makes
## O(1) decisions: an aggressive faction that is hostile to a neighbour launches a
## world-sim attack squad (data dot) at it. No live bodies, no per-frame actor scans.
## This replaces the deleted controller-side raid AI. Behavior is driven by each
## faction's editor-authored personality (aggression) + diplomacy — per-faction, not
## a generic routine.

const TICK_INTERVAL := 6.0
const RAID_COOLDOWN_SECONDS := 90.0
const MIN_AGGRESSION_TO_RAID := 0.45
## Only ONE war party may be afield at a time, and a peace period follows each raid so
## raiders regroup instead of pouring out constantly.
const GLOBAL_RAID_COOLDOWN_SECONDS := 90.0
## Player reference (world_actor.move_speed 3.2 walk × NpcRules run mult 1.7 ≈ 5.44 run).
## Squads march near a walk and are hard-capped below the player's run, so a war party
## never out-paces the player. World-time speed (Engine.time_scale) still fast-forwards
## the whole sim, so raids stay watchable at higher speeds without cheating the pace.
const PLAYER_WALK_SPEED := 3.2
const PLAYER_RUN_SPEED := 5.44

var _tick_remaining := 0.0
var _elapsed := 0.0
var _raid_index := 0
var _last_raid_at := {}
var _last_global_raid_at := -1.0e9
var _rng := RandomNumberGenerator.new()
var _root_scene: Node
var _context: BootstrapContext


func initialize(context: BootstrapContext) -> void:
	_context = context
	_root_scene = context.root_scene


func _ready() -> void:
	add_to_group("faction_world_sim_controller")
	_rng.randomize()
	if _root_scene == null and get_tree() != null:
		_root_scene = get_tree().current_scene


func _process(delta: float) -> void:
	_elapsed += delta
	_tick_remaining -= delta
	if _tick_remaining > 0.0:
		return
	_tick_remaining = TICK_INTERVAL
	_tick()


func _tick() -> void:
	var gecs := _get_gecs_world()
	var factions := _get_faction_controller()
	if gecs == null or factions == null or not gecs.has_method("upsert_world_sim_squad"):
		return
	# One war party at a time — let the current raid play out before mustering another.
	if _has_active_faction_raid(gecs):
		return
	# Peace period after the last raid — raiders regroup, they don't spawn constantly.
	if _elapsed - _last_global_raid_at < GLOBAL_RAID_COOLDOWN_SECONDS:
		return
	var settlements := _gather_settlements()
	if settlements.size() < 2:
		return
	# Only the single most-aggressive faction with a hostile neighbour considers a raid,
	# and even then it commits only some of the time — they bide their time.
	var source := _pick_raid_source(factions, settlements)
	if source.is_empty():
		return
	var faction_id := str(source.get("faction_id", ""))
	if _elapsed - float(_last_raid_at.get(source.get("id", ""), -1.0e9)) < RAID_COOLDOWN_SECONDS:
		return
	var aggression := _faction_aggression(factions, faction_id)
	if aggression < MIN_AGGRESSION_TO_RAID:
		return
	if _rng.randf() > aggression * 0.5:
		return
	var target := _pick_target(factions, faction_id, source, settlements)
	if target.is_empty():
		return
	_launch_raid(gecs, factions, source, target, faction_id)


## True while any faction war party still exists in the world sim (enforces one-at-a-time).
func _has_active_faction_raid(gecs: Node) -> bool:
	if not gecs.has_method("get_world_sim_squads"):
		return false
	for record in gecs.get_world_sim_squads():
		if str(record.get("owner_kind", "")) == "faction":
			return true
	return false


## Spawn a world-sim raid squad (a data dot) with the demand_tribute objective and send
## it at the target. Shared by the autonomous brain and the manual debug trigger.
func _launch_raid(gecs: Node, factions: Node, source: Dictionary, target: Dictionary, faction_id: String) -> void:
	_last_raid_at[source.get("id", "")] = _elapsed
	_last_global_raid_at = _elapsed
	_raid_index += 1
	var squad_id := "faction:%s:raid:%d" % [faction_id, _raid_index]
	var squad_size := _faction_squad_size(factions, faction_id)
	gecs.upsert_world_sim_squad({
		"squad_id": squad_id,
		"owner_id": str(source.get("id", "")),
		"owner_kind": "faction",
		"faction_id": faction_id,
		"objective": "attack",
		"target_settlement_id": str(target.get("id", "")),
		"position": source.get("position", Vector3.ZERO),
		"target_position": target.get("position", Vector3.ZERO),
		"home_position": source.get("position", Vector3.ZERO),
		"move_speed": _squad_march_speed(factions, faction_id),
		"member_count": squad_size,
		"state": "active",
		"phase": "",
		"phase_timer": 0.0,
		"decision": "",
	})
	if gecs.has_method("log_world_event"):
		gecs.log_world_event("faction", "%s war party marches on %s (%d strong)" % [faction_id, str(target.get("id", "")), squad_size], {})


## Manual trigger (debug button): launch a demand_tribute raid from the most aggressive
## settlement at its nearest hostile neighbour. Returns a status line for the action UI.
func force_demand_tribute_raid() -> String:
	var gecs := _get_gecs_world()
	var factions := _get_faction_controller()
	if gecs == null or factions == null or not gecs.has_method("upsert_world_sim_squad"):
		return "World sim not ready"
	if _has_active_faction_raid(gecs):
		return "A war party is already afield — one raid at a time"
	var settlements := _gather_settlements()
	if settlements.size() < 2:
		return "Need at least two settlements"
	var source := _pick_raid_source(factions, settlements)
	if source.is_empty():
		return "No faction with a hostile neighbour to raid"
	var faction_id := str(source.get("faction_id", ""))
	var target := _pick_target(factions, faction_id, source, settlements)
	if target.is_empty():
		return "No hostile target for %s" % faction_id
	_launch_raid(gecs, factions, source, target, faction_id)
	return "%s raids %s — watch the map (M) / log (F9)" % [faction_id, str(target.get("id", ""))]


## Pick the settlement whose faction is most aggressive AND has a hostile target — the
## natural raider (East Raiders in the demo).
func _pick_raid_source(factions: Node, settlements: Array) -> Dictionary:
	var best := {}
	var best_aggression := -1.0
	for source in settlements:
		var faction_id := str(source.get("faction_id", ""))
		if faction_id.is_empty():
			continue
		if _pick_target(factions, faction_id, source, settlements).is_empty():
			continue
		var aggression := _faction_aggression(factions, faction_id)
		if aggression > best_aggression:
			best_aggression = aggression
			best = source
	return best


func _pick_target(factions: Node, faction_id: String, source: Dictionary, settlements: Array) -> Dictionary:
	var best := {}
	var best_distance := INF
	var source_position: Vector3 = source.get("position", Vector3.ZERO)
	for candidate in settlements:
		if candidate.get("id", "") == source.get("id", ""):
			continue
		var candidate_faction := str(candidate.get("faction_id", ""))
		if candidate_faction.is_empty() or candidate_faction == faction_id:
			continue
		if not bool(factions.are_hostile(faction_id, candidate_faction)):
			continue
		var distance: float = source_position.distance_squared_to(candidate.get("position", Vector3.ZERO))
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


func _gather_settlements() -> Array:
	var result: Array = []
	var tree := get_tree()
	if tree == null:
		return result
	for node in tree.get_nodes_in_group("settlement_town"):
		if not (node is Node3D):
			continue
		var faction_id := ""
		if node.has_method("get_faction_id"):
			faction_id = str(node.call("get_faction_id"))
		elif node.get("faction_id") != null:
			faction_id = str(node.get("faction_id"))
		# Canonical settlement id (e.g. "surf_city") — matches the settlement controller's
		# keys, so tribute/loot/defender lookups hit the right town (node.name is "SurfCity").
		var settlement_id := str(node.call("get_settlement_id")) if node.has_method("get_settlement_id") else str(node.name)
		result.append({
			"id": settlement_id,
			"faction_id": faction_id,
			"position": (node as Node3D).global_position,
		})
	return result


## Centralized dice resolver — the one place a fight's winner + margin is rolled, on
## attacker-vs-defender combat-stat leverage. Pure roll + casualties, NO spoils/capture
## (the encounter's aftermath applies the winner's objective). Logic only, no bodies.
func roll_raid(attackers: int, target_id: String) -> Dictionary:
	attackers = maxi(attackers, 0)
	var attacker_power := float(maxi(attackers, 1))
	var defender_power := _settlement_defender_power(target_id)
	var win_chance := attacker_power / maxf(attacker_power + defender_power, 0.001)
	var won := _rng.randf() < win_chance
	var loss_fraction := 0.25 if won else 0.65
	var survivors := maxi(0, attackers - int(round(float(attackers) * loss_fraction)))
	return {
		"won": won,
		"survivors": survivors,
		"win_chance": win_chance,
		"attacker_power": attacker_power,
		"defender_power": defender_power,
	}


## Loot applied when the attackers win (called from the encounter aftermath).
func apply_raid_win_spoils(target_id: String, food_amount: float) -> void:
	if target_id.is_empty():
		return
	var settlements := _get_settlement_controller()
	if settlements != null and settlements.has_method("adjust_food"):
		settlements.call("adjust_food", target_id, -absf(food_amount), "world_sim_raid")


func _settlement_defender_power(settlement_id: String) -> float:
	if settlement_id.is_empty():
		return 6.0
	var settlements := _get_settlement_controller()
	if settlements != null and settlements.has_method("get_settlement_state"):
		var state: Dictionary = settlements.call("get_settlement_state", settlement_id)
		# Defenders scale with population; +3 base so an empty town isn't a free win.
		return float(state.get("population", 0)) + 3.0
	return 6.0


## Overground march pace for a faction's squads — a walk scaled by the faction's fitness
## (aggregate endurance/run), clamped so a raid never moves faster than the player runs.
func _squad_march_speed(factions: Node, faction_id: String) -> float:
	var fitness := 1.0
	if factions != null and factions.has_method("get_faction_definition"):
		var definition = factions.get_faction_definition(faction_id)
		if definition != null and definition.has_method("get_squad_march_fitness"):
			fitness = float(definition.get_squad_march_fitness())
	return clampf(PLAYER_WALK_SPEED * fitness, 2.0, PLAYER_RUN_SPEED)


func _faction_squad_size(factions: Node, faction_id: String) -> int:
	if factions != null and factions.has_method("get_faction_definition"):
		var definition = factions.get_faction_definition(faction_id)
		if definition != null and definition.has_method("get_default_squad_size"):
			return int(definition.get_default_squad_size())
	return 4


## Generate persistent records (name from the faction name profile, look from its
## appearance profile, raider gear/stance) for a realized squad. Keyed by squad_id so a
## squad keeps the same faces across realize/derealize. Returns [] if no population brain.
func _generate_squad_records(population: Node, definition, faction_id: String, squad_id: String, size: int, hostiles, body_color: Color) -> Array:
	if population == null or not population.has_method("ensure_generated_population"):
		return []
	var context := {
		"member_name_prefix": faction_id,
		"faction_id": faction_id,
		"squad_name": squad_id,
		"role_id": "raider",
		"base_color": body_color,
		"hostile_faction_ids": Array(hostiles) if hostiles != null else [],
		"combat_stance": NpcRules.CombatStance.AGGRESSIVE,
		"population_appearance_profile": definition.get("population_appearance_profile"),
		"population_name_profile": definition.get("population_name_profile"),
	}
	return population.ensure_generated_population(squad_id, squad_id, size, context)


func _get_population_controller() -> Node:
	return _context.get_optional(PopulationController.SERVICE_ID) if _context != null else null


func _get_settlement_controller() -> Node:
	return _context.get_optional(SettlementController.SERVICE_ID) if _context != null else null


func _faction_aggression(factions: Node, faction_id: String) -> float:
	if not factions.has_method("get_faction_definition"):
		return 0.0
	var definition = factions.get_faction_definition(faction_id)
	if definition == null:
		return 0.0
	var profile = definition.get_personality_profile() if definition.has_method("get_personality_profile") else null
	if profile != null and profile.get("aggression") != null:
		return float(profile.get("aggression"))
	return 0.0


## --- Faction squad body realization (driven by WorldSimSquadController's LOD swap) ---
## Manifest a faction squad's bodies from its world-sim record when it enters the LOD
## ring; fold them back (counting survivors) when it leaves. Same source of truth, so
## the player's kills persist across the handoff — fully impactful, not cosmetic.

func is_faction_squad_realized(squad_id: String) -> bool:
	var root := _faction_squad_actor_root(false)
	if root == null:
		return false
	for node in root.get_children():
		if str(node.get("world_squad_id")) == squad_id:
			return true
	return false


func realize_faction_squad(record: Dictionary) -> void:
	var squad_id := str(record.get("squad_id", ""))
	if squad_id.is_empty() or is_faction_squad_realized(squad_id):
		return
	var factions := _get_faction_controller()
	if factions == null or not factions.has_method("get_faction_definition"):
		return
	var faction_id := str(record.get("faction_id", ""))
	var definition = factions.get_faction_definition(faction_id)
	if definition == null or not definition.has_method("get_member_actor_script"):
		return
	var actor_script: Script = definition.get_member_actor_script()
	if actor_script == null:
		return
	var size := int(record.get("member_count", 0))
	if size <= 0:
		size = definition.get_default_squad_size() if definition.has_method("get_default_squad_size") else 4
	var origin: Vector3 = record.get("position", Vector3.ZERO)
	var hostiles = definition.get("default_hostile_faction_ids")
	var body_color: Color = definition.get("primary_color") if definition.get("primary_color") != null else Color(0.6, 0.6, 0.6, 1.0)
	var root := _faction_squad_actor_root()
	if root == null:
		return
	# Generate real raider records (name + appearance + gear) the same way towns do, so
	# the manifested bodies are actual characters, not nameless "Character" with no model.
	var population := _get_population_controller()
	var records := _generate_squad_records(population, definition, faction_id, squad_id, size, hostiles, body_color)
	for i in range(size):
		var actor = actor_script.new()
		if actor == null:
			continue
		actor.name = "%s_%d" % [squad_id.replace(":", "_"), i]
		# Apply the generated record BEFORE add_child so the body projection builds the
		# model from its appearance when it enters the tree.
		if population != null and population.has_method("apply_record_to_actor") and i < records.size():
			population.apply_record_to_actor(actor, records[i])
		actor.set("faction_name", faction_id)
		actor.set("world_squad_id", squad_id)
		if hostiles != null:
			actor.set("hostile_factions", hostiles)
		actor.set("position", origin + Vector3(_rng.randf_range(-2.0, 2.0), 0.0, _rng.randf_range(-2.0, 2.0)))
		_ensure_body_children(actor)
		root.add_child(actor)
		# Transient encounter bodies manage their own realize/derealize lifecycle.
		actor.add_to_group("encounter_squad_body")
		if actor.has_method("request_spawn_grounding_refresh"):
			actor.call("request_spawn_grounding_refresh", 8)


## Script-spawned humanoids need their collision AND a "BodyMesh" node — the humanoid
## body projection bails (builds no model) unless a child named "BodyMesh" exists, then
## hides it once the real model is built. Mirrors the town spawner's _add_basic_humanoid_children.
func _ensure_body_children(actor: Node) -> void:
	if actor.get_node_or_null("CollisionShape3D") == null:
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		collision.transform = Transform3D(Basis(), Vector3(0.0, 0.95, 0.0))
		var capsule_shape := CapsuleShape3D.new()
		capsule_shape.radius = 0.45
		capsule_shape.height = 1.1
		collision.shape = capsule_shape
		actor.add_child(collision)
	if actor.get_node_or_null("BodyMesh") == null:
		var body := MeshInstance3D.new()
		body.name = "BodyMesh"
		body.transform = Transform3D(Basis(), Vector3(0.0, 0.95, 0.0))
		var capsule_mesh := CapsuleMesh.new()
		capsule_mesh.radius = 0.45
		body.mesh = capsule_mesh
		actor.add_child(body)


## Order a realized squad's live bodies to march toward the target town and return their
## centroid (so the world-sim dot tracks them). Without this the bodies just stand where
## they spawned even though the squad's objective is the target settlement.
func drive_realized_squad(record: Dictionary) -> Vector3:
	var squad_id := str(record.get("squad_id", ""))
	var fallback: Vector3 = record.get("position", Vector3.ZERO)
	var root := _faction_squad_actor_root(false)
	if root == null:
		return fallback
	var target: Vector3 = record.get("target_position", fallback)
	var sum := Vector3.ZERO
	var count := 0
	for node in root.get_children():
		if str(node.get("world_squad_id")) != squad_id or not (node is Node3D):
			continue
		if node.has_method("is_alive") and not bool(node.call("is_alive")):
			continue
		if node.has_method("set_move_target"):
			node.call("set_move_target", target, false)
		sum += (node as Node3D).global_position
		count += 1
	return sum / float(count) if count > 0 else fallback


func derealize_faction_squad(squad_id: String) -> int:
	var survivors := 0
	var root := _faction_squad_actor_root(false)
	if root == null:
		return survivors
	for node in root.get_children():
		if str(node.get("world_squad_id")) != squad_id:
			continue
		if node.has_method("is_alive"):
			if bool(node.call("is_alive")):
				survivors += 1
		else:
			survivors += 1
		node.queue_free()
	return survivors


func _faction_squad_actor_root(create_if_missing := true) -> Node:
	if _root_scene == null:
		_root_scene = get_tree().current_scene if get_tree() != null else null
	if _root_scene == null:
		return null
	var root := _root_scene.get_node_or_null("WorldSimSquadActors")
	if root == null and create_if_missing:
		root = Node3D.new()
		root.name = "WorldSimSquadActors"
		_root_scene.add_child(root)
	return root


func _get_faction_controller() -> Node:
	return _context.get_optional(FactionController.SERVICE_ID) if _context != null else null


func _get_gecs_world() -> Node:
	return _context.get_optional(GecsWorldController.SERVICE_ID) if _context != null else null
