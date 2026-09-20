extends "res://tests/validation/test_case.gd"
## The same eager actor dependency fails to compile under --script before ECS
## autoload setup. The normal scene host must load it only after autoloads exist.
const ACTOR_SCRIPT := preload("res://features/actors/bridge/world_actor.gd")


class CleanupProbe:
	extends "res://tests/validation/test_case.gd"
	var finalized := false

	func _finalize() -> void:
		finalized = true


func _initialize() -> void:
	# Case entry must run after the host is attached, not while the root is
	# locked by add_child. Feature tests install real bootstrap/world siblings.
	var sibling := Node.new()
	sibling.name = "TestHostSibling"
	root.add_child(sibling)
	if sibling.get_parent() != root:
		sibling.free()
		push_error("Test entry must be able to attach a world to the running root")
		quit(1)
		return
	sibling.free()
	if root.get_node_or_null("ECS") == null or ECS != root.get_node_or_null("ECS"):
		push_error("Test host must expose the real project ECS autoload")
		quit(1)
		return
	var actor_script: Script = ACTOR_SCRIPT
	if not actor_script.can_instantiate() or get_root() != get_tree().root:
		push_error("Test dependencies and SceneTree aliases must resolve")
		quit(1)
		return
	await process_frame
	await physics_frame
	await create_timer(0.01).timeout
	# Removing a real hosted case must invoke its finalizer before it is freed.
	# A cleanup print during process shutdown alone cannot fail this validator.
	var cleanup_probe := CleanupProbe.new()
	add_child(cleanup_probe)
	await process_frame
	remove_child(cleanup_probe)
	var finalized: bool = cleanup_probe.finalized
	cleanup_probe.free()
	if not finalized:
		push_error("Hosted case removal must invoke _finalize before it is freed")
		quit(1)
		return
	print("TEST_HOST_OK autoload=true frames=true timer=true cleanup=true")
	quit(0)


func _finalize() -> void:
	print("TEST_HOST_CLEANUP_OK")
