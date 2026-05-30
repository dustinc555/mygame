extends Control

class_name SelectionIndicatorOverlay

const RING_SEGMENTS := 72

@export var ring_world_radius := 0.76
@export var selected_color := Color(0.76, 0.78, 0.82, 0.5)
@export var focused_color := Color(1.0, 0.84, 0.28, 0.72)
@export var shadow_color := Color(0.0, 0.0, 0.0, 0.22)
@export var line_width := 2.0
@export var shadow_width := 4.0

var party_manager: PartyManager
var world_camera: Camera3D


func setup(manager: PartyManager, camera_3d: Camera3D) -> void:
	party_manager = manager
	world_camera = camera_3d
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(true)
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if party_manager == null or world_camera == null or not is_instance_valid(world_camera):
		return
	for member in party_manager.selected_members:
		_draw_member_ring(member, selected_color)
	var focused_member := party_manager.followed_member
	if focused_member != null and is_instance_valid(focused_member):
		_draw_member_ring(focused_member, focused_color)


func _draw_member_ring(member: HumanoidCharacter, color: Color) -> void:
	if member == null or not is_instance_valid(member) or not member.is_inside_tree():
		return
	var center := member.get_ground_marker_position(0.03)
	if world_camera.is_position_behind(center + Vector3.UP * 0.25):
		return
	var points := PackedVector2Array()
	for index in range(RING_SEGMENTS + 1):
		var angle := TAU * float(index) / float(RING_SEGMENTS)
		var world_point := center + Vector3(cos(angle), 0.0, sin(angle)) * ring_world_radius
		points.append(world_camera.unproject_position(world_point))
	if points.size() < 2:
		return
	draw_polyline(points, shadow_color, shadow_width, true)
	draw_polyline(points, color, line_width, true)
