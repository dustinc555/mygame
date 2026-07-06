extends SceneTree

## Headless world navcache baker: loads a world scene, waits for the full
## startup bake, then saves every tile into the scene's navcache directory.
## The world_authoring editor plugin's "Bake World Nav" button is the primary
## workflow; this is the CLI/CI equivalent.
##
##   godot --headless --path . --script res://tools/bake_world_navcache.gd
##   godot --headless --path . --script res://tools/bake_world_navcache.gd -- res://scenes/zones/other_world/other_world.tscn

const DEFAULT_SCENE := "res://scenes/zones/rustwash_basin/rustwash_basin.tscn"
const MAX_BAKE_FRAMES := 60000


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	var scene_path := DEFAULT_SCENE
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and String(args[0]).begins_with("res://"):
		scene_path = String(args[0])
	print("NAVCACHE_BAKE scene=%s" % scene_path)
	var packed: PackedScene = load(scene_path)
	if packed == null:
		print("NAVCACHE_BAKE_FAILED cannot load scene")
		quit(1)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	# Register as the played scene: save_world_cache targets the current
	# scene's directory (a world bake must write beside the WORLD, not fall
	# back to a zone's cache).
	current_scene = scene
	var controller: Node = null
	for _i in range(600):
		await physics_frame
		controller = get_first_node_in_group("world_navigation_controller")
		if controller != null:
			break
	if controller == null:
		print("NAVCACHE_BAKE_FAILED no WorldNavigationController")
		quit(1)
		return
	# An explicit bake command must bake FRESH: without this, an existing
	# cache is loaded, silently round-tripped, and re-saved stale.
	for _i in range(10):
		await physics_frame
	controller.call("notify_world_geometry_changed")
	for _i in range(MAX_BAKE_FRAMES):
		await physics_frame
		if not bool(controller.call("is_initial_navigation_pending")) and bool(controller.call("is_idle")):
			break
	var saved := int(controller.call("save_world_cache"))
	if saved <= 0:
		print("NAVCACHE_BAKE_FAILED saved=0")
		quit(1)
		return
	print("NAVCACHE_BAKE_OK tiles=%d" % saved)
	quit(0)
