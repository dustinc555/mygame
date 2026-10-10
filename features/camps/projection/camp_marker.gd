@tool
@icon("res://features/camps/projection/camp_icon.svg")
extends Node3D
class_name CampMarker

## Stable save identity. The placement tool assigns this once; never reuse it.
@export var camp_id := ""
@export var faction: FactionDefinition = preload("res://features/factions/resources/factions/roaming_desert_thugs.tres")
@export var camp_type: Resource = preload("res://features/camps/resources/desert_thug_camp.tres")
@export_enum("Small", "Medium", "Large") var camp_size := 1
## Squad roaming distance only. Never controls furniture or resident spacing.
@export_range(10.0, 2000.0, 10.0, "or_greater", "suffix:m") var roaming_radius := 250.0
## Legacy serialized fields remain loadable, but cannot override compact size presets.
@export_storage var population := 0
@export_storage var camp_radius := 12.0
@export_storage var operational_radius: float = 250.0:
	get:
		return roaming_radius
	set(value):
		roaming_radius = value
@export_range(1, 4, 1) var squad_count := 2
@export_range(1, 20, 1) var squad_size := 3
@export var generation_seed := 1

func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh_marker()
		return
	add_to_group("camp_marker")
	add_to_group(BootstrapContext.SERVICE_CONSUMER_GROUP)
	if BootstrapContext.active != null:
		_on_bootstrap_context_ready(BootstrapContext.active)

func _on_bootstrap_context_ready(context: BootstrapContext) -> void:
	var camps := context.get_optional(&"camps")
	if camps != null:
		camps.call_deferred("register_marker", self)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if camp_id.strip_edges().is_empty():
		warnings.append("Assign a unique Camp ID before playing.")
	if camp_type != null and get_population() <= squad_count * squad_size:
		warnings.append("Population must leave at least one resident leader after patrol allocation.")
	if faction == null or camp_type == null:
		warnings.append("Assign both faction and camp type.")
	return warnings

func _refresh_marker() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var boundary := get_node_or_null("CampBoundary")
	if boundary != null:
		remove_child(boundary)
		boundary.queue_free()
	var marker := get_node_or_null("CampIcon") as Sprite3D
	if marker == null:
		marker = Sprite3D.new()
		marker.name = "CampIcon"
		add_child(marker)
	marker.texture = preload("res://features/camps/projection/camp_icon.svg")
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.shaded = false
	marker.pixel_size = 0.035
	marker.position.y = 1.5
	update_configuration_warnings()

func get_size_preset() -> Resource:
	return camp_type.get_size_preset(camp_size)

func get_population() -> int:
	return int(get_size_preset().population)
