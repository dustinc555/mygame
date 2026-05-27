extends SceneTree

const TWO_TOWNS_SCENE := preload("res://scenes/test_levels/two_towns_road_test.tscn")
const FACTION_HUMANOID_SCRIPT := preload("res://scripts/characters/faction_humanoid.gd")
const FARMERS_FACTION_ID := "Farmers"

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	_scene = TWO_TOWNS_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(240)
	_validate_keep_ruler_is_not_law_soldier()
	await _validate_farmer_crossing_jail_guard_assault()
	if _failures.is_empty():
		print("FARMER_CROSSING_JAIL_ASSAULT_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("FARMER_CROSSING_JAIL_ASSAULT_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_farmer_crossing_jail_guard_assault() -> void:
	var player := _scene.get_node_or_null("PartyMembers/Mira") as HumanoidCharacter
	var jail_guard := _scene.get_node_or_null("Settlements/FarmerCrossing/Facilities/SettlementJail/Staff/Guard") as HumanoidCharacter
	var warden := _scene.get_node_or_null("Settlements/FarmerCrossing/Facilities/SettlementJail/Staff/Warden") as HumanoidCharacter
	var law := root.find_child("LawOrderController", true, false)
	if player == null or jail_guard == null or warden == null or law == null:
		_fail("Expected Mira, Farmer Crossing jail guard, warden, and LawOrderController")
		return
	print("ASSAULT_REPRO guard_faction=%s guard_role=%s guard_authority=%s guard_npc_group=%s guard_settlement=%s player_party=%s" % [
		jail_guard.faction_name,
		str(jail_guard.get_meta("settlement_staff_role", "")),
		str(jail_guard.call("is_settlement_authority") if jail_guard.has_method("is_settlement_authority") else false),
		str(jail_guard.is_in_group("npc_character")),
		str(law.call("get_current_settlement_id_for", jail_guard)),
		str(player.is_player_party_member()),
	])
	_reset_actor(player)
	_reset_actor(jail_guard)
	_reset_actor(warden)
	law.call("_clear_warrant_for_actor", player, FARMERS_FACTION_ID)
	player.global_position = jail_guard.global_position + Vector3(0.9, 0.0, 0.0)
	player.assign_attack_target(jail_guard, true, true, true)
	await _wait_frames(12)
	var record: Dictionary = law.call("get_warrant_record", player, FARMERS_FACTION_ID)
	print("ASSAULT_REPRO after_attack warrant=%s public=%s crimes=%d guard_law_arrest=%s guard_target=%s player_target=%s guard_hostile=%s player_hostile=%s" % [
		str(not record.is_empty()),
		str(record.get("public_known", false)),
		(record.get("crimes", []) as Array).size(),
		str(jail_guard.call("is_law_arresting", player) if jail_guard.has_method("is_law_arresting") else false),
		str(jail_guard.get_current_combat_target()),
		str(player.get_current_combat_target()),
		str(jail_guard.has_hostility_with(player)),
		str(player.has_hostility_with(jail_guard)),
	])
	_print_nearby_authority(player, jail_guard)
	if record.is_empty():
		_fail("Attacking Farmer Crossing jail guard should create an immediate Farmers assault warrant")
	elif not _record_has_crime(record, LawOrderController.CRIME_ASSAULT):
		_fail("Farmer Crossing jail guard attack warrant should include assault")
	if not bool(jail_guard.call("is_law_arresting", player)):
		_fail("Attacked Farmer Crossing jail guard should answer as law arrest")
	if not bool(warden.call("is_law_arresting", player)):
		_fail("Farmer Crossing warden should answer detected jail guard assaults as a soldier")
	await _validate_warden_assault_path(player, jail_guard, warden, law)
	await _validate_context_menu_attack_path(player, jail_guard, warden, law)


func _validate_keep_ruler_is_not_law_soldier() -> void:
	var mayor_house := _scene.get_node_or_null("Settlements/FarmerCrossing/Keeps/MayorHouse") if _scene != null else null
	var ruler := _find_role_actor(mayor_house, "ruler")
	if ruler == null:
		_fail("Farmer Crossing keep should provide a ruler for soldier classification validation")
		return
	if ruler.has_method("is_faction_soldier") and bool(ruler.call("is_faction_soldier")):
		_fail("Keep ruler should remain settlement authority without becoming a law-response soldier")


func _validate_context_menu_attack_path(player: HumanoidCharacter, jail_guard: HumanoidCharacter, warden: HumanoidCharacter, law: Node) -> void:
	var party_manager := _scene.get_node_or_null("PartyManager")
	var interaction := root.find_child("WorldInteractionController", true, false)
	if party_manager == null or interaction == null:
		_fail("Context-menu repro requires PartyManager and WorldInteractionController")
		return
	_reset_actor(player)
	_reset_actor(jail_guard)
	_reset_actor(warden)
	law.call("_clear_warrant_for_actor", player, FARMERS_FACTION_ID)
	var passing_soldier := _make_validation_humanoid("PassingFarmerSoldier", "validation.farmer_crossing.passing_soldier", jail_guard.global_position + Vector3(2.0, 0.0, 0.0))
	passing_soldier.faction_name = FARMERS_FACTION_ID
	passing_soldier.squad_name = "PassingSoldiers"
	passing_soldier.set_faction_soldier(true)
	_scene.add_child(passing_soldier)
	var private_security := _make_validation_humanoid("NearbyPrivateSecurity", "validation.farmer_crossing.private_security", jail_guard.global_position + Vector3(3.0, 0.0, 0.0))
	private_security.faction_name = FARMERS_FACTION_ID
	private_security.squad_name = "BarSecurity"
	private_security.set_private_security(true)
	private_security.set_faction_soldier(false)
	_scene.add_child(private_security)
	await _wait_frames(8)
	law.call("_clear_warrant_for_actor", player, FARMERS_FACTION_ID)
	_reset_actor(player)
	_reset_actor(jail_guard)
	_reset_actor(warden)
	_reset_actor(passing_soldier)
	_reset_actor(private_security)
	player.global_position = jail_guard.global_position + Vector3(0.9, 0.0, 0.0)
	party_manager.call("select_only", player)
	interaction.set("context_humanoid", jail_guard)
	interaction.call("_on_context_menu_id_pressed", 5)
	await _wait_frames(12)
	var record: Dictionary = law.call("get_warrant_record", player, FARMERS_FACTION_ID)
	print("ASSAULT_REPRO context_path warrant=%s guard_law_arrest=%s guard_target=%s player_target=%s" % [
		str(not record.is_empty()),
		str(jail_guard.call("is_law_arresting", player) if jail_guard.has_method("is_law_arresting") else false),
		str(jail_guard.get_current_combat_target()),
		str(player.get_current_combat_target()),
	])
	if record.is_empty():
		_fail("Context-menu Attack on Farmer Crossing jail guard should create an assault warrant")
	if not bool(jail_guard.call("is_law_arresting", player)):
		_fail("Context-menu attacked Farmer Crossing jail guard should answer as law arrest")
	if not bool(warden.call("is_law_arresting", player)):
		_fail("Warden should answer context-menu jail guard assault as a soldier")
	await _wait_frames(60)
	var secondary_law_responders := _count_secondary_law_responders(player, jail_guard)
	print("ASSAULT_REPRO secondary_law_responders=%d" % secondary_law_responders)
	if secondary_law_responders <= 0:
		_fail("Same-settlement soldiers that join the jail assault should be upgraded to law arrest")
	if not bool(passing_soldier.call("is_law_arresting", player)):
		_fail("Same-faction passing soldier inside the settlement should answer the local jail assault")
	if bool(private_security.call("is_law_arresting", player)):
		_fail("Private security should not become a general law responder outside its venue defense")
	var starting_player_damage := player.get_total_wound_damage()
	await _wait_frames(240)
	print("ASSAULT_REPRO live_combat player_damage=%.2f guard_damage=%.2f player_life=%s guard_life=%s guard_law_arrest=%s distance=%.2f" % [
		player.get_total_wound_damage(),
		jail_guard.get_total_wound_damage(),
		str(player.life_state),
		str(jail_guard.life_state),
		str(jail_guard.call("is_law_arresting", player) if jail_guard.has_method("is_law_arresting") else false),
		player.global_position.distance_to(jail_guard.global_position),
	])
	if player.get_total_wound_damage() <= starting_player_damage and player.life_state == NpcRules.LifeState.ALIVE:
		_fail("Farmer Crossing jail guard should land combat hits after answering assault")
	passing_soldier.queue_free()
	private_security.queue_free()


func _validate_warden_assault_path(player: HumanoidCharacter, jail_guard: HumanoidCharacter, warden: HumanoidCharacter, law: Node) -> void:
	_reset_actor(player)
	_reset_actor(jail_guard)
	_reset_actor(warden)
	law.call("_clear_warrant_for_actor", player, FARMERS_FACTION_ID)
	player.global_position = warden.global_position + Vector3(0.9, 0.0, 0.0)
	player.assign_attack_target(warden, true, true, true)
	await _wait_frames(20)
	var record: Dictionary = law.call("get_warrant_record", player, FARMERS_FACTION_ID)
	print("ASSAULT_REPRO warden_path warrant=%s warden_law=%s guard_law=%s" % [
		str(not record.is_empty()),
		str(warden.call("is_law_arresting", player) if warden.has_method("is_law_arresting") else false),
		str(jail_guard.call("is_law_arresting", player) if jail_guard.has_method("is_law_arresting") else false),
	])
	if record.is_empty():
		_fail("Attacking Farmer Crossing warden should create an immediate Farmers assault warrant")
	if not bool(warden.call("is_law_arresting", player)):
		_fail("Attacked Farmer Crossing warden should answer as law arrest")
	if not bool(jail_guard.call("is_law_arresting", player)):
		_fail("Jail guard should help the attacked warden as a soldier")


func _print_nearby_authority(player: HumanoidCharacter, victim: HumanoidCharacter) -> void:
	for node in root.get_tree().get_nodes_in_group("npc_character"):
		var actor := node as HumanoidCharacter
		if actor == null or actor == player:
			continue
		var role := str(actor.get_meta("settlement_staff_role", ""))
		var distance := actor.global_position.distance_to(victim.global_position)
		if distance <= 12.0 or role == "guard" or role == "warden":
			print("ASSAULT_REPRO responder name=%s faction=%s role=%s authority=%s dist=%.2f law=%s target=%s" % [
				str(actor.name),
				actor.faction_name,
				role,
				str(actor.call("is_settlement_authority") if actor.has_method("is_settlement_authority") else false),
				distance,
				str(actor.call("is_law_arresting", player) if actor.has_method("is_law_arresting") else false),
				str(actor.get_current_combat_target()),
			])


func _count_secondary_law_responders(player: HumanoidCharacter, victim: HumanoidCharacter) -> int:
	var count := 0
	for node in root.get_tree().get_nodes_in_group("npc_character"):
		var actor := node as HumanoidCharacter
		if actor == null or actor == player or actor == victim:
			continue
		if not actor.has_method("is_faction_soldier") or not bool(actor.call("is_faction_soldier")):
			continue
		if actor.faction_name != FARMERS_FACTION_ID:
			continue
		if actor.has_method("is_law_arresting") and bool(actor.call("is_law_arresting", player)):
			count += 1
	return count


func _find_role_actor(target_root: Node, role: String) -> HumanoidCharacter:
	if target_root == null:
		return null
	if target_root is HumanoidCharacter and str(target_root.get_meta("settlement_staff_role", "")) == role:
		return target_root as HumanoidCharacter
	for child in target_root.get_children():
		var found := _find_role_actor(child, role)
		if found != null:
			return found
	return null


func _reset_actor(actor: HumanoidCharacter) -> void:
	if actor == null:
		return
	actor.call("_clear_all_active_orders")
	var ai_brain = actor.get("_ai_brain")
	if ai_brain != null and ai_brain.has_method("clear_for_player_override"):
		ai_brain.call("clear_for_player_override")
	actor.call("clear_all_personal_hostility")
	actor.call("disengage_combat_with")
	actor.velocity = Vector3.ZERO


func _make_validation_humanoid(node_name: String, stable_id: String, world_position: Vector3) -> HumanoidCharacter:
	var actor := CharacterBody3D.new()
	actor.name = node_name
	actor.set_script(FACTION_HUMANOID_SCRIPT)
	actor.position = world_position
	actor.set("member_name", node_name)
	actor.set("stable_id", stable_id)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.1
	collision.shape = capsule
	collision.position.y = 0.95
	actor.add_child(collision)
	var body := MeshInstance3D.new()
	body.name = "BodyMesh"
	body.position.y = 0.95
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.45
	body.mesh = mesh
	actor.add_child(body)
	return actor as HumanoidCharacter


func _record_has_crime(record: Dictionary, crime_type: String) -> bool:
	var crimes: Array = record.get("crimes", [])
	for crime in crimes:
		if crime is Dictionary and str(crime.get("crime_type", "")) == crime_type:
			return true
	return false


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
