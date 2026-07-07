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
}


static func type_name(furniture_type: Type) -> String:
	return str(TYPE_NAMES.get(furniture_type, "decor"))
