extends Node

class_name PopulationCharacterRealizer

const SERVICE_ID := &"population_character_realizer"
const SELECTION_RING_VISUAL = preload("res://features/actors/projection/selection_ring_visual.gd")

var _context: BootstrapContext
var _population: PopulationController
var _factions: FactionController


func initialize(context: BootstrapContext) -> void:
	_context = context
	_population = context.require(PopulationController.SERVICE_ID) as PopulationController
	_factions = context.require(FactionController.SERVICE_ID) as FactionController


func realize_actor(actor_id: String, role_owner: Node, parent: Node, node_name := "", requested_character_type_id := "") -> Node:
	if actor_id.strip_edges().is_empty() or role_owner == null or parent == null:
		_fail(actor_id, role_owner, "missing actor id, role owner, or parent")
		return null
	var record := _population.get_actor_record(actor_id)
	if record.is_empty():
		_fail(actor_id, role_owner, "population record does not exist")
		return null
	var realizer := resolve_effective_realizer(role_owner, record)
	if not _valid_realizer(realizer):
		_fail(actor_id, role_owner, "no valid character realizer resolves from facility -> town -> faction")
		return null
	record = _population.ensure_record_character_realizer(actor_id, realizer, resolve_effective_name_profile(role_owner, record))
	var type_set := resolve_effective_character_type_set(role_owner, record)
	var role_id := str(record.get("role_id", "resident")).strip_edges().to_lower()
	var character_type := type_set.call("resolve_character_type", requested_character_type_id, role_id) as Resource if type_set != null and type_set.has_method("resolve_character_type") else null
	if character_type == null:
		_fail(actor_id, role_owner, "no valid Character Type resolves from facility -> town -> faction")
		return null
	record = _population.ensure_record_character_type(actor_id, character_type)
	if not _valid_record(record):
		_fail(actor_id, role_owner, "realizer produced an incomplete population record")
		return null
	var actor_script := realizer.get("actor_script") as Script
	var actor := _population.get_live_actor(actor_id)
	var prior_realizer_id := str(actor.get_meta("population_character_realizer_id", "")) if actor != null else ""
	var prior_type_id := str(actor.get_meta("population_character_type_id", "")) if actor != null else ""
	if actor != null and actor.get_script() != actor_script:
		_fail(actor_id, role_owner, "live actor class does not match effective realizer")
		return null
	if actor == null:
		actor = actor_script.new() as Node
		if actor == null or not (actor is Node3D):
			_fail(actor_id, role_owner, "realizer actor script did not create a Node3D")
			if actor != null:
				actor.free()
			return null
		actor.name = node_name if not node_name.is_empty() else actor_id.to_pascal_case()
		_population.apply_record_to_actor(actor, record)
		_ensure_projection_bootstrap(actor)
		parent.add_child(actor)
	else:
		_reparent_preserving_transform(actor, parent)
		_population.apply_record_to_actor(actor, record)
		if prior_realizer_id != _realizer_id(realizer) and actor.has_method("apply_appearance_data"):
			actor.call("apply_appearance_data", actor.get("appearance_data"))
		if prior_type_id != str(character_type.get("type_id")) and actor.has_method("get_equipment"):
			var equipment = actor.call("get_equipment")
			if equipment != null and equipment.has_method("seed_starting_equipment_from_actor"):
				equipment.call("seed_starting_equipment_from_actor")
	if not node_name.is_empty():
		actor.name = node_name
	actor.set_meta("population_character_realizer_id", _realizer_id(realizer))
	actor.set_meta("population_character_type_id", str(character_type.get("type_id")))
	_population.mark_actor_realized(actor, actor_id)
	return actor


func realize_record_actor(actor_id: String, parent: Node, node_name := "") -> Node:
	if actor_id.is_empty() or parent == null:
		return null
	var record := _population.get_actor_record(actor_id)
	if record.is_empty():
		return null
	var actor_script := load(str(record.get("actor_script_path", ""))) as Script if not str(record.get("actor_script_path", "")).is_empty() else null
	if actor_script == null:
		return realize_actor(actor_id, parent, parent, node_name)
	var actor := _population.get_live_actor(actor_id)
	if actor == null:
		actor = actor_script.new() as Node
		if actor == null or not (actor is Node3D):
			if actor != null:
				actor.free()
			return null
		actor.name = node_name if not node_name.is_empty() else actor_id.to_pascal_case()
		_population.apply_record_to_actor(actor, record)
		_ensure_projection_bootstrap(actor)
		parent.add_child(actor)
	else:
		_reparent_preserving_transform(actor, parent)
		_population.apply_record_to_actor(actor, record)
	if int(record.get("life_state", NpcRules.LifeState.ALIVE)) == NpcRules.LifeState.DEAD and actor.has_method("set_player_party_member"):
		actor.call("set_player_party_member", false)
	_population.mark_actor_realized(actor, actor_id)
	return actor


