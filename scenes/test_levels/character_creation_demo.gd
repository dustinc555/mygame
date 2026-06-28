extends Node3D

const PARTY_MEMBER_SCENE := preload("res://features/core/party/party_member.tscn")
const INVENTORY_STOCK_SCRIPT := preload("res://features/inventory/resources/items/inventory_stock.gd")
const SILVER_ITEM := preload("res://features/inventory/resources/items/silver.tres")
const PEASANT_TUNIC := preload("res://features/inventory/resources/items/peasant_tunic.tres")
const PEASANT_TROUSERS := preload("res://features/inventory/resources/items/peasant_trousers.tres")
const PEASANT_SHOES := preload("res://features/inventory/resources/items/peasant_shoes.tres")
const IRON_SWORD := preload("res://features/inventory/resources/items/iron_sword.tres")
const ROUND_SHIELD := preload("res://features/inventory/resources/items/round_shield.tres")

@export var auto_open_editor := true

var created_member: HumanoidCharacter
var _creation_opened := false


func _ready() -> void:
	call_deferred("_deferred_setup")


func _deferred_setup() -> void:
	var appearance_controller := await _wait_for_appearance_controller()
	if appearance_controller == null:
		return
	var creation_saved_callable := Callable(self, "_on_creation_saved")
	if appearance_controller.has_signal("creation_saved") and not appearance_controller.is_connected("creation_saved", creation_saved_callable):
		appearance_controller.connect("creation_saved", creation_saved_callable)
	if auto_open_editor and not _creation_opened:
		_creation_opened = bool(appearance_controller.open_creation_editor())


func spawn_created_character(appearance: Resource, character_name := "") -> HumanoidCharacter:
	if appearance == null:
		return null
	var party_root := get_node_or_null("PartyMembers") as Node3D
	if party_root == null:
		return null
	var member := PARTY_MEMBER_SCENE.instantiate() as HumanoidCharacter
	if member == null:
		return null
	member.name = "CreatedCharacter"
	member.member_name = character_name.strip_edges() if not character_name.strip_edges().is_empty() else "Wanderer"
	member.faction_name = "Player"
	member.appearance_data = appearance.make_copy() if appearance.has_method("make_copy") else appearance
	member.character_race = member.appearance_data.character_race
	member.body_archetype = member.appearance_data.body_archetype
	member.visual_body_type = member.appearance_data.visual_body_type
	member.starting_items = [_make_stock(SILVER_ITEM, 10)]
	member.starting_equipment = [PEASANT_TUNIC, PEASANT_TROUSERS, PEASANT_SHOES, IRON_SWORD, ROUND_SHIELD]
	party_root.add_child(member)
	var spawn_marker := get_node_or_null("CharacterSpawn") as Node3D
	if spawn_marker != null:
		member.global_transform = spawn_marker.global_transform
	created_member = member
	var party_manager := get_node_or_null("PartyManager") as PartyManager
	if party_manager != null:
		party_manager.register_party_member(member)
		party_manager.select_only(member)
	return member


func get_created_member() -> HumanoidCharacter:
	return created_member


func _on_creation_saved(appearance: Resource, character_name: String) -> void:
	spawn_created_character(appearance, character_name)


func _make_stock(item_definition: ItemDefinition, quantity: int) -> Resource:
	var stock := INVENTORY_STOCK_SCRIPT.new()
	stock.item_definition = item_definition
	stock.quantity = quantity
	return stock


func _wait_for_appearance_controller() -> Node:
	for _index in range(60):
		var controller := BootstrapContext.service(CharacterAppearanceController.SERVICE_ID)
		if controller != null:
			return controller
		await get_tree().process_frame
	return null
