extends Node

## Validates and applies world placement requests independently from inventory state.

var players_node: Node
var chunk_manager: Node
var structure_manager: Node


func setup(p_players_node: Node, p_chunk_manager: Node, p_structure_manager: Node) -> void:
	players_node = p_players_node
	chunk_manager = p_chunk_manager
	structure_manager = p_structure_manager


func validate_and_place_world_item(sender_id: int, item_id: int, coord: Vector2i) -> bool:
	if item_id == ItemProperties.NONE:
		return false

	var item_props := ItemProperties.get_properties(item_id)
	if item_props == null or not item_props.is_placeable():
		return false
	if chunk_manager == null or players_node == null:
		return false

	var player_node := players_node.get_node_or_null(str(sender_id))
	if player_node == null:
		return false

	var tile_center := Vector2(
		coord.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
		coord.y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0
	)
	if player_node.global_position.distance_to(tile_center) > GameConstants.BLOCK_INTERACT_RANGE:
		return false

	if item_props.places_tile():
		if not chunk_manager.can_place_top_tile_at(coord):
			return false
		if structure_manager != null and structure_manager.is_cell_occupied(coord):
			return false
		chunk_manager.place_tile(coord, item_props.tile_id)
		return true

	if item_props.places_structure():
		if structure_manager == null:
			return false
		return structure_manager.place_structure(coord, item_props.structure_id)

	return false
