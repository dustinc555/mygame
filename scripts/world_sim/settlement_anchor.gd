extends Node3D

class_name SettlementAnchor

@export var settlement_definition: Resource
@export var resident_root_path: NodePath
@export var raid_spawn_path: NodePath
@export var defense_spawn_path: NodePath
@export var storage_paths: Array[NodePath] = []
@export var state_label_path: NodePath


func _ready() -> void:
	add_to_group("settlement_anchor")


func get_settlement_id() -> String:
	return str(settlement_definition.call("get_id")) if settlement_definition != null and settlement_definition.has_method("get_id") else name


func get_spawn_position(role := "") -> Vector3:
	var spawn_path := raid_spawn_path if role == "raid" else defense_spawn_path
	var marker := get_node_or_null(spawn_path) as Node3D
	if marker != null:
		return marker.global_position
	return global_position


func get_resident_characters() -> Array:
	var residents: Array = []
	var root := get_node_or_null(resident_root_path)
	if root == null:
		root = self
	_collect_residents(root, residents)
	return residents


func get_storage_nodes() -> Array[Node]:
	var result: Array[Node] = []
	for storage_path in storage_paths:
		var storage := get_node_or_null(storage_path)
		if storage != null:
			result.append(storage)
	return result


func apply_settlement_state(state: Dictionary) -> void:
	var label := get_node_or_null(state_label_path) as Label3D
	if label == null:
		label = get_node_or_null("StateLabel") as Label3D
	if label == null:
		return
	label.text = "%s\nFOOD  %d / %d    %s\nPOP   %d / %d    %s\n%s" % [
		str(state.get("display_name", get_settlement_id())).to_upper(),
		int(round(float(state.get("food", 0.0)))),
		int(round(float(state.get("max_food", 0.0)))),
		str(state.get("pressure_state", "stable")).to_upper(),
		int(state.get("population", 0)),
		int(state.get("max_occupancy", 0)),
		str(state.get("occupancy_label", "Populated")).to_upper(),
		str(state.get("last_action", "Idle")).to_upper(),
	]


func _collect_residents(root: Node, residents: Array) -> void:
	for child in root.get_children():
		if child.has_method("assign_attack_target"):
			residents.append(child)
		_collect_residents(child, residents)