func resolve_effective_realizer(role_owner: Node, record: Dictionary = {}) -> Resource:
	if role_owner != null and role_owner.has_method("get_effective_character_realizer"):
		var effective := role_owner.call("get_effective_character_realizer") as Resource
		if effective != null:
			return effective
	var direct := _resource_property(role_owner, "population_appearance_profile")
	if direct != null:
		return direct
	var definition := _settlement_definition(role_owner)
	if definition != null and definition.has_method("get_character_realizer"):
		var inherited := definition.call("get_character_realizer") as Resource
		if inherited != null:
			return inherited
	var faction_id := str(record.get("faction_id", "")).strip_edges()
	if faction_id.is_empty() and role_owner.has_method("get_property_owner_faction"):
		faction_id = str(role_owner.call("get_property_owner_faction")).strip_edges()
	var faction := _factions.get_faction_definition(faction_id) if _factions != null else null
	return faction.call("get_character_realizer") as Resource if faction != null and faction.has_method("get_character_realizer") else null


func resolve_effective_character_type_set(role_owner: Node, record: Dictionary = {}) -> Resource:
	if role_owner != null and role_owner.has_method("get_effective_character_type_set"):
		var effective := role_owner.call("get_effective_character_type_set") as Resource
		if effective != null:
			return effective
	var direct := _resource_property(role_owner, "character_type_set")
	if direct != null:
		return direct
	var definition := _settlement_definition(role_owner)
	if definition != null and definition.has_method("get_character_type_set"):
		var inherited := definition.call("get_character_type_set") as Resource
		if inherited != null:
			return inherited
	var faction_id := str(record.get("faction_id", "")).strip_edges()
	if faction_id.is_empty() and role_owner.has_method("get_property_owner_faction"):
		faction_id = str(role_owner.call("get_property_owner_faction")).strip_edges()
	var faction := _factions.get_faction_definition(faction_id) if _factions != null else null
	return faction.call("get_character_type_set") as Resource if faction != null and faction.has_method("get_character_type_set") else null


func resolve_effective_name_profile(role_owner: Node, record: Dictionary = {}) -> Resource:
	var direct := _resource_property(role_owner, "population_name_profile")
	if direct != null:
		return direct
	var definition := _settlement_definition(role_owner)
	if definition != null and definition.has_method("get_population_name_profile"):
		var inherited := definition.call("get_population_name_profile") as Resource
		if inherited != null:
			return inherited
	var faction_id := str(record.get("faction_id", "")).strip_edges()
	var faction := _factions.get_faction_definition(faction_id) if _factions != null else null
	return faction.call("get_population_name_profile") as Resource if faction != null and faction.has_method("get_population_name_profile") else null


func _valid_realizer(realizer: Resource) -> bool:
	return realizer != null \
		and realizer.has_method("create_appearance") \
		and realizer.get("actor_script") is Script \
		and not _realizer_id(realizer).is_empty()


func _valid_record(record: Dictionary) -> bool:
	return not str(record.get("actor_id", "")).strip_edges().is_empty() \
		and not str(record.get("faction_id", "")).strip_edges().is_empty() \
		and not str(record.get("member_name", "")).strip_edges().is_empty() \
		and not (record.get("appearance", {}) as Dictionary).is_empty() \
		and not str(record.get("character_realizer_id", "")).strip_edges().is_empty()


func _ensure_projection_bootstrap(actor: Node) -> void:
	if not (actor is HumanoidCharacter):
		return
	if actor.get_node_or_null("CollisionShape3D") == null:
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		collision.position = Vector3(0.0, 0.95, 0.0)
		var shape := CapsuleShape3D.new()
		shape.radius = 0.4
		shape.height = 1.1
		collision.shape = shape
		actor.add_child(collision)
	if actor.get_node_or_null("BodyMesh") == null:
		var body := MeshInstance3D.new()
		body.name = "BodyMesh"
		body.position = Vector3(0.0, 0.95, 0.0)
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.4
		body.mesh = mesh
		actor.add_child(body)
	if actor.get_node_or_null("SelectionRing") == null:
		var ring := MeshInstance3D.new()
		ring.name = "SelectionRing"
		ring.position = Vector3(0.0, 0.03, 0.0)
		ring.visible = false
		SELECTION_RING_VISUAL.setup_ring(ring)
		actor.add_child(ring)


func _reparent_preserving_transform(actor: Node, parent: Node) -> void:
	if actor.get_parent() == parent:
		return
	var transform := (actor as Node3D).global_transform if actor is Node3D else Transform3D.IDENTITY
	if actor.get_parent() != null:
		actor.get_parent().remove_child(actor)
	parent.add_child(actor)
	if actor is Node3D:
		(actor as Node3D).global_transform = transform


func _settlement_definition(node: Node) -> SettlementDefinition:
	var current := node
	while current != null:
		var value = _resource_property(current, "settlement_definition")
		if value is SettlementDefinition:
			return value
		current = current.get_parent()
	return null


func _resource_property(node: Node, property_name: String) -> Resource:
	if node == null:
		return null
	for property in node.get_property_list():
		if str(property.get("name", "")) == property_name:
			return node.get(property_name) as Resource
	return null


func _realizer_id(realizer: Resource) -> String:
	return str(realizer.get("profile_id")).strip_edges() if realizer != null else ""


func _fail(actor_id: String, role_owner: Node, reason: String) -> void:
	push_error("Character realization rejected: actor=%s owner=%s reason=%s" % [actor_id, str(role_owner.get_path()) if role_owner != null and role_owner.is_inside_tree() else str(role_owner), reason])
