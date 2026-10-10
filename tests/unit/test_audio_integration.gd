extends GutTest

## Exercise the real composition-root installer without starting a whole world.
class WiringBootstrap extends "res://features/core/game_bootstrap.gd":
	func _ready() -> void:
		pass

class AudioSource extends Node:
	signal combat_audio_event(event: Dictionary)
	func get_actor_by_stable_id(_id: String):
		return null


func test_bootstrap_installs_combat_ui_and_unlock_audio_from_registered_modules() -> void:
	var root := Node.new()
	add_child_autofree(root)
	var bootstrap := WiringBootstrap.new()
	root.add_child(bootstrap)
	bootstrap.root_scene = root
	bootstrap._create_roots()
	var context := BootstrapContext.new(root)
	bootstrap._context = context
	var source := AudioSource.new()
	root.add_child(source)
	context.register(&"gecs_world", source)
	var expected := {&"combat_audio": 0, &"ui_audio": 0, &"unlock_audio": 0}
	for module in bootstrap.MODULES:
		for spec in module.PROJECTION:
			if not expected.has(spec.service):
				continue
			expected[spec.service] += 1
			var controller: Node = bootstrap._install_spec(spec, bootstrap.projection_root)
			assert_same(context.get_optional(spec.service), controller)
			controller.initialize(context)
			assert_same(bootstrap._install_spec(spec, bootstrap.projection_root), controller,
				"Installing an existing spec reuses its registered controller")
	assert_eq(expected[&"combat_audio"], 1, "Production bootstrap must include combat audio exactly once")
	assert_eq(expected[&"ui_audio"], 1, "Production bootstrap must include UI audio exactly once")
	assert_eq(expected[&"unlock_audio"], 1, "Production bootstrap must include unlock audio exactly once")
	assert_eq(source.get_signal_connection_list("combat_audio_event").size(), 1)
	root.free()
