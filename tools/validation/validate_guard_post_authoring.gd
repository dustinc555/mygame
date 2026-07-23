extends SceneTree

const KEEP_SCENE := "res://features/settlements/bridge/settlement_keep.tscn"
const BAR_SCENE := "res://features/settlements/bridge/settlement_bar.tscn"
const POST_SCENE := "res://features/settlements/bridge/venues/facility_guard_post.tscn"
const KEEP_RULES := "res://features/settlements/resources/furnishing/keep.tres"
const FACILITY_TOOLS := "res://addons/world_authoring/facility_tools.gd"
const RUSTWASH_SCENE := "res://scenes/zones/rustwash_basin/rustwash_basin.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_keep_posts()
	_validate_other_facility_posts()
	_validate_plugin_and_current_canyon()
	_finish()


func _validate_keep_posts() -> void:
	var keep := (load(KEEP_SCENE) as PackedScene).instantiate()
	root.add_child(keep)
	var first := keep.get_node_or_null("GuardPosts/GuardPost") as Node3D
	var second := keep.get_node_or_null("GuardPosts/GuardPost2") as Node3D
	_expect(first != null and second != null, "Keep must author two visible guard stand spots")
	if first != null and second != null:
		_expect(first.transform.is_equal_approx(Transform3D(Basis(Vector3.UP, deg_to_rad(25.0)), Vector3(-4.4, 0.05, 3.9))), "Keep GuardPost transform changed")
		_expect(second.transform.is_equal_approx(Transform3D(Basis(Vector3.UP, deg_to_rad(-25.0)), Vector3(4.4, 0.05, 3.9))), "Keep GuardPost2 transform changed")
		_expect(not first.is_in_group(FurnitureRules.FURNITURE_GROUP) and not second.is_in_group(FurnitureRules.FURNITURE_GROUP), "Guard stand spots must not be furniture")
	var rules := load(KEEP_RULES) as FurnishRules
	_expect(rules != null and rules.utility_scenes.is_empty(), "Keep Furnish must not own guard stand spots")
	keep.queue_free()


func _validate_other_facility_posts() -> void:
	var bar := (load(BAR_SCENE) as PackedScene).instantiate()
	var first := bar.get_node_or_null("GuardPosts/GuardPost") as Node3D
	var second := bar.get_node_or_null("GuardPosts/GuardPost2") as Node3D
	var third := bar.get_node_or_null("GuardPosts/GuardPost3") as Node3D
	_expect(first != null and second != null and third != null, "Bar guard stand spots must remain authored under GuardPosts")
	if first != null and second != null and third != null:
		_expect(first.position.is_equal_approx(Vector3(-3.3624148, 0.05, 6.071506)), "Bar GuardPost transform changed")
		_expect(second.position.is_equal_approx(Vector3(-2.879912, 0.05, 8.843071)), "Bar GuardPost2 transform changed")
		_expect(third.position.is_equal_approx(Vector3(0.0, 2.9232936, -6.900717)), "Bar GuardPost3 transform changed")
	bar.free()


func _validate_plugin_and_current_canyon() -> void:
	var tools := FileAccess.get_file_as_string(FACILITY_TOOLS)
	var place_start := tools.find("func _place_guard_post")
	var place_end := tools.find("\n\nfunc ", place_start + 1)
	var place_source := tools.substr(place_start, place_end - place_start)
	_expect(place_source.contains("get_node_or_null(\"GuardPosts\")") and place_source.contains("posts_root.name = \"GuardPosts\""), "Place Guard Post must target GuardPosts")
	_expect(not place_source.contains("get_node_or_null(\"Furniture\")"), "Place Guard Post must not target Furniture")
	var zone := FileAccess.get_file_as_string(RUSTWASH_SCENE)
	_expect(not zone.contains("[node name=\"Utility1\" type=\"Node3D\" parent=\"Towns/Canyon/Keep/Furniture\""), "Canyon Keep retains generated Utility1 guard post")
	_expect(not zone.contains("[node name=\"Utility2\" type=\"Node3D\" parent=\"Towns/Canyon/Keep/Furniture\""), "Canyon Keep retains generated Utility2 guard post")
	_expect(zone.contains("[node name=\"GuardPost3\" parent=\"Towns/Canyon/Keep/GuardPosts\""), "Canyon Keep must preserve the manually placed third guard post")
	_expect(zone.contains("-1.8026581, -0.0638659, 7.99115"), "Canyon manual guard post transform changed")
	_expect(not zone.contains("[node name=\"Cluster1\" parent=\"Towns/Canyon/Keep/Furniture\""), "Canyon Keep retains a vignette cluster container")
	for piece_name in ["Workstation", "Table", "ChairSouth", "StoolNorth"]:
		_expect(zone.contains("[node name=\"%s\" parent=\"Towns/Canyon/Keep/Furniture\"" % piece_name), "Canyon Keep is missing direct vignette child %s" % piece_name)
	_expect(FileAccess.file_exists(POST_SCENE), "Guard post service-point scene must exist outside the furniture catalog")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("GUARD_POST_AUTHORING_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("GUARD_POST_AUTHORING_FAILED count=%d" % _failures.size())
	quit(1)
