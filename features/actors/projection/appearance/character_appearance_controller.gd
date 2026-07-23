extends Node

class_name CharacterAppearanceController

const SERVICE_ID := &"character_appearance"

signal creation_saved(draft_appearance, character_name)

const CHARACTER_EDITOR_SCENE = preload("res://features/ui/projection/character_editor.tscn")
const SILVER_ITEM = preload("res://features/inventory/resources/items/silver.tres")

const HAIR_STYLES: Array[Resource] = [
	preload("res://features/actors/resources/character_appearance/hair_buzzed.tres"),
	preload("res://features/actors/resources/character_appearance/hair_buzzed_female.tres"),
	preload("res://features/actors/resources/character_appearance/hair_simple_parted.tres"),
	preload("res://features/actors/resources/character_appearance/hair_long.tres"),
	preload("res://features/actors/resources/character_appearance/hair_buns.tres"),
]
const BEARD_STYLES: Array[Resource] = [
	preload("res://features/actors/resources/character_appearance/beard_full.tres"),
]
const EYEBROW_STYLES: Array[Resource] = [
	preload("res://features/actors/resources/character_appearance/eyebrows_regular.tres"),
	preload("res://features/actors/resources/character_appearance/eyebrows_female.tres"),
]

var root_scene: Node
var _context: BootstrapContext
var hud_layer: CanvasLayer
var world_time: Node
var floating_notice: FloatingNotice
var editor_window
var _initialized := false
var _appearance_pause_requested := false


func initialize(context: BootstrapContext) -> void:
	root_scene = context.root_scene
	hud_layer = context.hud_layer
	_context = context
	if is_inside_tree():
		_do_initialize()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if root_scene != null:
		if hud_layer == null:
			hud_layer = root_scene.get_node_or_null("GameHUD")
		_do_initialize()


func _do_initialize() -> void:
	if _initialized or root_scene == null:
		return
	if hud_layer == null:
		hud_layer = root_scene.get_node_or_null("GameHUD")
	if hud_layer == null:
		return
	world_time = _context.get_optional(WorldTimeController.SERVICE_ID) if _context != null else null
	floating_notice = hud_layer.get_node_or_null("FloatingNotice") as FloatingNotice
	_ensure_editor_window()
	_initialized = true


func open_creation_editor() -> bool:
	_ensure_editor_window()
	if editor_window == null:
		return false
	_request_editor_pause()
	editor_window.open_for_actor(null, "creation")
	editor_window.move_to_front()
	return true


func open_barber_editor(actor: HumanoidCharacter, barber: Node = null) -> bool:
	if actor == null or actor.inventory == null:
		return false
	if not _ensure_durable_actor(actor):
		_show_message("Character record unavailable")
		return false
	_ensure_editor_window()
	if editor_window == null:
		return false
	var price := _get_barber_price(barber)
	if price > 0:
		if actor.inventory.count_item(SILVER_ITEM) < price:
			_show_message("Need %d silver" % price)
			if barber != null and barber.has_method("show_world_speech"):
				barber.show_world_speech("Come back with %d silver." % price, 4.0)
			return false
		if not actor.inventory.remove_item_count(SILVER_ITEM, price):
			_show_message("Need %d silver" % price)
			return false
	_request_editor_pause()
	editor_window.open_for_actor(actor, "barber")
	editor_window.move_to_front()
	return true


func is_editor_open() -> bool:
	return editor_window != null and editor_window.visible


func get_editor_window():
	_ensure_editor_window()
	return editor_window


func _ensure_editor_window() -> void:
	if editor_window != null and is_instance_valid(editor_window):
		return
	if hud_layer == null:
		return
	editor_window = CHARACTER_EDITOR_SCENE.instantiate()
	editor_window.name = "CharacterEditor"
	editor_window.process_mode = Node.PROCESS_MODE_ALWAYS
	hud_layer.add_child(editor_window)
	editor_window.configure_styles(HAIR_STYLES, BEARD_STYLES, EYEBROW_STYLES)
	editor_window.save_requested.connect(_on_editor_save_requested)
	editor_window.cancel_requested.connect(_on_editor_cancel_requested)


func _on_editor_save_requested(actor, draft_appearance) -> void:
	if actor == null:
		creation_saved.emit(draft_appearance, editor_window.get_character_name() if editor_window != null and editor_window.has_method("get_character_name") else "")
	elif draft_appearance != null and actor.has_method("apply_appearance_data"):
		var population := _context.get_optional(&"population") if _context != null else null
		_ensure_durable_actor(actor)
		var actor_id := str(actor.get_meta("actor_record_id", actor.get("stable_id"))).strip_edges()
		var record: Dictionary = population.call("update_actor_appearance", actor_id, draft_appearance) if population != null and population.has_method("update_actor_appearance") else {}
		var canonical_appearance = PopulationController.appearance_from_record(record.get("appearance", {}) as Dictionary)
		if canonical_appearance == null:
			push_error("Appearance save rejected: actor '%s' has no durable population record" % actor_id)
		else:
			actor.apply_appearance_data(canonical_appearance)
			_show_message("Appearance saved")
	_release_editor_pause()


func _ensure_durable_actor(actor: Node) -> bool:
	var population := _context.get_optional(&"population") if _context != null else null
	if population == null or not population.has_method("get_actor_record"):
		return false
	var actor_id := str(actor.get_meta("actor_record_id", actor.get("stable_id"))).strip_edges()
	if actor_id.is_empty():
		return false
	if (population.call("get_actor_record", actor_id) as Dictionary).is_empty() and population.has_method("register_actor"):
		population.call("register_actor", actor)
	return not (population.call("get_actor_record", actor_id) as Dictionary).is_empty()


func _on_editor_cancel_requested() -> void:
	_release_editor_pause()


func _request_editor_pause() -> void:
	if _appearance_pause_requested:
		return
	if world_time == null:
		world_time = _context.get_optional(WorldTimeController.SERVICE_ID) if _context != null else null
	if world_time != null and world_time.has_method("request_appearance_editor_pause"):
		_appearance_pause_requested = bool(world_time.call("request_appearance_editor_pause"))


func _release_editor_pause() -> void:
	if not _appearance_pause_requested:
		return
	_appearance_pause_requested = false
	if world_time == null:
		world_time = _context.get_optional(WorldTimeController.SERVICE_ID) if _context != null else null
	if world_time != null and world_time.has_method("release_appearance_editor_pause"):
		world_time.call("release_appearance_editor_pause")


func _get_barber_price(barber: Node) -> int:
	if barber != null and barber.has_method("get_barber_service_price"):
		return maxi(0, int(barber.call("get_barber_service_price")))
	if barber != null and barber.has_meta("barber_service_price"):
		return maxi(0, int(barber.get_meta("barber_service_price")))
	return 1


func _show_message(message: String) -> void:
	if floating_notice != null:
		floating_notice.show_message(message)
