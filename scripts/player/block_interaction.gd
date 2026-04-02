extends Node2D
## Handles block breaking and placing interaction for the player.
## Breaking: tracks progress, shows crack overlay, delegates to ChunkManager.
## Placing: sends intent (slot + coord) to InventoryManager for host validation.

var _player: CharacterBody2D
var _terrain_layer: TileMapLayer
var _chunk_manager: Node
var _inventory_manager: Node

## Currently selected hotbar slot (0-based, indexes into first HOTBAR_SIZE inventory slots).
var selected_hotbar_slot: int = 0

## Currently targeted tile coordinate (in tile-space), or null if not mining.
var _target_coord: Vector2i = Vector2i(-99999, -99999)
var _break_progress: float = 0.0
var _break_total: float = 1.0

## Crack overlay sprite, created at runtime and positioned over the target tile.
var _crack_sprite: Sprite2D
var _crack_texture: Texture2D


func _ready() -> void:
	_player = get_parent() as CharacterBody2D
	var world := get_tree().get_root().get_node_or_null("Main/World")
	if world:
		_terrain_layer = world.get_node("TerrainLayer")
		_chunk_manager = world.get_node("ChunkManager")
	_inventory_manager = get_tree().get_root().get_node_or_null("Main/InventoryManager")
	_setup_crack_sprite()


func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not _player.is_multiplayer_authority():
		return

	if Input.is_action_pressed("break_block"):
		_handle_breaking(delta)
	else:
		_reset_breaking()

	if Input.is_action_just_pressed("place_block"):
		_handle_placing()


func _handle_breaking(delta: float) -> void:
	if _terrain_layer == null:
		return

	var mouse_world := get_global_mouse_position()
	var player_pos: Vector2 = _player.global_position

	if player_pos.distance_to(mouse_world) > GameConstants.BLOCK_INTERACT_RANGE:
		_reset_breaking()
		return

	var coord := _terrain_layer.local_to_map(mouse_world)
	if _chunk_manager == null:
		_reset_breaking()
		return

	var tile_id: int = _chunk_manager.get_tile_at(coord)
	if tile_id == TileProperties.EMPTY:
		_reset_breaking()
		return

	var props: TileProperties = TileProperties.get_properties(tile_id)
	if props == null or not props.breakable:
		_reset_breaking()
		return

	if coord != _target_coord:
		_target_coord = coord
		_break_progress = 0.0
		_break_total = props.hardness

	_break_progress += delta
	_update_crack_overlay(coord)

	if _break_progress >= _break_total:
		if _chunk_manager:
			_chunk_manager.break_tile(coord)
		_reset_breaking()


## Sends a place-block intent to the server for the currently selected hotbar slot.
func _handle_placing() -> void:
	if _terrain_layer == null or _inventory_manager == null:
		return

	var mouse_world := get_global_mouse_position()
	var player_pos: Vector2 = _player.global_position
	if player_pos.distance_to(mouse_world) > GameConstants.BLOCK_INTERACT_RANGE:
		return

	var coord := _terrain_layer.local_to_map(mouse_world)
	if _terrain_layer.get_cell_atlas_coords(coord) != Vector2i(-1, -1):
		return

	_request_place_block(coord)


func _request_place_block(coord: Vector2i) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_inventory_manager._request_place_block(selected_hotbar_slot, coord.x, coord.y)
	else:
		_inventory_manager._request_place_block.rpc_id(1, selected_hotbar_slot, coord.x, coord.y)


func _update_crack_overlay(coord: Vector2i) -> void:
	_crack_sprite.visible = true
	var tile_world := Vector2(coord) * GameConstants.TILE_SIZE
	tile_world += Vector2(GameConstants.TILE_SIZE / 2.0, GameConstants.TILE_SIZE / 2.0)
	_crack_sprite.global_position = tile_world

	var ratio: float = clampf(_break_progress / _break_total, 0.0, 1.0)
	_crack_sprite.frame = mini(
		int(ratio * float(_crack_sprite.hframes)),
		_crack_sprite.hframes - 1
	)


## Creates a crack overlay sprite with a procedural 8-frame spritesheet.
func _setup_crack_sprite() -> void:
	var frame_count: int = 8
	var size: int = GameConstants.TILE_SIZE
	var img := Image.create(size * frame_count, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var crack_color := Color(0.05, 0.08, 0.12, 0.72)
	var center := Vector2(float(size - 1) / 2.0, float(size - 1) / 2.0)
	for frame in range(frame_count):
		var offset_x: int = frame * size
		var progress := float(frame + 1) / float(frame_count)
		var primary_branches: int = 4 + frame
		for branch in range(primary_branches):
			var angle := (TAU * float(branch) / float(primary_branches)) + randf_range(-0.22, 0.22)
			var branch_length := lerpf(2.5, float(size) * 0.48, progress) + randf_range(-1.0, 1.0)
			_draw_crack_branch(img, offset_x, center, angle, branch_length, crack_color, progress)

			if frame >= 2:
				var split_count: int = 1 + int(progress * 2.0)
				for _split in range(split_count):
					var split_distance := branch_length * randf_range(0.35, 0.8)
					var split_origin := center + Vector2.from_angle(angle) * split_distance
					var split_angle := angle + randf_range(-0.9, 0.9)
					var split_length := branch_length * randf_range(0.2, 0.45)
					_draw_crack_branch(
						img,
						offset_x,
						split_origin,
						split_angle,
						split_length,
						crack_color,
						progress * 0.85
					)

	_crack_texture = ImageTexture.create_from_image(img)
	_crack_sprite = Sprite2D.new()
	_crack_sprite.texture = _crack_texture
	_crack_sprite.hframes = frame_count
	_crack_sprite.visible = false
	_crack_sprite.z_index = 10
	get_tree().get_root().call_deferred("add_child", _crack_sprite)


func _draw_crack_branch(
	img: Image,
	offset_x: int,
	start: Vector2,
	angle: float,
	length: float,
	color: Color,
	progress: float,
) -> void:
	var direction := Vector2.from_angle(angle)
	var position_on_branch := start
	var steps := maxi(int(length * 1.6), 1)

	for step in range(steps):
		var t := float(step) / float(steps)
		var wiggle := sin(t * PI * 2.0) * lerpf(0.1, 0.65, progress)
		position_on_branch += direction * (length / float(steps))
		position_on_branch += direction.orthogonal() * wiggle * 0.12

		var px := clampi(int(round(position_on_branch.x)), 0, GameConstants.TILE_SIZE - 1)
		var py := clampi(int(round(position_on_branch.y)), 0, GameConstants.TILE_SIZE - 1)
		img.set_pixel(offset_x + px, py, color)

		if progress > 0.45 and px + 1 < GameConstants.TILE_SIZE:
			img.set_pixel(offset_x + px + 1, py, color)
		if progress > 0.7 and py + 1 < GameConstants.TILE_SIZE:
			img.set_pixel(offset_x + px, py + 1, color)


func _reset_breaking() -> void:
	_target_coord = Vector2i(-99999, -99999)
	_break_progress = 0.0
	if _crack_sprite:
		_crack_sprite.visible = false
