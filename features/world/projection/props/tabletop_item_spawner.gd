extends StaticBody3D

class_name TabletopItemSpawner

const WORLD_ITEM_SCENE := preload("res://features/world/projection/items/world_item.tscn")

const TABLE_PLATE := preload("res://features/inventory/resources/items/table_plate.tres")
const MUG := preload("res://features/inventory/resources/items/mug.tres")
const TABLE_FORK := preload("res://features/inventory/resources/items/table_fork.tres")
const TABLE_SPOON := preload("res://features/inventory/resources/items/table_spoon.tres")
const TABLE_KNIFE := preload("res://features/inventory/resources/items/table_knife.tres")
const BOTTLE_1 := preload("res://features/inventory/resources/items/bottle_1.tres")
const BOTTLE_2 := preload("res://features/inventory/resources/items/bottle_2.tres")
const SMALL_BOTTLE := preload("res://features/inventory/resources/items/small_bottle.tres")
const CHALICE := preload("res://features/inventory/resources/items/chalice.tres")
const CANDLE_1 := preload("res://features/inventory/resources/items/candle_1.tres")
const CANDLE_2 := preload("res://features/inventory/resources/items/candle_2.tres")
const CANDLE_3 := preload("res://features/inventory/resources/items/candle_3.tres")
const CANDLESTICK := preload("res://features/inventory/resources/items/candlestick.tres")
const BREAD := preload("res://features/inventory/resources/items/bread.tres")

const SPAWNED_ITEMS_ROOT_NAME := "SpawnedTabletopItems"
const CATEGORY_ITEMS := {
	"dish": [TABLE_PLATE],
	"drink": [MUG, MUG, MUG, SMALL_BOTTLE],
	"bottle": [BOTTLE_1, BOTTLE_2, SMALL_BOTTLE],
	"utensil": [TABLE_FORK, TABLE_SPOON, TABLE_KNIFE],
	"food": [BREAD],
	"candle": [CANDLE_1, CANDLE_2, CANDLE_3, CANDLESTICK],
	"drink_fancy": [CHALICE, CHALICE, MUG],
	"small_clutter": [SMALL_BOTTLE, CANDLE_3, TABLE_SPOON],
}

@export var furniture_type := FurnitureRules.Type.TABLE
@export var spawn_on_ready := true
@export var prop_slots_path := NodePath("PropSlots")
@export_range(0.0, 1.0, 0.01) var spawn_density := 1.0
@export var minimum_spawned_items := 3
@export_range(0.0, 0.5, 0.01) var yaw_jitter_radians := 0.12
@export var tabletop_spawn_surface_offset := -0.10
@export var tabletop_pickup_clearance := 0.6
@export var tabletop_pickup_seat_clearance := 0.6
@export var tabletop_grab_horizontal_reach := 1.9
# Measured from the actor's feet: a standing grab tops out around 2m, which
# keeps chest-height wall shelves (slots ~1.7m) reachable.
@export var tabletop_grab_vertical_reach := 2.05
@export var tabletop_pickup_arrival_slack := 0.25
@export var tabletop_pickup_nav_projection_limit := 1.25
# Wall-mounted shelves sit ~1.6m up; their access candidates must be allowed
# to project down to the floor beside them or the route solver rejects them.
@export var tabletop_pickup_vertical_projection_limit := 2.0
@export var seed_salt := "comfortable_tavern"
@export var owner_faction_name := ""
@export var theft_noise_radius := 1.2
@export_range(0, 100, 1) var theft_difficulty := 15


func _ready() -> void:
	add_to_group("tabletop_item_spawner")
	add_to_group(FurnitureRules.FURNITURE_GROUP)
	if Engine.is_editor_hint() or not spawn_on_ready:
		return
	call_deferred("spawn_tabletop_items")


func spawn_tabletop_items() -> void:
	if Engine.is_editor_hint():
		return
	var slots_root := get_node_or_null(prop_slots_path)
	if slots_root == null:
		return
	var spawned_items_root := _get_or_create_spawned_items_root()
	if spawned_items_root.get_child_count() > 0:
		return
	var eligible_slots := _collect_eligible_slots(slots_root)
	var spawned_count := 0
	for slot in eligible_slots:
		var rng := _make_slot_rng(slot, "roll")
		var spawn_chance := clampf(_get_slot_weight(slot) * spawn_density, 0.0, 1.0)
		if rng.randf() <= spawn_chance and _spawn_item_at_slot(spawned_items_root, slot, rng):
			spawned_count += 1
	for slot in eligible_slots:
		if spawned_count >= minimum_spawned_items:
			break
		if _slot_already_spawned(spawned_items_root, slot):
			continue
		if _spawn_item_at_slot(spawned_items_root, slot, _make_slot_rng(slot, "minimum")):
			spawned_count += 1


