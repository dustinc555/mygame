@tool
extends Resource

class_name CharacterRaceDefinition

const DEFAULT_SLOT_GRID_SIZES: Dictionary[String, Vector2i] = {
	"head": Vector2i(2, 2),
	"chest": Vector2i(2, 3),
	"legs": Vector2i(2, 3),
	"feet": Vector2i(2, 2),
	"hands": Vector2i(2, 2),
	"undershirt": Vector2i(2, 3),
	"backpack": Vector2i(2, 3),
	"weapon": Vector2i(2, 5),
	"offhand": Vector2i(2, 3),
}

@export var race_id := ""
@export var display_name := "Race"
@export var equipment_slots: PackedStringArray = PackedStringArray()
@export var equipment_slot_labels: Dictionary = {}
## Fixed width/height in inventory cells for this race's equipment slots.
## Both the visible area and equip limits use these sizes; items never resize slots.
@export var equipment_slot_grid_sizes: Dictionary[String, Vector2i] = DEFAULT_SLOT_GRID_SIZES.duplicate()
@export var bleed_fluid: Resource
@export var default_male_archetype: Resource
@export var default_female_archetype: Resource
## Optional authored species palette. Matching indices select colors/textures.
@export var skin_tones: Array[Color] = []
@export var skin_textures: Array[Texture2D] = []
@export var skin_mesh_names: PackedStringArray = PackedStringArray()


func apply_skin_palette(root: Node, color: Color) -> bool:
	if skin_tones.is_empty() or skin_textures.size() != skin_tones.size():
		return false
	var index := 0
	var distance := INF
	for i in skin_tones.size():
		var difference := Vector3(color.r - skin_tones[i].r, color.g - skin_tones[i].g, color.b - skin_tones[i].b).length_squared()
		if difference < distance:
			distance = difference
			index = i
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		if not skin_mesh_names.has(str(mesh.name)):
			continue
		for surface in mesh.mesh.get_surface_count():
			var original = mesh.get_active_material(surface)
			if original is StandardMaterial3D:
				var material := original.duplicate() as StandardMaterial3D
				material.albedo_texture = skin_textures[index]
				mesh.set_surface_override_material(surface, material)
	return true


func get_equipment_slots() -> Array[String]:
	var slots: Array[String] = []
	for slot_name in equipment_slots:
		slots.append(str(slot_name))
	return slots


func get_slot_label(slot_name: String) -> String:
	return str(equipment_slot_labels.get(slot_name, slot_name.capitalize()))


func get_slot_grid_size(slot_name: String) -> Vector2i:
	var cells: Vector2i = equipment_slot_grid_sizes.get(slot_name, default_slot_grid_size(slot_name))
	return Vector2i(maxi(1, cells.x), maxi(1, cells.y))


static func default_slot_grid_size(slot_name: String) -> Vector2i:
	return DEFAULT_SLOT_GRID_SIZES.get(slot_name, Vector2i(2, 2))
