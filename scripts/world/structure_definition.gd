class_name StructureDefinition
extends "res://scripts/world/world_object_definition.gd"

var footprint_size: Vector2i


func _init(
	p_id: String,
	p_footprint_size: Vector2i,
	p_cells: Array[Dictionary],
	p_anchor_offset_px: Vector2,
	p_placement_anchor_cell: Vector2i = Vector2i.ZERO,
	p_atlas_texture_path: String = DEFAULT_ATLAS_PATH,
	p_break_hardness: float = 2.0,
) -> void:
	footprint_size = p_footprint_size
	super._init(
		p_id,
		KIND_STRUCTURE,
		_normalize_cells(p_cells),
		p_anchor_offset_px,
		p_placement_anchor_cell,
		p_atlas_texture_path,
		p_break_hardness,
		1.0,
		[],
		p_id,
		false,
		0.0,
		0.0,
		float(GameConstants.TILE_SIZE),
		[],
		-1,
		p_id
	)


static func _normalize_cells(p_cells: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell_data in p_cells:
		var normalized := cell_data.duplicate(true)
		if not normalized.has("hit"):
			normalized["hit"] = bool(normalized.get("breakable", false))
		result.append(normalized)
	return result
