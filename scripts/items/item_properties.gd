class_name ItemProperties
extends RefCounted

const ITEM_HOLD_STYLE_CATALOG := preload("res://scripts/items/item_hold_style_catalog.gd")
## Central registry of all item types.
## Separate from TileProperties — linked via optional tile_id field.
## Integer IDs are stable and permanent — never reuse a removed ID.

## Sentinel for empty slots / no item.
const NONE: int = -1
const DEFAULT_ICON_ATLAS_PATH := "res://assets/tilesets/terrain_tiles.png"
const INVALID_ICON_COORD := Vector2i(-1, -1)

enum PlacementKind {
	NONE,
	TILE,
	STRUCTURE,
}

enum ToolKind {
	NONE,
	PICKAXE,
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
	4: ItemProperties.new(
		4,
		"stone_pickaxe",
		1,
		PlacementKind.NONE,
		-1,
		"",
		1,
		0.75,
		0.18,
		ToolKind.PICKAXE,
		"res://assets/tilesets/tool_items.png",
		Vector2i(0, 0),
		ITEM_HOLD_STYLE_CATALOG.STYLE_TOOL_UP_RIGHT
	),
}

## Reverse lookup: string name -> integer ID. Keep in sync with registry.
static var by_name: Dictionary = {
	"sand": 0,
	"stone": 1,
	"coral": 2,
	"large_furnace": 3,
	"stone_pickaxe": 4,
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
## Optional atlas path for a custom icon sheet.
var icon_atlas_path: String
## Optional atlas coordinate inside a custom icon sheet.
var icon_atlas_coord: Vector2i
## Base break damage when this item is used against a breakable target.
var break_damage: float
## Cooldown in seconds before this item may perform the next primary use.
var use_cooldown: float
## Optional tool classification for gameplay rules and balancing.
var tool_kind: ToolKind
## Style profile for held rendering.
var hold_style_id: String
## Optional item-specific additional shift from the resolved grip pixel.
var hold_grip_offset: Vector2
## Optional absolute scale override. Negative values mean "use style default".
var hold_scale_override: Vector2


func _init(
	p_id: int,
	p_name: String,
	p_max_stack: int,
	p_placement_kind: PlacementKind,
	p_tile_id: int = -1,
	p_structure_id: String = "",
	p_icon_tile_id: int = -1,
	p_break_damage: float = GameConstants.BREAK_BASE_DAMAGE,
	p_use_cooldown: float = GameConstants.PRIMARY_USE_COOLDOWN,
	p_tool_kind: ToolKind = ToolKind.NONE,
	p_icon_atlas_path: String = "",
	p_icon_atlas_coord: Vector2i = INVALID_ICON_COORD,
	p_hold_style_id: String = "",
	p_hold_grip_offset: Vector2 = Vector2.ZERO,
	p_hold_scale_override: Vector2 = Vector2(-1, -1),
) -> void:
	id = p_id
	name = p_name
	max_stack = p_max_stack
	placement_kind = p_placement_kind
	tile_id = p_tile_id
	structure_id = p_structure_id
	icon_tile_id = p_icon_tile_id if p_icon_tile_id >= 0 else p_tile_id
	icon_atlas_path = p_icon_atlas_path
	icon_atlas_coord = p_icon_atlas_coord
	break_damage = maxf(p_break_damage, 0.0)
	use_cooldown = maxf(p_use_cooldown, 0.0)
	tool_kind = p_tool_kind
	hold_style_id = p_hold_style_id
	hold_grip_offset = p_hold_grip_offset
	hold_scale_override = p_hold_scale_override


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


func get_icon_atlas_path() -> String:
	if not icon_atlas_path.is_empty():
		return icon_atlas_path
	return DEFAULT_ICON_ATLAS_PATH


func get_icon_atlas_coord() -> Vector2i:
	if icon_atlas_coord != INVALID_ICON_COORD:
		return icon_atlas_coord
	var tile_props := TileProperties.get_properties(icon_tile_id)
	if tile_props == null:
		return INVALID_ICON_COORD
	return tile_props.atlas_coord


func build_icon_texture() -> Texture2D:
	var atlas_coord := get_icon_atlas_coord()
	if atlas_coord == INVALID_ICON_COORD:
		return null
	var atlas := load(get_icon_atlas_path()) as Texture2D
	if atlas == null:
		return null

	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = atlas
	var tile_size := GameConstants.TILE_SIZE
	atlas_texture.region = Rect2(
		atlas_coord.x * tile_size,
		atlas_coord.y * tile_size,
		tile_size,
		tile_size
	)
	return atlas_texture


func get_break_damage() -> float:
	return break_damage


func get_use_cooldown() -> float:
	return use_cooldown


func get_tool_kind() -> ToolKind:
	return tool_kind


func is_tool() -> bool:
	return tool_kind != ToolKind.NONE


func get_hold_style_id() -> String:
	if not hold_style_id.is_empty():
		return hold_style_id
	return (
		ITEM_HOLD_STYLE_CATALOG.STYLE_TOOL_UP_RIGHT
		if is_tool()
		else ITEM_HOLD_STYLE_CATALOG.STYLE_SMALL_ITEM
	)


func get_hold_scale() -> Vector2:
	if hold_scale_override.x >= 0.0 and hold_scale_override.y >= 0.0:
		return hold_scale_override
	var style := ITEM_HOLD_STYLE_CATALOG.get_style(get_hold_style_id())
	return style.get("scale", Vector2.ONE) as Vector2


func get_hold_grip_point(texture_size: Vector2) -> Vector2:
	var style := ITEM_HOLD_STYLE_CATALOG.get_style(get_hold_style_id())
	var grip_mode := String(style.get("grip_mode", "bottom_center"))
	var grip_point := _resolve_hold_grip_point(grip_mode, texture_size)
	var style_offset := style.get("grip_pixel_offset", Vector2.ZERO) as Vector2
	return grip_point + style_offset + hold_grip_offset


func _resolve_hold_grip_point(grip_mode: String, texture_size: Vector2) -> Vector2:
	match grip_mode:
		"bottom_center":
			return Vector2((texture_size.x - 1.0) * 0.5, texture_size.y - 1.0)
	return texture_size * 0.5
