extends SceneTree

const CATALOG_PATH := "res://features/world/resources/building_pieces/quaternius/medieval_village_woodbrick/starter_woodbrick_catalog.tres"
const ROOF_IDS := [
	"roof_modular_flattiles_6_l",
	"roof_modular_flattiles_6_mid",
	"roof_modular_flattiles_6_r",
	"roof_modular_flattiles_8_l",
	"roof_modular_flattiles_8_mid",
	"roof_modular_flattiles_8_r",
]


func _init() -> void:
	var catalog := load(CATALOG_PATH) as Resource
	_assert(catalog != null, "Missing modular piece catalog.")
	_assert(catalog.get("pieces").size() == 30, "Catalog should contain the reviewed starter set, roof modules, and three shop pieces.")
	for piece_id in ROOF_IDS:
		var definition := catalog.call("get_piece", piece_id) as Resource
		_assert(definition != null, "Catalog missing %s." % piece_id)
		_assert(str(definition.get("category")) == "roof", "%s must be a roof piece." % piece_id)
		_assert((definition.get("snap_points") as Array).size() == 4, "%s must define left, right, wall, and ridge snap points." % piece_id)
		var source := definition.get("source_scene") as PackedScene
		_assert(source != null, "%s missing raw source link." % piece_id)
		var scene := definition.get("scene") as PackedScene
		_assert(scene != null, "%s missing wrapper scene." % piece_id)
		var wrapper := scene.instantiate() as Node3D
		_assert(wrapper != null, "%s wrapper did not instantiate." % piece_id)
		_assert(wrapper.get_piece_id() == piece_id, "%s wrapper ID mismatch." % piece_id)
		_assert(wrapper.get_snap_markers().size() == 4, "%s wrapper must expose four snap markers." % piece_id)
		_assert(wrapper.get_node_or_null("Model") != null, "%s wrapper must keep the raw model beneath Model." % piece_id)
		wrapper.free()
	print("MEDIEVAL_ROOF_MODULES_OK count=%d catalog=%d" % [ROOF_IDS.size(), catalog.get("pieces").size()])
	quit()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
