extends Node

const ITEM_ENTITY_SCENE := preload("res://scenes/items/item_entity.tscn")

var _item_spawner: MultiplayerSpawner
var _inventory_manager: Node
var _is_initialized: bool = false


func setup(item_spawner: MultiplayerSpawner, inventory_manager: Node) -> void:
	_item_spawner = item_spawner
	_inventory_manager = inventory_manager
	if _is_initialized:
		return
	GameEvents.block_broken.connect(_on_block_broken)
	GameEvents.structure_broken.connect(_on_structure_broken)
	_is_initialized = true


func create_item_entity(data: Dictionary) -> Node:
	var entity := ITEM_ENTITY_SCENE.instantiate()
	if entity.has_method("setup_inventory_manager"):
		entity.setup_inventory_manager(_inventory_manager)
	var initial_velocity := Vector2(
		float(data.get("vx", 0.0)),
		float(data.get("vy", 0.0)),
	)
	entity.initialize(data["item_id"], data["count"], initial_velocity)
	entity.position = Vector2(data["x"], data["y"])
	return entity


func spawn_item_drop(
	item_id: int,
	count: int,
	world_pos: Vector2,
	initial_velocity: Vector2 = Vector2.ZERO,
) -> void:
	if not multiplayer.is_server():
		return
	_item_spawner.spawn(
		{
			"item_id": item_id,
			"count": count,
			"x": world_pos.x,
			"y": world_pos.y,
			"vx": initial_velocity.x,
			"vy": initial_velocity.y,
		}
	)


func _on_block_broken(coord: Vector2i, tile_id: int) -> void:
	if not multiplayer.is_server():
		return

	var props := TileProperties.get_properties(tile_id)
	if props == null:
		return

	var drop_id: int = props.drop_tile_id if props else tile_id
	var item_id: int = ItemProperties.from_tile(drop_id)
	if item_id == ItemProperties.NONE:
		return

	var tile_center := Vector2(
		coord.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
		coord.y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0
	)
	spawn_item_drop(item_id, 1, tile_center)


func _on_structure_broken(structure_id: String, world_pos: Vector2) -> void:
	if not multiplayer.is_server():
		return

	var item_id := ItemProperties.from_structure(structure_id)
	if item_id == ItemProperties.NONE:
		return
	spawn_item_drop(item_id, 1, world_pos)
