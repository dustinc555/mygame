@tool
extends StaticBody3D

class_name ShopCounter

## Counter a bartender/shopkeeper works behind using the Counter_* animation
## set (Counter_Enter -> Counter_Idle while serving; shop menu opens while
## the keeper holds the counter pose). Exposes the two working positions:
## staff side (red editor square) and customer side (green editor square).
## The markers are editor-only authoring aids — they are never built at
## runtime.

@export var furniture_type := FurnitureRules.Type.COUNTER
@export var facility_role_ids: Array[String] = []
## Where the keeper stands, local space (behind the counter).
@export var staff_stand_local_offset := Vector3(0.0, 0.0, -0.85):
	set(value):
		staff_stand_local_offset = value
		_update_editor_markers()
## Where a customer stands to talk/trade (front of the counter).
@export var customer_stand_local_offset := Vector3(0.0, 0.0, 0.85):
	set(value):
		customer_stand_local_offset = value
		_update_editor_markers()
@export var staff_work_radius := 0.5

var _staff_marker: MeshInstance3D
var _customer_marker: MeshInstance3D
var _assigned_worker: HumanoidCharacter


func _ready() -> void:
	add_to_group(FurnitureRules.FURNITURE_GROUP)
	add_to_group("shop_counter")
	# The imported convex hull spans the full model depth; with nav erosion it
	# eats BOTH standing fronts — customers can't reach the counter face and
	# the barkeeper can't take the service point. Only the authored slim box
	# may block a counter.
	FurnitureRules.strip_imported_collision(self)
	if Engine.is_editor_hint():
		_build_editor_markers()


func get_staff_stand_position() -> Vector3:
	return global_transform * staff_stand_local_offset


func supports_facility_role(role_id: String) -> bool:
	var normalized := role_id.strip_edges().to_lower()
	for candidate in facility_role_ids:
		if candidate.strip_edges().to_lower() == normalized:
			return true
	return false


func get_work_position() -> Vector3:
	return get_staff_stand_position()


func get_customer_position() -> Vector3:
	return global_transform * customer_stand_local_offset


## Yaw for the keeper so they face across the counter toward the customer.
func get_staff_facing_yaw() -> float:
	var direction := get_customer_position() - get_staff_stand_position()
	return atan2(direction.x, direction.z)


func claim_worker(worker: HumanoidCharacter) -> bool:
	if worker == null:
		return false
	if _assigned_worker != null and is_instance_valid(_assigned_worker) and _assigned_worker != worker:
		return false
	_assigned_worker = worker
	return true


func release_worker(worker: HumanoidCharacter) -> void:
	if _assigned_worker == worker:
		_assigned_worker = null


func is_available_for(worker: HumanoidCharacter) -> bool:
	return _assigned_worker == null or not is_instance_valid(_assigned_worker) or _assigned_worker == worker


func get_assigned_worker() -> HumanoidCharacter:
	return _assigned_worker if _assigned_worker != null and is_instance_valid(_assigned_worker) else null


func is_worker_at_point(worker: HumanoidCharacter) -> bool:
	return worker != null and worker.global_position.distance_to(get_staff_stand_position()) <= staff_work_radius


func _build_editor_markers() -> void:
	_staff_marker = _make_marker("StaffStandMarker", Color(0.9, 0.15, 0.1, 0.55))
	_customer_marker = _make_marker("CustomerStandMarker", Color(0.15, 0.85, 0.2, 0.55))
	_update_editor_markers()


func _make_marker(marker_name: String, color: Color) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = marker_name
	var quad := PlaneMesh.new()
	quad.size = Vector2(0.6, 0.6)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = material
	marker.mesh = quad
	add_child(marker)
	return marker


func _update_editor_markers() -> void:
	if _staff_marker != null and is_instance_valid(_staff_marker):
		_staff_marker.position = staff_stand_local_offset + Vector3(0.0, 0.02, 0.0)
	if _customer_marker != null and is_instance_valid(_customer_marker):
		_customer_marker.position = customer_stand_local_offset + Vector3(0.0, 0.02, 0.0)
