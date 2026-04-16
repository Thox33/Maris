class_name WorldPropCatalog
extends RefCounted
const WORLD_PROP_DEFINITION := preload("res://scripts/world/world_prop_definition.gd")
## Static registry of node-based single-cell world props.

const EMPTY: int = -1

static var registry: Dictionary = _build_registry()
static var by_name: Dictionary = _build_by_name()
static var coral_variants: Array[int] = _build_coral_variants()


static func get_definition(prop_id: int):
	return registry.get(prop_id)


static func resolve_placement_prop_id(prop_id: int) -> int:
	var definition = get_definition(prop_id)
	if definition == null:
		return prop_id
	if definition.placement_variants.is_empty():
		return prop_id
	var variant_index: int = randi() % definition.placement_variants.size()
	return definition.placement_variants[variant_index]


static func _build_registry() -> Dictionary:
	return {
		0: _build_coral_definition(0, "coral", Vector2i(0, 1), [0, 1, 2, 3, 4, 5]),
		1: _build_coral_definition(1, "coral_fan", Vector2i(1, 1)),
		2: _build_coral_definition(2, "coral_kelp", Vector2i(2, 1)),
		3: _build_coral_definition(3, "coral_brain", Vector2i(3, 1)),
		4: _build_coral_definition(4, "coral_anemone", Vector2i(4, 1)),
		5: _build_coral_definition(5, "coral_tube", Vector2i(5, 1)),
	}


static func _build_by_name() -> Dictionary:
	var result: Dictionary = {}
	for prop_id: int in registry:
		var definition = registry[prop_id]
		if definition != null:
			result[definition.name] = prop_id
	return result


static func _build_coral_variants() -> Array[int]:
	return [0, 1, 2, 3, 4, 5]


static func _build_coral_definition(
	prop_id: int,
	prop_name: String,
	atlas_coord: Vector2i,
	placement_variants: Array[int] = [],
):
	return WORLD_PROP_DEFINITION.new(
		prop_id,
		prop_name,
		atlas_coord,
		Vector2(GameConstants.TILE_SIZE / 2.0, GameConstants.TILE_SIZE),
		Vector2(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE),
		[],
		true,
		0.4,
		0.4,
		placement_variants,
		0,
		true,
		4.0,
		3.0,
		2.0
	)
