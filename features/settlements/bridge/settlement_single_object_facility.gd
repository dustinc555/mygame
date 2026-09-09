@tool
extends SettlementFacilityInstance

class_name SettlementSingleObjectFacility

## Generic host for facilities that are one configured world object rather than
## a generated area or a building with furniture. The realized object is an
## internal, ownerless child: it renders and runs normally without manufacturing
## a scene-tree branch or being serialized into every town.
@export var object_scene: PackedScene:
	set(value):
		if object_scene == value:
			return
		object_scene = value
		_rebuild_single_object()
@export var object_property_overrides: Dictionary = {}:
	set(value):
		object_property_overrides = value.duplicate(true)
		apply_single_object_properties()

var _single_object: Node3D


func _repair_authoring_tree() -> void:
	composition = FacilityComposition.SINGLE_OBJECT
	building_root_path = NodePath("")
	staff_root_path = NodePath("")
	service_points_root_path = NodePath("")
	storage_root_path = NodePath("")
	job_providers_root_path = NodePath("")
	activity_points_root_path = NodePath("")
	# The inherited setter requests another repair. Only cross that setter once;
	# assigning false repeatedly would recursively redispatch this override.
	if auto_create_standard_roots:
		auto_create_standard_roots = false
	super._repair_authoring_tree()
	_ensure_single_object()


func get_single_object() -> Node3D:
	return _single_object if is_instance_valid(_single_object) else null


func is_single_object(node: Node) -> bool:
	return node != null and node == get_single_object()


func apply_single_object_properties() -> void:
	var object := get_single_object()
	if object == null:
		return
	for property_name_value in object_property_overrides:
		var property_name := str(property_name_value)
		if _has_property(object, property_name):
			object.set(property_name, object_property_overrides[property_name_value])
	_sync_single_object_identity(object)


func _ensure_single_object() -> void:
	if not is_inside_tree() or get_single_object() != null or object_scene == null:
		return
	var object := object_scene.instantiate() as Node3D
	if object == null:
		push_error("Single-object facility scene root must be Node3D: %s" % object_scene.resource_path)
		return
	object.name = "FacilityObject"
	_single_object = object
	# Child _ready captures authored contents for first bind/save-load. Configure
	# identity and overrides before entering the tree, not after that snapshot.
	apply_single_object_properties()
	add_child(object, false, Node.INTERNAL_MODE_FRONT)


func _rebuild_single_object() -> void:
	if is_instance_valid(_single_object):
		remove_child(_single_object)
		_single_object.free()
	_single_object = null
	_ensure_single_object()


func _sync_single_object_identity(object: Node) -> void:
	var clean_id := get_facility_id().strip_edges()
	if clean_id.is_empty():
		return
	if _has_property(object, "facility_id"):
		object.set("facility_id", clean_id)
	if _has_property(object, "liquid_container_id"):
		object.set("liquid_container_id", "%s.container" % clean_id)
	if _has_property(object, "source_id"):
		object.set("source_id", "%s.source" % clean_id)


func _has_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
