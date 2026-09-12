extends RefCounted

var failures: Array[String] = []


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run(tree: SceneTree) -> void:
	var appearance := CharacterAppearanceData.new()
	appearance.character_race = load("res://features/actors/resources/character_races/puglin.tres")
	appearance.body_archetype = load("res://features/actors/resources/character_body_archetypes/puglin.tres")
	appearance.visual_body_type = 2
	var actor := HumanoidCharacter.new()
	actor.name = "PuglinRuntimeValidation"
	var mesh := MeshInstance3D.new()
	mesh.name = "BodyMesh"
	mesh.mesh = CapsuleMesh.new()
	actor.add_child(mesh)
	actor.appearance_data = appearance
	tree.root.add_child(actor)
	actor.set_physics_process(false)
	var body := actor.get_body_projection() as HumanoidBodyProjection
	_check(body != null and body.get_visual_root() != null, "Canonical Puglin must build through HumanoidCharacter")
	if body == null or body.get_visual_root() == null:
		tree.quit(1)
		return
	var player := body.get_primary_animation_player()
	_check(body.get_resolved_body_archetype() == appearance.character_race.default_male_archetype, "Production actor resolves the same canonical body as the race")
	var unsupported_clothing := ItemDefinition.new()
	unsupported_clothing.equip_slot = "chest"
	_check(not actor.get_equipment().can_equip_item_to_slot(unsupported_clothing, "chest"), "Puglin cannot equip unprovided clothing slots")
	var skeleton := AnimationRetargetLib.find_skeleton(body.get_visual_root())
	var expected_library = load("res://tools/monster_pack_explorer/monster_animation_library.gd").new()
	for clip in ["Idle", "Walk", "Mining"]:
		_check(player.has_animation(clip), "Missing production clip: " + clip)
		var original: Dictionary = {}
		for source in expected_library.sources:
			if source.name == clip:
				original = source
				break
		var expected: Animation = expected_library.retarget(original, player.get_parent(), skeleton)
		var actual := player.get_animation(clip)
		for track in expected.get_track_count():
			var path := expected.track_get_path(track)
			var actual_track := actual.find_track(path, expected.track_get_type(track))
			_check(actual_track >= 0, "%s: production track must resolve to canonical wrapper skeleton: %s" % [clip, path])
			if actual_track < 0:
				continue
			var value = actual.track_get_key_value(actual_track, 0)
			var reference = expected.track_get_key_value(track, 0)
			if value is Quaternion:
				_check(absf(value.dot(reference)) > 0.9999, "%s: rest-aware rotation %s" % [clip, path])
			elif value is Vector3:
				_check(value.distance_to(reference) < 0.0001, "%s: target bone offset %s" % [clip, path])
		body.seek_clip(clip, 0.2)
	_check(body.get_visual_root().find_child("AppearanceEyebrows", true, false) == null, "Must not attach human eyebrows to an incompatible body")
	var stick: ItemDefinition = load("res://features/inventory/resources/items/bestiary_puglin_stick.tres")
	actor.equip_item_to_slot(stick, "weapon")
	_check(actor.get_equipped_item("weapon") == stick, "Normal actor equip must retain the real stick item")
	_check(body.get_visual_root().find_child("EquippedWeaponVisual", true, false) != null, "Normal actor equip must mount stick through shared sockets")
	actor.apply_appearance_data(appearance)
	_check(body.get_visual_root().find_child("AppearanceEyebrows", true, false) == null, "Live appearance rebuild must not inject human eyebrows")
	_check(body.get_visual_root().find_child("EquippedWeaponVisual", true, false) != null, "Appearance rebuild must retain equipped stick")
	var bronze: ItemDefinition = load("res://features/inventory/resources/items/bronze_sword.tres")
	actor.equip_item_to_slot(bronze, "weapon")
	var socket := body.get_visual_root().find_child("RightHandGrip", true, false) as Node3D
	_check(socket != null and socket.transform.is_equal_approx(appearance.body_archetype.grip_socket_profile.right_hand_one_hand), "Production bronze sword uses canonical Puglin grip without item overrides")
	actor.unequip_item_from_slot("weapon")
	_check(body.get_visual_root().find_child("EquippedWeaponVisual", true, false) == null, "Normal unequip must remove stick visual")
	actor.free()
	_verify_human_transfer(tree)
	await tree.process_frame

	if failures.is_empty():
		print("PUGLIN_RUNTIME_PROJECTION_OK")
	tree.quit(0 if failures.is_empty() else 1)

func _verify_human_transfer(tree: SceneTree) -> void:
	var source_root: Node = load("res://assets/vendor/quaternius/universal_animation_library_1_pro/UAL1_Pro.glb").instantiate()
	var source_skeleton := AnimationRetargetLib.find_skeleton(source_root)
	var source_player := AnimationRetargetLib.find_animation_player(source_root)
	for body_id in ["human_male", "human_female"]:
		var appearance := CharacterAppearanceData.new()
		appearance.character_race = load("res://features/actors/resources/character_races/human.tres")
		appearance.body_archetype = load("res://features/actors/resources/character_body_archetypes/%s.tres" % body_id)
		var actor := HumanoidCharacter.new()
		var mesh := MeshInstance3D.new()
		mesh.name = "BodyMesh"
		mesh.mesh = CapsuleMesh.new()
		actor.add_child(mesh)
		actor.appearance_data = appearance
		tree.root.add_child(actor)
		actor.set_physics_process(false)
		var body := actor.get_body_projection() as HumanoidBodyProjection
		var skeleton := AnimationRetargetLib.find_skeleton(body.get_visual_root())
		var actual := body.get_primary_animation_player().get_animation("Idle")
		var expected := source_player.get_animation("Idle").duplicate(true) as Animation
		AnimationPositionScale.scale_position_tracks(expected, AnimationPositionScale.ratio_between(source_skeleton, skeleton))
		_check(actual.get_track_count() == expected.get_track_count(), body_id + ": preserve original human track count")
		for track in expected.get_track_count():
			_check(actual.track_get_path(track) == expected.track_get_path(track), body_id + ": preserve human paths")
			_check(actual.track_get_key_value(track, 0) == expected.track_get_key_value(track, 0), body_id + ": preserve original human poses")
		_check(body.get_visual_root().find_child("AppearanceEyebrows", true, false) != null, body_id + ": preserve automatic human eyebrows")
		actor.free()
	source_root.free()

