extends CharacterBody3D

class_name PartyMember

@export var member_name := "Party Member"
@export var base_color := Color(0.7, 0.7, 0.7, 1.0)
@export var selected_color := Color(1.0, 0.88, 0.48, 1.0)
@export var focused_color := Color(1.0, 0.97, 0.7, 1.0)
@export var move_speed := 4.5
@export var acceleration := 10.0
@export var interact_distance := 1.8
@export var inventory_columns := 10
@export var inventory_rows := 6
@export var max_carry_weight := 60.0
@export var show_nameplate := true

var is_selected := false
var is_focused := false
var inventory
var _move_target := Vector3.ZERO
var _has_move_target := false
var _current_mining_node
var _mining_progress_by_node: Dictionary = {}
var _mining_active := false
var _current_container_target

@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var selection_ring: MeshInstance3D = $SelectionRing

var _body_material := StandardMaterial3D.new()
var _ring_material := StandardMaterial3D.new()
var _nameplate: Label3D

signal inventory_changed
signal mining_changed
signal container_reached(member, container)


func _ready() -> void:
	var inventory_data_script = load("res://scripts/items/inventory_data.gd")
	inventory = inventory_data_script.new(inventory_columns, inventory_rows, max_carry_weight)
	inventory.changed.connect(_on_inventory_data_changed)
	add_to_group("party_member")
	_body_material.roughness = 0.85
	_body_material.albedo_color = base_color
	body_mesh.material_override = _body_material

	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	selection_ring.material_override = _ring_material
	_setup_nameplate()
	_update_visuals()


func _physics_process(delta: float) -> void:
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if _has_move_target:
		var to_target := _move_target - global_position
		to_target.y = 0.0
		if to_target.length() <= 0.1:
			_has_move_target = false
			horizontal_velocity = Vector3.ZERO
		else:
			var direction := to_target.normalized()
			horizontal_velocity = horizontal_velocity.lerp(direction * move_speed, min(1.0, acceleration * delta))
			look_at(global_position + direction, Vector3.UP)
	else:
		horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, min(1.0, acceleration * delta))

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	move_and_slide()
	_process_mining(delta)
	_process_container_interaction()


func set_selected(value: bool) -> void:
	is_selected = value
	_update_visuals()


func set_focused(value: bool) -> void:
	is_focused = value
	_update_visuals()


func set_move_target(target: Vector3) -> void:
	_mining_active = false
	stop_container_interaction()
	mining_changed.emit()
	_move_target = target
	_has_move_target = true


func stop_mining_assignment() -> void:
	if _current_mining_node != null:
		_current_mining_node.release_miner(self)
	_current_mining_node = null
	_mining_active = false
	mining_changed.emit()


func stop_container_interaction() -> void:
	if _current_container_target != null and _current_container_target.has_method("release_interactor"):
		_current_container_target.release_interactor(self)
	_current_container_target = null


func assign_open_container(container) -> void:
	if container == null:
		return
	if _current_container_target != null and _current_container_target != container and _current_container_target.has_method("release_interactor"):
		_current_container_target.release_interactor(self)
	_current_container_target = container
	if _current_container_target.has_method("register_interactor"):
		_current_container_target.register_interactor(self)
	var target: Vector3 = _current_container_target.get_interaction_position(self)
	_move_target = target
	_has_move_target = true


func assign_mining_resource(resource_node) -> void:
	if resource_node == null:
		return
	if _current_mining_node != null and _current_mining_node != resource_node:
		_current_mining_node.release_miner(self)
	_current_mining_node = resource_node
	_current_mining_node.register_miner(self)
	_mining_active = false
	var target: Vector3 = _current_mining_node.get_mining_position(self)
	_move_target = target
	_has_move_target = true
	mining_changed.emit()


func has_mining_assignment() -> bool:
	return _current_mining_node != null


func is_actively_mining() -> bool:
	return _mining_active


func get_mining_progress_ratio() -> float:
	if _current_mining_node == null:
		return 0.0
	return minf(_get_stored_mining_progress(_current_mining_node) / _current_mining_node.mine_duration, 1.0)


func _process_mining(delta: float) -> void:
	if _current_mining_node == null:
		return

	var mining_position: Vector3 = _current_mining_node.get_mining_position(self)
	if global_position.distance_to(mining_position) > interact_distance:
		if not _has_move_target:
			_move_target = mining_position
			_has_move_target = true
			_mining_active = false
			mining_changed.emit()
		return

	if _has_move_target:
		return

	_mining_active = true
	var progress := _get_stored_mining_progress(_current_mining_node) + delta
	var duration := maxf(_current_mining_node.mine_duration, 0.01)
	if progress >= duration:
		if inventory.add_item(_current_mining_node.item_definition):
			progress = 0.0
		else:
			progress = duration
			_mining_active = false

	_store_mining_progress(_current_mining_node, progress)
	mining_changed.emit()


func _process_container_interaction() -> void:
	if _current_container_target == null:
		return
	var interaction_position: Vector3 = _current_container_target.get_interaction_position(self)
	if global_position.distance_to(interaction_position) > interact_distance:
		if not _has_move_target:
			_move_target = interaction_position
			_has_move_target = true
		return
	if _has_move_target:
		return
	var container = _current_container_target
	_current_container_target = null
	container_reached.emit(self, container)


func _get_stored_mining_progress(resource_node) -> float:
	return _mining_progress_by_node.get(resource_node.get_instance_id(), 0.0)


func _store_mining_progress(resource_node, progress: float) -> void:
	_mining_progress_by_node[resource_node.get_instance_id()] = progress


func _on_inventory_data_changed() -> void:
	inventory_changed.emit()


func get_inventory_display_name() -> String:
	return member_name


func get_inventory_world_position() -> Vector3:
	return global_position


func get_inventory_cell_size() -> Vector2:
	return Vector2(30.0, 30.0)


func shows_inventory_weight() -> bool:
	return true


func _setup_nameplate() -> void:
	if not show_nameplate:
		return
	_nameplate = get_node_or_null("Nameplate")
	if _nameplate == null:
		_nameplate = Label3D.new()
		_nameplate.name = "Nameplate"
		add_child(_nameplate)
	_nameplate.text = member_name
	_nameplate.position = Vector3(0.0, 2.15, 0.0)
	_nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nameplate.no_depth_test = false
	_nameplate.font_size = 50
	_nameplate.modulate = Color(0.56, 0.56, 0.6, 0.96)
	_nameplate.outline_size = 0
	_nameplate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _update_visuals() -> void:
	var body_color := base_color
	if is_selected:
		body_color = base_color.lerp(selected_color, 0.4)
	if is_focused:
		body_color = body_color.lerp(focused_color, 0.45)
	_body_material.albedo_color = body_color

	selection_ring.visible = is_selected or is_focused
	if is_focused:
		_ring_material.albedo_color = focused_color
	elif is_selected:
		_ring_material.albedo_color = selected_color
