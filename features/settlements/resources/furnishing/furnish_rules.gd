@tool
extends Resource

class_name FurnishRules

## Per-facility-type furnishing recipe consumed by FacilityFurnisher. All
## taste dials live here (what to place, how much); placement strategy and
## walkability guarantees live in the solver. One .tres per facility type
## (bar.tres first).

## Counter pool (one is placed against the wall farthest from the door).
@export var counter_scenes: Array[PackedScene] = []
## Counter floor footprint in meters (width along the wall, depth into room).
@export var counter_footprint := Vector2(1.9, 1.0)
## Walk strip reserved between wall and counter for the staff member.
@export var counter_staff_strip_meters := 0.9

## Clusters the facility cannot function without (a jail's cell block):
## each is placed exactly once, trying every candidate spot on every
## eligible storey. If one still fits nowhere, the whole furnish fails
## loudly instead of yielding a non-functional facility.
@export var required_cluster_scenes: Array[PackedScene] = []

## Hand-authored table vignettes (FurnitureVignette roots), stamped whole.
@export var cluster_scenes: Array[PackedScene] = []
## One cluster per this many square meters of free interior floor.
@export var square_meters_per_cluster := 14.0
@export var max_clusters := 3
## Clear walking space around a table or room vignette.
@export var cluster_margin := 0.35
## Also roll clusters on upper storeys (before beds claim the space). Ground
## floors with central stairs often can't seat a large vignette; a jail's
## cell block or an inn's bunk room belongs upstairs.
@export var clusters_on_upper_floors := false

## Wall shelves, rolled per solid interior wall segment.
@export var shelf_scenes: Array[PackedScene] = []
@export_range(0.0, 1.0, 0.05) var shelf_chance := 0.45
@export var shelf_mount_height := 1.6
@export var max_shelves := 8
@export var min_shelves := 0

## Wall-mounted light fixtures (LightFixture wrappers — they switch with
## world time on their own), rolled per solid interior wall segment on every
## storey. Mounted above head height, so they never touch the floor grid.
@export var light_scenes: Array[PackedScene] = []
@export_range(0.0, 1.0, 0.05) var light_chance := 0.55
@export var light_mount_height := 2.1
## Minimum distance between two placed lights on the same storey.
@export var light_spacing_meters := 3.0
@export var max_lights_per_level := 6
@export var min_lights := 0

## Function-required utility furniture (a jail's prisoner locker, a shop's
## strongbox): each scene placed exactly once against a ground-floor wall,
## before the random containers roll. Optional developer/world-generation
## starter stock is authored separately from their reusable furniture scenes.
@export var utility_scenes: Array[PackedScene] = []
## Optional developer/world-generation starter recipes parallel to
## utility_scenes. Runtime player furnishing calls the solver without starter
## stock, so building another granary can never mint seeds or tools.
@export var utility_stock_tables: Array[ContainerStockTable] = []
## Whether a utility that fits nowhere fails the whole furnish. True for a
## jail (a cell block with no prisoner locker is broken); false where the
## utility is a convenience the town can satisfy elsewhere — a granary's seed
## barrel is found by any farmhand through the town-wide seed store search, so
## a cottage-sized granary should still furnish without one.
@export var utilities_required := true

## Floor-standing lootable containers (crates/barrels), stood against solid
## ground-floor walls after tables claim their space.
@export var container_scenes: Array[PackedScene] = []
@export_enum("general", "seeds", "tools", "food", "materials") var container_type := "general"
## Loot recipe rolled per placed container with the furnish RNG.
@export var container_stock: ContainerStockTable
@export var max_containers := 4
@export_range(0.0, 1.0, 0.05) var container_chance := 0.5
@export var min_containers := 0

## Beds for the upper floors, headboard against a wall.
@export var bed_scenes: Array[PackedScene] = []
## Small one-storey homes may place beds on their ground floor.
@export var beds_on_ground_floor := false
@export var max_beds := 4
@export_range(0.0, 1.0, 0.05) var bed_chance := 0.55
@export var min_beds := 0
## Bed floor footprint (width along wall, length into room).
@export var bed_footprint := Vector2(2.0, 2.6)

## Bulk storage pallets (BulkStoragePlatform wrappers), the function
## furniture of a granary or warehouse: they stand on the floor, self-register
## with the haul provider, and hold one crop each once stock arrives.
@export var pallet_scenes: Array[PackedScene] = []
## AUTO measures the shell: a hall wide enough for two rows plus a walkable
## aisle gets rows, anything tighter lines the pallets along its walls. The
## explicit modes force one or the other regardless of size.
@export_enum("auto", "wall_line", "aisle_rows") var pallet_layout := "auto"
## Walking aisle kept clear between two pallet rows.
@export var pallet_aisle_meters := 1.4
## Gap between neighbouring pallets within one row or wall line.
@export var pallet_gap_meters := 0.3
## Strip left between a pallet and the wall behind or beside it.
@export var pallet_wall_clearance := 0.45
## "auto" only picks rows for a room with at least this much free floor. A
## cramped store room may be geometrically wide enough for two rows, but its
## floor is worth more as walking space than as an aisle.
@export var pallet_rows_min_floor_area := 45.0
@export var max_pallets := 8
@export var min_pallets := 0
## Optional crop lock, cycled across the placed pallets: each pallet gets
## storage_item_overrides admitting exactly one of these item ids. Leave it
## empty and pallets accept any food, specializing on the first haul instead.
@export var pallet_item_ids: PackedStringArray = []
