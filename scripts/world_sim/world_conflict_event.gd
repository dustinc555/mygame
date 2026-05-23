extends Node3D

class_name WorldConflictEvent

@export var event_id := ""
@export var title := "Nearby Conflict"
@export_multiline var description := ""
@export var side_a_faction_id := ""
@export var side_a_label := "Side A"
@export var side_b_faction_id := ""
@export var side_b_label := "Side B"
@export var event_radius := 35.0
@export var participation_seconds_required := 20.0
@export var reputation_gain := 10
@export var favor_gain := 1
@export var opposed_reputation_loss := -5
@export var side_a_actor_paths: Array[NodePath] = []
@export var side_b_actor_paths: Array[NodePath] = []

var prompted := false
var ignored := false
var committed := false
var completed := false
var chosen_faction_id := ""
var opposed_faction_id := ""
var participation_seconds := 0.0


func configure(data: Dictionary) -> void:
	event_id = str(data.get("event_id", event_id))
	title = str(data.get("title", title))
	description = str(data.get("description", description))
	side_a_faction_id = str(data.get("side_a_faction_id", side_a_faction_id))
	side_a_label = str(data.get("side_a_label", side_a_label))
	side_b_faction_id = str(data.get("side_b_faction_id", side_b_faction_id))
	side_b_label = str(data.get("side_b_label", side_b_label))
	event_radius = float(data.get("event_radius", event_radius))
	participation_seconds_required = float(data.get("participation_seconds_required", participation_seconds_required))
	reputation_gain = int(data.get("reputation_gain", reputation_gain))
	favor_gain = int(data.get("favor_gain", favor_gain))
	opposed_reputation_loss = int(data.get("opposed_reputation_loss", opposed_reputation_loss))
	if data.has("world_position") and data["world_position"] is Vector3:
		global_position = data["world_position"]
	side_a_actor_paths = _node_path_array(data.get("side_a_actor_paths", side_a_actor_paths))
	side_b_actor_paths = _node_path_array(data.get("side_b_actor_paths", side_b_actor_paths))


func choose_side(faction_id: String, root_scene: Node) -> void:
	if completed or ignored or committed:
		return
	if faction_id != side_a_faction_id and faction_id != side_b_faction_id:
		return
	committed = true
	chosen_faction_id = faction_id
	opposed_faction_id = side_b_faction_id if faction_id == side_a_faction_id else side_a_faction_id
	_apply_temporary_hostility(root_scene)


func ignore() -> void:
	if completed or committed:
		return
	ignored = true
	prompted = true


func process_participation(delta: float, root_scene: Node, faction_controller: Node) -> void:
	if completed or ignored or not committed:
		return
	if not is_player_in_radius(root_scene):
		return
	participation_seconds += maxf(delta, 0.0)
	if participation_seconds < participation_seconds_required:
		return
	completed = true
	if faction_controller != null and faction_controller.has_method("apply_helped_faction_result"):
		faction_controller.call("apply_helped_faction_result", chosen_faction_id, opposed_faction_id, reputation_gain, favor_gain, opposed_reputation_loss)


func is_player_in_radius(root_scene: Node) -> bool:
	if root_scene == null or not is_inside_tree():
		return false
	for actor in get_tree().get_nodes_in_group("party_member"):
		if actor is Node3D and actor.global_position.distance_to(global_position) <= event_radius:
			return true
	return false


func _apply_temporary_hostility(root_scene: Node) -> void:
	if root_scene == null:
		return
	var opposed_paths := side_b_actor_paths if opposed_faction_id == side_b_faction_id else side_a_actor_paths
	for party_actor in get_tree().get_nodes_in_group("party_member"):
		if not (party_actor is HumanoidCharacter):
			continue
		for path in opposed_paths:
			var opposed_actor := root_scene.get_node_or_null(path)
			if opposed_actor is HumanoidCharacter:
				party_actor.mark_hostile(opposed_actor)
				opposed_actor.mark_hostile(party_actor)


func _node_path_array(value) -> Array[NodePath]:
	var result: Array[NodePath] = []
	if value is Array:
		for item in value:
			result.append(item if item is NodePath else NodePath(str(item)))
	return result
