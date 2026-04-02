class_name ItemProperties
extends RefCounted
## Central registry of all item types.
## Separate from TileProperties — linked via optional tile_id field.
## Integer IDs are stable and permanent — never reuse a removed ID.

## Sentinel for empty slots / no item.
const NONE: int = -1

## Master registry: stable integer ID -> ItemProperties.
## To add an item: append a new entry with the next unused ID.
static var registry: Dictionary = {
	0: ItemProperties.new(0, "sand", 64, 0),
	1: ItemProperties.new(1, "stone", 64, 1),
	2: ItemProperties.new(2, "coral", 64, 2),
}

## Reverse lookup: string name -> integer ID. Keep in sync with registry.
static var by_name: Dictionary = {
	"sand": 0,
	"stone": 1,
	"coral": 2,
}

## Stable integer ID (never reuse a removed ID).
var id: int
## Canonical string key — used in save files and code.
var name: String
## Maximum number of this item per inventory slot.
var max_stack: int
## Which tile this item places when used. -1 = not placeable.
var tile_id: int


func _init(p_id: int, p_name: String, p_max_stack: int, p_tile_id: int) -> void:
	id = p_id
	name = p_name
	max_stack = p_max_stack
	tile_id = p_tile_id


## Returns properties for an item ID, or null if not found.
static func get_properties(item_id: int) -> ItemProperties:
	return registry.get(item_id)


## Returns the item ID that corresponds to a tile ID, or NONE if no item drops from that tile.
static func from_tile(p_tile_id: int) -> int:
	for item_id: int in registry:
		if (registry[item_id] as ItemProperties).tile_id == p_tile_id:
			return item_id
	return NONE


## Returns true if this item can be placed as a block in the world.
func is_placeable() -> bool:
	return tile_id != -1
