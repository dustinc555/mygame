extends Resource

class_name PlaceableBuildingCatalog

## Operator-curated list of buildings the construction system offers. Only
## entries listed here appear in the Building Placer; demo/test scenes stay
## out unless explicitly added.

@export var catalog_id := ""
@export var display_name := ""
@export var buildings: Array[Resource] = []


func get_building(building_id: String) -> Resource:
	for building in buildings:
		if building != null and str(building.call("get_id")) == building_id:
			return building
	return null