func get_tabletop_pickup_position(item: Node3D, actor = null) -> Vector3:
	if item == null:
		return global_position
	var half_extents := _get_tabletop_pickup_half_extents()
	var inverse := global_transform.affine_inverse()
	var item_local := inverse * item.global_position
	var actor_local := item_local
	if actor is Node3D:
		actor_local = inverse * (actor as Node3D).global_position
	return _get_best_tabletop_access_position(item_local, actor_local, half_extents)


func is_tabletop_item_reachable_from(item: Node3D, _actor, actor_position: Vector3, reach_distance: float) -> bool:
	if item == null:
		return false
	if absf(actor_position.y - item.global_position.y) > tabletop_grab_vertical_reach:
		return false
	var horizontal_distance := Vector2(actor_position.x - item.global_position.x, actor_position.z - item.global_position.z).length()
	return horizontal_distance <= minf(reach_distance, tabletop_grab_horizontal_reach)


func _get_or_create_spawned_items_root() -> Node3D:
	var existing := get_node_or_null(SPAWNED_ITEMS_ROOT_NAME) as Node3D
	if existing != null:
		return existing
	var root := Node3D.new()
	root.name = SPAWNED_ITEMS_ROOT_NAME
	add_child(root)
	return root


func _collect_eligible_slots(slots_root: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child in slots_root.get_children():
		var slot := child as Node3D
		if slot == null:
			continue
		if not CATEGORY_ITEMS.has(_get_slot_category(slot)):
			continue
		result.append(slot)
	return result


func _spawn_item_at_slot(parent: Node, slot: Node3D, rng: RandomNumberGenerator) -> bool:
	var definition := _choose_item_definition(_get_slot_category(slot), rng)
	if definition == null:
		return false
	var item := WORLD_ITEM_SCENE.instantiate() as WorldItem
	if item == null:
		return false
	item.name = _spawned_item_name(slot)
	parent.add_child(item)
	item.setup(definition, 1)
	item.owner_faction_name = owner_faction_name
	item.theft_value = _get_theft_value(definition)
	item.theft_noise_radius = theft_noise_radius
	item.theft_difficulty = theft_difficulty
	item.set_meta("tabletop_slot", String(slot.name))
	var surface_position := slot.global_position + Vector3.UP * tabletop_spawn_surface_offset
	item.global_transform = Transform3D(_get_slot_basis(slot, rng), surface_position)
	item.place_bottom_at(surface_position, surface_position.y)
	item.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	item.freeze = true
	item.sleeping = true
	item.gravity_scale = 0.0
	return true


func _choose_item_definition(category: String, rng: RandomNumberGenerator) -> ItemDefinition:
	var choices: Array = CATEGORY_ITEMS.get(category, [])
	if choices.is_empty():
		return null
	return choices[rng.randi_range(0, choices.size() - 1)] as ItemDefinition


func _get_tabletop_pickup_half_extents() -> Vector2:
	var collision := get_node_or_null("BodyCollision") as CollisionShape3D
	if collision != null and collision.shape is BoxShape3D:
		var box := collision.shape as BoxShape3D
		return Vector2(maxf(box.size.x * 0.5, 0.1), maxf(box.size.z * 0.5, 0.1))
	return Vector2(1.35, 0.65)


func _get_best_tabletop_access_position(item_local: Vector3, actor_local: Vector3, half_extents: Vector2) -> Vector3:
	var best_position := global_position
	var best_score := INF
	var nearby_seats := _get_nearby_seats()
	for candidate_local in _get_tabletop_access_candidates(item_local, half_extents):
		var candidate_world := global_transform * candidate_local
		var projected_world := _project_tabletop_access_to_navigation(candidate_world)
		var projected_local := global_transform.affine_inverse() * projected_world
		if _get_local_horizontal_distance(projected_local, item_local) > _get_tabletop_route_horizontal_reach():
			continue
		var score := _get_tabletop_access_score(projected_world, projected_local, actor_local, nearby_seats)
		if score < best_score:
			best_score = score
			best_position = projected_world
	return best_position


func _get_local_horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _get_tabletop_route_horizontal_reach() -> float:
	return maxf(0.2, tabletop_grab_horizontal_reach - maxf(tabletop_pickup_arrival_slack, 0.0) - 0.05)


func _get_tabletop_access_candidates(item_local: Vector3, half_extents: Vector2) -> Array[Vector3]:
	var x_edge := half_extents.x + tabletop_pickup_clearance
	var z_edge := half_extents.y + tabletop_pickup_clearance
	var clamped_x := clampf(item_local.x, -half_extents.x, half_extents.x)
	var clamped_z := clampf(item_local.z, -half_extents.y, half_extents.y)
	var side_step := minf(0.85, maxf(0.0, half_extents.x - 0.2))
	var wide_side_step := minf(1.2, maxf(0.0, half_extents.x - 0.05))
	var side_left_x := clampf(item_local.x - side_step, -half_extents.x, half_extents.x)
	var side_right_x := clampf(item_local.x + side_step, -half_extents.x, half_extents.x)
	var wide_side_left_x := clampf(item_local.x - wide_side_step, -half_extents.x, half_extents.x)
	var wide_side_right_x := clampf(item_local.x + wide_side_step, -half_extents.x, half_extents.x)
	return [
		Vector3(-x_edge, 0.0, clamped_z),
		Vector3(x_edge, 0.0, clamped_z),
		Vector3(clamped_x, 0.0, -z_edge),
		Vector3(clamped_x, 0.0, z_edge),
		Vector3(side_left_x, 0.0, -z_edge),
		Vector3(side_right_x, 0.0, -z_edge),
		Vector3(side_left_x, 0.0, z_edge),
		Vector3(side_right_x, 0.0, z_edge),
		Vector3(wide_side_left_x, 0.0, -z_edge),
		Vector3(wide_side_right_x, 0.0, -z_edge),
		Vector3(wide_side_left_x, 0.0, z_edge),
		Vector3(wide_side_right_x, 0.0, z_edge),
		Vector3(-x_edge, 0.0, -z_edge),
		Vector3(x_edge, 0.0, -z_edge),
		Vector3(-x_edge, 0.0, z_edge),
		Vector3(x_edge, 0.0, z_edge),
	]


func _get_tabletop_access_score(world_position: Vector3, local_position: Vector3, actor_local: Vector3, nearby_seats: Array[Node3D]) -> float:
	var actor_distance := Vector2(local_position.x - actor_local.x, local_position.z - actor_local.z).length()
	return actor_distance + _get_nearby_seat_penalty(world_position, nearby_seats)


## Seats within reach of this table, fetched once per access solve — the group
## scan must not run per candidate.
func _get_nearby_seats() -> Array[Node3D]:
	var seats: Array[Node3D] = []
	if not is_inside_tree() or tabletop_pickup_seat_clearance <= 0.0:
		return seats
	for node in get_tree().get_nodes_in_group("sittable_seat"):
		var seat := node as Node3D
		if seat == null or not is_instance_valid(seat):
			continue
		if seat.global_position.distance_squared_to(global_position) > 16.0:
			continue
		seats.append(seat)
	return seats


func _get_nearby_seat_penalty(world_position: Vector3, nearby_seats: Array[Node3D]) -> float:
	var penalty := 0.0
	for seat in nearby_seats:
		var distance := Vector2(world_position.x - seat.global_position.x, world_position.z - seat.global_position.z).length()
		if distance < tabletop_pickup_seat_clearance:
			penalty += (tabletop_pickup_seat_clearance - distance) * 200.0
	return penalty


func _project_tabletop_access_to_navigation(access_position: Vector3) -> Vector3:
	if not is_inside_tree():
		return access_position
	var world_3d := get_world_3d()
	if world_3d == null:
		return access_position
	var navigation_map: RID = world_3d.navigation_map
	if NavigationServer3D.map_get_iteration_id(navigation_map) == 0:
		return access_position
	var closest := NavigationServer3D.map_get_closest_point(navigation_map, access_position)
	var horizontal_offset := Vector2(closest.x - access_position.x, closest.z - access_position.z).length()
	if horizontal_offset > tabletop_pickup_nav_projection_limit:
		return access_position
	if absf(closest.y - access_position.y) > tabletop_pickup_vertical_projection_limit:
		return access_position
	return closest


func _get_slot_category(slot: Node) -> String:
	return str(slot.get_meta("prop_category", ""))


func _get_slot_weight(slot: Node) -> float:
	return clampf(float(slot.get_meta("comfortable_weight", 0.0)), 0.0, 1.0)


func _slot_already_spawned(parent: Node, slot: Node3D) -> bool:
	return parent.get_node_or_null(NodePath(_spawned_item_name(slot))) != null


func _spawned_item_name(slot: Node3D) -> String:
	return "Tabletop_%s" % String(slot.name)


func _make_slot_rng(slot: Node3D, phase: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var seed_text := "%s|%s|%s|%s|%.2f|%.2f|%.2f" % [
		seed_salt,
		phase,
		str(get_path()),
		String(slot.name),
		global_position.x,
		global_position.y,
		global_position.z,
	]
	var seed_value := int(seed_text.hash())
	if seed_value < 0:
		seed_value = -seed_value
	if seed_value == 0:
		seed_value = 1
	rng.seed = seed_value
	return rng


func _get_slot_basis(slot: Node3D, rng: RandomNumberGenerator) -> Basis:
	var slot_basis := slot.global_transform.basis.orthonormalized()
	if yaw_jitter_radians > 0.0:
		slot_basis = Basis(Vector3.UP, rng.randf_range(-yaw_jitter_radians, yaw_jitter_radians)) * slot_basis
	return slot_basis


func _get_theft_value(definition: ItemDefinition) -> int:
	if definition == null:
		return 5
	return maxi(1, int(round(definition.unit_weight * 20.0)))
