class_name StructureDefinition
extends RefCounted
## Immutable definition for a placeable world structure.
## Structures own their footprint, occupancy, collision cells, and visual parts.

const DEFAULT_ATLAS_PATH := "res://assets/tilesets/terrain_tiles.png"

var id: String
var footprint_size: Vector2i
var occupied_cells: Array[Vector2i]
var collision_cells: Array[Vector2i]
var breakable_cells: Array[Vector2i]
var visual_parts: Array[Dictionary]
var atlas_texture_path: String
var anchor_offset_px: Vector2
var placement_anchor_cell: Vector2i
var break_hardness: float


func _init(
	p_id: String,
	p_footprint_size: Vector2i,
	p_occupied_cells: Array[Vector2i],
	p_collision_cells: Array[Vector2i],
	p_breakable_cells: Array[Vector2i],
	p_visual_parts: Array[Dictionary],
	p_anchor_offset_px: Vector2,
	p_placement_anchor_cell: Vector2i = Vector2i.ZERO,
	p_atlas_texture_path: String = DEFAULT_ATLAS_PATH,
	p_break_hardness: float = 2.0,
) -> void:
	id = p_id
	footprint_size = p_footprint_size
	occupied_cells = p_occupied_cells.duplicate()
	collision_cells = p_collision_cells.duplicate()
	breakable_cells = p_breakable_cells.duplicate()
	visual_parts = p_visual_parts.duplicate(true)
	anchor_offset_px = p_anchor_offset_px
	placement_anchor_cell = p_placement_anchor_cell
	atlas_texture_path = p_atlas_texture_path
	break_hardness = p_break_hardness


func get_origin_cell(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("origin_x", 0)), int(data.get("origin_y", 0)))


func get_origin_from_placement_cell(target_cell: Vector2i) -> Vector2i:
	return target_cell - placement_anchor_cell


func get_world_position(origin: Vector2i) -> Vector2:
	return Vector2(
		origin.x * GameConstants.TILE_SIZE + anchor_offset_px.x,
		origin.y * GameConstants.TILE_SIZE + anchor_offset_px.y
	)


func build_visual_parts() -> Array[Dictionary]:
	return visual_parts.duplicate(true)


func build_collision_rects(tile_size_px: int = GameConstants.TILE_SIZE) -> Array[Dictionary]:
	var rects: Array[Dictionary] = []
	for cell in collision_cells:
		var top_left := Vector2(
			cell.x * tile_size_px - anchor_offset_px.x,
			cell.y * tile_size_px - anchor_offset_px.y
		)
		rects.append(
			{
				"size": Vector2(tile_size_px, tile_size_px),
				"offset": top_left + Vector2(tile_size_px / 2.0, tile_size_px / 2.0),
			}
		)
	return rects


func get_occupied_world_cells(origin: Vector2i) -> Array[Vector2i]:
	return _translate_cells(origin, occupied_cells)


func get_breakable_world_cells(origin: Vector2i) -> Array[Vector2i]:
	return _translate_cells(origin, breakable_cells)


func _translate_cells(origin: Vector2i, cells: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in cells:
		result.append(origin + cell)
	return result
