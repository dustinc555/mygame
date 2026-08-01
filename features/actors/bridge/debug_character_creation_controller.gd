extends Node

class_name DebugCharacterCreationController

const SERVICE_ID := &"debug_character_creation"
const REQUEST_ID := &"debug_character_creation"
const APPEARANCE_SERVICE_ID := &"character_appearance"
const POPULATION_SERVICE_ID := &"population"
const GECS_WORLD_SERVICE_ID := &"gecs_world"
const WORLD_TIME_SERVICE_ID := &"world_time"
const DEFER_POPULATION_REGISTRATION_META := &"defer_population_registration"
const PARTY_MEMBER_SCENE := preload("res://features/core/party/party_member.tscn")
const INVENTORY_STOCK_SCRIPT := preload("res://features/inventory/resources/items/inventory_stock.gd")
const SILVER_ITEM := preload("res://features/inventory/resources/items/silver.tres")
const PEASANT_TUNIC := preload("res://features/inventory/resources/items/peasant_tunic.tres")
const PEASANT_TROUSERS := preload("res://features/inventory/resources/items/peasant_trousers.tres")
const PEASANT_SHOES := preload("res://features/inventory/resources/items/peasant_shoes.tres")
const IRON_SWORD := preload("res://features/inventory/resources/items/iron_sword.tres")
const ROUND_SHIELD := preload("res://features/inventory/resources/items/round_shield.tres")

signal creation_finished(success: bool, message: String, actor: WorldActor)

var _context: BootstrapContext
var _root_scene: Node
var _appearance_controller: Node
var _population_controller: Node
var _gecs_world: Node
var _world_time: Node
var _pending_spawn_position := Vector3.ZERO
var _request_pending := false


func initialize(context: BootstrapContext) -> void:
	_context = context
	_root_scene = context.root_scene
	_appearance_controller = context.get_optional(APPEARANCE_SERVICE_ID)
	_population_controller = context.get_optional(POPULATION_SERVICE_ID)
	_gecs_world = context.get_optional(GECS_WORLD_SERVICE_ID)
	_world_time = context.get_optional(WORLD_TIME_SERVICE_ID)
	if _appearance_controller != null:
		if _appearance_controller.has_signal("creation_completed") and not _appearance_controller.creation_completed.is_connected(_on_creation_completed):
			_appearance_controller.creation_completed.connect(_on_creation_completed)
		if _appearance_controller.has_signal("creation_cancelled") and not _appearance_controller.creation_cancelled.is_connected(_on_creation_cancelled):
			_appearance_controller.creation_cancelled.connect(_on_creation_cancelled)


func open_at(spawn_position: Vector3) -> bool:
	if _request_pending or _appearance_controller == null or not _appearance_controller.has_method("open_creation_editor"):
		return false
	_pending_spawn_position = spawn_position
	_request_pending = true
	if bool(_appearance_controller.call("open_creation_editor", REQUEST_ID)):
		return true
	_request_pending = false
	return false


func spawn_debug_party_character(appearance: Resource, character_name: String, age_years: int, spawn_position: Vector3) -> HumanoidCharacter:
	if appearance == null or _root_scene == null or _population_controller == null or _gecs_world == null:
		return null
	var party_root := _root_scene.get_node_or_null("PartyMembers") as Node3D
	var party_manager := _root_scene.get_node_or_null("PartyManager") as PartyManager
	if party_root == null or party_manager == null:
		return null
	var member := PARTY_MEMBER_SCENE.instantiate() as HumanoidCharacter
	if member == null:
		return null
	var actor_id := "player.created.%s" % Crypto.new().generate_random_bytes(16).hex_encode()
	member.name = "CreatedCharacter_%s" % actor_id.right(8)
	member.stable_id = actor_id
	member.member_name = character_name.strip_edges() if not character_name.strip_edges().is_empty() else "Wanderer"
	member.faction_name = _party_faction(party_manager)
	member.squad_name = _party_squad(party_manager)
	var canonical_appearance := (appearance.make_copy() if appearance.has_method("make_copy") else appearance) as CharacterAppearanceData
	if canonical_appearance == null:
		member.free()
		return null
	canonical_appearance.visual_age_years = age_years
	member.appearance_data = canonical_appearance
	member.set_meta("population_birth_day_index", CharacterAgeRules.birth_day_for_age(age_years, _current_world_day()))
	member.set_meta("population_age_years", age_years)
	member.set_meta("party_id", PartyManager.PLAYER_PARTY_ID)
	member.set_meta(DEFER_POPULATION_REGISTRATION_META, true)
	member.starting_items = [_make_stock(SILVER_ITEM, 10)]
	member.starting_equipment = [PEASANT_TUNIC, PEASANT_TROUSERS, PEASANT_SHOES, IRON_SWORD, ROUND_SHIELD]
	member.position = party_root.to_local(spawn_position)
	party_root.add_child(member)
	member.global_position = spawn_position
	var gecs_actor_id := str(_gecs_world.call("register_actor", member, "", {"role_id": "player_party"}))
	if gecs_actor_id.is_empty():
		member.queue_free()
		return null
	member.remove_meta(DEFER_POPULATION_REGISTRATION_META)
	var record: Dictionary = _population_controller.call("register_actor", member, "", {"role_id": "player_party"})
	if record.is_empty():
		if _gecs_world.has_method("unregister_actor"):
			_gecs_world.call("unregister_actor", member)
		member.queue_free()
		return null
	party_manager.register_party_member(member)
	party_manager.select_only(member)
	return member


func _on_creation_completed(appearance: Resource, character_name: String, age_years: int, request_id: StringName) -> void:
	if not _request_pending or request_id != REQUEST_ID:
		return
	_request_pending = false
	var member := spawn_debug_party_character(appearance, character_name, age_years, _pending_spawn_position)
	if member == null:
		creation_finished.emit(false, "Character creation failed.", null)
		return
	creation_finished.emit(true, "%s joined the party." % member.member_name, member)


func _on_creation_cancelled(request_id: StringName) -> void:
	if not _request_pending or request_id != REQUEST_ID:
		return
	_request_pending = false
	creation_finished.emit(false, "Character creation cancelled.", null)


func _current_world_day() -> int:
	return int(_world_time.call("get_day_index")) if _world_time != null and _world_time.has_method("get_day_index") else 0


func _party_faction(party_manager: PartyManager) -> String:
	for actor in party_manager.party_members:
		var faction := str(actor.faction_name).strip_edges()
		if not faction.is_empty():
			return faction
	return "Player"


func _party_squad(party_manager: PartyManager) -> String:
	for actor in party_manager.party_members:
		var squad := str(actor.squad_name).strip_edges()
		if not squad.is_empty():
			return squad
	return "Drifters"


func _make_stock(item_definition: ItemDefinition, quantity: int) -> Resource:
	var stock := INVENTORY_STOCK_SCRIPT.new()
	stock.item_definition = item_definition
	stock.quantity = quantity
	return stock
