extends GutTest

class QuietActor extends WorldActor:
	var commands := 0
	func _enter_tree() -> void: pass
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
	func set_move_target(target: Vector3, issued_by_player: bool = true, continue_order: bool = false) -> void:
		commands += 1
		super.set_move_target(target, issued_by_player, continue_order)

class CountingInteraction extends WorldInteractionController:
	var projections := 0
	func _ready() -> void: pass
	func _project_move_command_target(candidate: Vector3, _fallback: Vector3, _target_y: float) -> Vector3:
		projections += 1
		return candidate

var interaction: CountingInteraction
var party: PartyManager
var actors: Array[QuietActor] = []

func before_each() -> void:
	interaction = CountingInteraction.new()
	party = PartyManager.new()
	add_child(party)
	interaction.party_manager = party
	add_child(interaction)
	interaction.set_process(false)
	for index in range(6):
		var actor := QuietActor.new()
		add_child(actor)
		actor.position = Vector3(index, 0, 0)
		actors.append(actor)
		party.selected_members.append(actor)

func after_each() -> void:
	interaction.free()
	party.free()
	for actor in actors:
		if is_instance_valid(actor): actor.free()
	actors.clear()

func test_repeated_destination_does_not_project_or_restart_each_member() -> void:
	var target := Vector3(20, 0, 20)
	interaction.issue_move_command_at_world(target, false)
	for repeat in range(12):
		for actor in actors:
			actor.position += Vector3(0.1, 0, 0.1)
		interaction.issue_move_command_at_world(target, false, Vector3.UP, true)
	assert_eq(interaction.projections, 6, "An unchanged destination retains the issued member slots despite movement")
	for actor in actors:
		assert_eq(actor.commands, 1)

func test_new_destination_is_not_dropped() -> void:
	interaction.issue_move_command_at_world(Vector3(20, 0, 20), false)
	interaction.issue_move_command_at_world(Vector3(30, 0, 20), false)
	assert_eq(interaction.projections, 12)
	for actor in actors:
		assert_eq(actor.commands, 2)
		assert_true(actor.get_move_target().x > 28.0)

func test_interrupted_actor_accepts_same_destination_again() -> void:
	var target := Vector3(20, 0, 20)
	interaction.issue_move_command_at_world(target, false)
	actors[0].stop_movement()
	interaction.issue_move_command_at_world(target, false, Vector3.UP, true)
	assert_eq(actors[0].commands, 2)
	assert_true(actors[0].has_move_target())

func test_changed_selection_is_a_new_group_order() -> void:
	var target := Vector3(20, 0, 20)
	interaction.issue_move_command_at_world(target, false)
	party.selected_members = [actors[0]]
	interaction.issue_move_command_at_world(target, false, Vector3.UP, true)
	assert_eq(actors[0].get_move_target(), target)
	assert_eq(actors[0].commands, 2)

func test_retargeted_member_does_not_hide_behind_unchanged_group_destination() -> void:
	var target := Vector3(20, 0, 20)
	interaction.issue_move_command_at_world(target, false)
	actors[0].set_move_target(Vector3(-10, 0, 0))
	interaction.issue_move_command_at_world(target, false, Vector3.UP, true)
	assert_true(actors[0].get_move_target().x > 18.0)
	assert_eq(actors[0].commands, 3)

func test_fresh_click_at_same_point_remains_an_explicit_command() -> void:
	var target := Vector3(20, 0, 20)
	interaction.issue_move_command_at_world(target, false)
	interaction.issue_move_command_at_world(target, false)
	assert_eq(actors[0].commands, 2)

func test_combat_interruption_does_not_suppress_held_move() -> void:
	var target := Vector3(20, 0, 20)
	interaction.issue_move_command_at_world(target, false)
	actors[0]._combat_navigation_owned = true
	interaction.issue_move_command_at_world(target, false, Vector3.UP, true)
	assert_eq(actors[0].commands, 2)
