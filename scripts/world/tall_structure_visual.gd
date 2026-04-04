class_name TallStructureVisual
extends Node2D

@export var atlas_texture: Texture2D
@export var tile_size: int = GameConstants.TILE_SIZE
@export var collision_enabled: bool = true

@onready var _parts_root: Node2D = $Parts
@onready var _static_body: StaticBody2D = $StaticBody2D

var _parts: Array[Dictionary] = []
var _collision_rects: Array[Dictionary] = []


func _ready() -> void:
	_refresh_visual()


func configure_parts(
	parts: Array[Dictionary],
	p_collision_enabled: bool,
	p_collision_rects: Array[Dictionary] = [],
) -> void:
	_parts = []
	for part in parts:
		_parts.append(part.duplicate(true))
	collision_enabled = p_collision_enabled
	_collision_rects = []
	for rect in p_collision_rects:
		_collision_rects.append(rect.duplicate(true))
	if is_node_ready():
		_refresh_visual()


func _refresh_visual() -> void:
	for child in _parts_root.get_children():
		child.queue_free()

	if atlas_texture != null:
		for part in _parts:
			var atlas_coord := part.get("atlas_coord", Vector2i.ZERO) as Vector2i
			var offset := part.get("offset", Vector2.ZERO) as Vector2
			var z_index := int(part.get("z_index", 0))

			var sprite := Sprite2D.new()
			sprite.texture = _make_atlas_texture(atlas_coord)
			sprite.centered = false
			sprite.position = offset
			sprite.z_index = z_index
			_parts_root.add_child(sprite)

	for child in _static_body.get_children():
		if child is CollisionShape2D:
			child.queue_free()

	var active_collision_rects := _collision_rects
	if active_collision_rects.is_empty() and collision_enabled:
		active_collision_rects = [
			{
				"size": Vector2(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE),
				"offset": Vector2(0, -GameConstants.TILE_SIZE / 2.0),
			}
		]

	for rect in active_collision_rects:
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = rect.get("size", Vector2(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE))
		shape.shape = rectangle
		shape.position = rect.get("offset", Vector2.ZERO)
		_static_body.add_child(shape)

	var collision_active := collision_enabled and not active_collision_rects.is_empty()
	_static_body.process_mode = (
		Node.PROCESS_MODE_INHERIT if collision_active else Node.PROCESS_MODE_DISABLED
	)


func _make_atlas_texture(coord: Vector2i) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = atlas_texture
	atlas.region = Rect2(coord.x * tile_size, coord.y * tile_size, tile_size, tile_size)
	return atlas
