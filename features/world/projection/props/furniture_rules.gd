@tool
extends RefCounted

class_name FurnitureRules

## Shared furniture taxonomy. Every placeable furniture root (props,
## seats, beds, tabletop spawners, containers) exports a
## FurnitureRules.Type and joins FURNITURE_GROUP, so facility functions can
## discover their operating pieces ("the bar finds its counter, seats, and
## shelves") and the coming furniture port stays data-driven.

enum Type {
	DECOR,
	SEAT,
	TABLE,
	BED,
	CONTAINER,
	SHELF,
	RUG,
	COUNTER,
}

const FURNITURE_GROUP := "furniture"

const TYPE_NAMES := {
	Type.DECOR: "decor",
	Type.SEAT: "seat",
	Type.TABLE: "table",
	Type.BED: "bed",
	Type.CONTAINER: "container",
	Type.SHELF: "shelf",
	Type.RUG: "rug",
	Type.COUNTER: "counter",
}


static func type_name(furniture_type: Type) -> String:
	return str(TYPE_NAMES.get(furniture_type, "decor"))


## Quaternius pack models carry "-colonly" import hints that generate convex
## StaticBody3D colliders inside the visual model. Furniture wrappers author
## their own collision boxes, so the imported hulls only double the physics:
## they over-erode the navmesh, steal clicks from the wrapper body, and block
## eye-level raycasts (a counter hull that includes its vise tower blocks
## conversations across the counter). Wrappers strip them at runtime.
static func strip_imported_collision(furniture_root: Node) -> void:
	if Engine.is_editor_hint():
		return
	var stack: Array[Node] = []
	for child in furniture_root.get_children():
		stack.append(child)
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is StaticBody3D:
			node.queue_free()
			continue
		for child in node.get_children():
			stack.append(child)
