class_name ItemProperties
extends RefCounted
## Central registry of all item types.
## Separate from TileProperties — linked via optional tile_id field.
## Integer IDs are stable and permanent — never reuse a removed ID.

## Sentinel for empty slots / no item.
const NONE: int = -1

enum PlacementKind {
	NONE,
	TILE,
	STRUCTURE,
}

## Master registry: stable integer ID -> ItemProperties.
## To add an item: append a new entry with the next unused ID.
static var registry: Dictionary = {
	0: ItemProperties.new(0, "sand", 64, PlacementKind.TILE, 0, "", 0),
	1: ItemProperties.new(1, "stone", 64, PlacementKind.TILE, 1, "", 1),
	2: ItemProperties.new(2, "coral", 64, PlacementKind.TILE, 2, "", 2),
	3: ItemProperties.new(
		3,
		"large_furnace",
		16,
		PlacementKind.STRUCTURE,
		-1,
		"large_furnace",
		1
	),
}

## Reverse lookup: string name -> integer ID. Keep in sync with registry.
static var by_name: Dictionary = {
	"sand": 0,
	"stone": 1,
	"coral": 2,
	"large_furnace": 3,
}

## Stable integer ID (never reuse a removed ID).
var id: int
## Canonical string key — used in save files and code.
var name: String
## Maximum number of this item per inventory slot.
var max_stack: int
## How this item places into the world.
var placement_kind: PlacementKind
## Which tile this item places when used. -1 = not a tile-placement item.
var tile_id: int
## Which structure this item places when used. Empty = not a structure-placement item.
var structure_id: String
## Tile used to render this item in the UI/world.
var icon_tile_id: int


func _init(
	p_id: int,
	p_name: String,
	p_max_stack: int,
	p_placement_kind: PlacementKind,
	p_tile_id: int = -1,
	p_structure_id: String = "",
	p_icon_tile_id: int = -1,
) -> void:
	id = p_id
	name = p_name
	max_stack = p_max_stack
	placement_kind = p_placement_kind
	tile_id = p_tile_id
	structure_id = p_structure_id
	icon_tile_id = p_icon_tile_id if p_icon_tile_id >= 0 else p_tile_id


## Returns properties for an item ID, or null if not found.
static func get_properties(item_id: int) -> ItemProperties:
	return registry.get(item_id)


## Returns the item ID that corresponds to a tile ID, or NONE if no item drops from that tile.
static func from_tile(p_tile_id: int) -> int:
	for item_id: int in registry:
		if (registry[item_id] as ItemProperties).tile_id == p_tile_id:
			return item_id
	return NONE


static func from_structure(p_structure_id: String) -> int:
	for item_id: int in registry:
		if (registry[item_id] as ItemProperties).structure_id == p_structure_id:
			return item_id
	return NONE


## Returns true if this item can be placed as a block in the world.
func is_placeable() -> bool:
	return placement_kind != PlacementKind.NONE


func places_tile() -> bool:
	return placement_kind == PlacementKind.TILE and tile_id != -1


func places_structure() -> bool:
	return placement_kind == PlacementKind.STRUCTURE and not structure_id.is_empty()


func get_icon_tile_id() -> int:
	return icon_tile_id
