class_name TallStructureVisual
extends Node2D

@export var atlas_texture: Texture2D
@export var tile_size: int = GameConstants.TILE_SIZE
@export var collision_enabled: bool = true

@onready var _parts_root: Node2D = $Parts
@onready var _static_body: StaticBody2D = $StaticBody2D

var _parts: Array[Dictionary] = []
var _collision_rects: Array[Dictionary] = []
var _break_stage: int = -1
var _crack_texture: Texture2D = null
var _grid_anchor_offset_px: Vector2 = Vector2(GameConstants.TILE_SIZE / 2.0, GameConstants.TILE_SIZE)


func _ready() -> void:
	_refresh_visual()


func configure_parts(
	parts: Array[Dictionary],
	p_collision_enabled: bool,
	p_collision_rects: Array[Dictionary] = [],
	p_grid_anchor_offset_px: Vector2 = Vector2(
		GameConstants.TILE_SIZE / 2.0,
		GameConstants.TILE_SIZE
	),
) -> void:
	_parts = []
	for part in parts:
		_parts.append(part.duplicate(true))
	collision_enabled = p_collision_enabled
	_grid_anchor_offset_px = p_grid_anchor_offset_px
	_collision_rects = []
	for rect in p_collision_rects:
		_collision_rects.append(rect.duplicate(true))
	if is_node_ready():
		_refresh_visual()


func apply_break_visual(stage: int, crack_texture: Texture2D) -> void:
	_break_stage = stage
	_crack_texture = crack_texture
	if is_node_ready():
		_refresh_break_visual()


func clear_break_visual() -> void:
	_break_stage = -1
	_crack_texture = null
	if is_node_ready():
		_refresh_break_visual()


func _refresh_visual() -> void:
	for child in _parts_root.get_children():
		child.queue_free()

	if atlas_texture != null:
		for part in _parts:
			var atlas_coord := part.get("atlas_coord", Vector2i.ZERO) as Vector2i
			var offset := part.get("offset", Vector2.ZERO) as Vector2
			var part_z_index := int(part.get("z_index", 0))

			var sprite := Sprite2D.new()
			sprite.texture = _make_atlas_texture(atlas_coord)
			sprite.centered = false
			sprite.position = offset
			sprite.z_index = part_z_index
			sprite.material = _build_part_material(offset)
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
	_refresh_break_visual()


func _build_part_material(part_offset: Vector2) -> Material:
	var shader := load("res://assets/shaders/vegetation_sway.gdshader") as Shader
	if shader == null:
		return null
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	shader_material.set_shader_parameter("tile_size", float(tile_size))
	shader_material.set_shader_parameter("sprite_height_px", float(tile_size))
	shader_material.set_shader_parameter("rigid_base_px", float(tile_size))
	shader_material.set_shader_parameter("sway_amount", 0.0)
	shader_material.set_shader_parameter("sway_speed", 0.0)
	shader_material.set_shader_parameter("explicit_phase_mix", 1.0)
	shader_material.set_shader_parameter("phase_seed", 0.0)
	shader_material.set_shader_parameter("crack_enabled", false)
	shader_material.set_shader_parameter("crack_stage", -1.0)
	shader_material.set_shader_parameter("crack_frame_count", float(GameConstants.BREAK_STAGE_COUNT))
	shader_material.set_shader_parameter(
		"crack_visual_origin_px",
		part_offset + _grid_anchor_offset_px
	)
	return shader_material


func _refresh_break_visual() -> void:
	for child in _parts_root.get_children():
		var sprite := child as Sprite2D
		if sprite == null:
			continue
		var shader_material := sprite.material as ShaderMaterial
		if shader_material == null:
			shader_material = _build_part_material(sprite.position) as ShaderMaterial
			sprite.material = shader_material
		if shader_material == null:
			continue
		var crack_enabled := _break_stage >= 0 and _crack_texture != null
		shader_material.set_shader_parameter("crack_enabled", crack_enabled)
		shader_material.set_shader_parameter("crack_texture", _crack_texture)
		shader_material.set_shader_parameter("crack_stage", float(_break_stage))
		shader_material.set_shader_parameter(
			"crack_visual_origin_px",
			sprite.position + _grid_anchor_offset_px
		)


func _make_atlas_texture(coord: Vector2i) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = atlas_texture
	atlas.region = Rect2(coord.x * tile_size, coord.y * tile_size, tile_size, tile_size)
	return atlas
