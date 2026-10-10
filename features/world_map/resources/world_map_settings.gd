@tool
extends Resource
class_name WorldMapSettings

## World Inspector → World Map. Shared defaults; override this resource on a
## WorldRoot for a different world. Settings apply on the next game launch.
@export_group("Discovery")
## Disable for an authoring/playtest overview. Does not erase saved exploration.
@export var discovery_enabled := true
## Ground revealed around living party members, in world metres.
@export_range(16.0, 1000.0, 8.0, "suffix:m") var reveal_radius_meters := 96.0

@export_group("View")
## Initial map width near the party. Fit World always shows the full extent.
@export_range(128.0, 4096.0, 32.0, "suffix:m") var opening_width_meters := 640.0
## Finest zoom in logical screen pixels per world metre.
@export_range(0.25, 16.0, 0.25, "suffix:px/m") var max_pixels_per_meter := 4.0

@export_group("Cartography")
## Contour spacing in world metres. Zero disables contour lines.
@export_range(0.0, 100.0, 1.0, "suffix:m") var contour_interval_meters := 20.0
@export_range(0.0, 2.0, 0.05) var relief_strength := 0.85
## Untextured terrain fallback only; authored paint retains its own colours.
@export var land_color := Color("b6a27c")
@export var unknown_color := Color("c6b58d")
## Enable only when this world has an ocean at the specified height.
@export var ocean_enabled := false
@export_range(-1000.0, 1000.0, 1.0, "suffix:m") var ocean_height_meters := 0.0
@export var ocean_color := Color("668c92")

@export_group("Cache")
## Maximum resident map tiles. Tiles are generated on a worker, never by loading NPCs.
@export_range(32, 512, 16) var resident_tile_limit := 128

func raster_style() -> Dictionary:
	return {"contour": maxf(0.0, contour_interval_meters), "relief": clampf(relief_strength, 0.0, 2.0), "land": land_color, "ocean_enabled": ocean_enabled, "ocean_height": ocean_height_meters, "ocean": ocean_color}
