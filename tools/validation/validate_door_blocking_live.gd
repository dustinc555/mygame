extends SceneTree

## Live physics proof for door blocking: drives a real CharacterBody3D with
## the actor collision setup (mask includes the door blocker layer) straight
## at a closed door and expects it to be stopped, then opens the door and
## expects it to walk through. Guards against the shipped bug class where
## doors were pure decoration on a layer nobody collided with.

const DOOR_SCENE_PATH := "res://scenes/building_pieces/quaternius/medieval_village_woodbrick/door_wood_flat.tscn"
const DOOR_BLOCKER_LAYER := 8
const WALK_SPEED := 2.0
const WALK_FRAMES := 120

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var door = (load(DOOR_SCENE_PATH) as PackedScene).instantiate()
	door.door_id = "validation.blocking"
	root.add_child(door)
	var body := CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1 | DOOR_BLOCKER_LAYER
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	shape.shape = capsule
	body.add_child(shape)
	root.add_child(body)
	# The blocker box is centered at local (0.5142, ~1.08, -0.11); approach it
	# head-on along +Z at capsule height so only the door can stop the walk.
	var start := Vector3(0.5142, 1.0, -2.0)
	body.global_position = start
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	await _walk(body, Vector3.FORWARD * -1.0)
	var blocked_z := body.global_position.z
	if blocked_z > -0.45:
		_fail("Closed door failed to block: body reached z=%.2f" % blocked_z)
	door.apply_door_state({"is_open": true}, false)
	await physics_frame
	await _walk(body, Vector3.FORWARD * -1.0)
	var open_z := body.global_position.z
	if open_z < 0.6:
		_fail("Open door failed to let the body through: body reached z=%.2f" % open_z)
	if _failed:
		quit(1)
		return
	print("DOOR_BLOCKING_LIVE_OK closed_z=%.2f open_z=%.2f" % [blocked_z, open_z])
	quit()


func _walk(body: CharacterBody3D, direction: Vector3) -> void:
	for _frame in range(WALK_FRAMES):
		body.velocity = direction.normalized() * WALK_SPEED
		body.move_and_slide()
		await physics_frame


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
