class_name WorldProp
extends Node2D

@export var atlas_texture: Texture2D
@export var tile_size: int = GameConstants.TILE_SIZE

@onready var _sprite: Sprite2D = $Sprite
@onready var _static_body: StaticBody2D = $StaticBody2D

var _definition: WorldPropDefinition = null
var _cell: Vector2i = Vector2i.ZERO


func configure(definition: WorldPropDefinition, cell: Vector2i) -> void:
	_definition = definition
	_cell = cell
	if is_node_ready():
		_refresh_visual()


func _ready() -> void:
	_refresh_visual()


func _refresh_visual() -> void:
	for child in _static_body.get_children():
		if child is CollisionShape2D:
			child.queue_free()

	if _definition == null:
		_sprite.visible = false
		_sprite.material = null
		_static_body.process_mode = Node.PROCESS_MODE_DISABLED
		return

	_sprite.visible = true
	_sprite.texture = _make_atlas_texture(_definition)
	_sprite.position = _definition.get_sprite_offset()
	_sprite.material = _build_sway_material()

	var collision_rects := _definition.build_collision_rects()
	for rect in collision_rects:
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = rect.get("size", Vector2(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE))
		shape.shape = rectangle
		shape.position = rect.get("offset", Vector2.ZERO)
		_static_body.add_child(shape)

	_static_body.process_mode = (
		Node.PROCESS_MODE_INHERIT if not collision_rects.is_empty() else Node.PROCESS_MODE_DISABLED
	)


func _build_sway_material() -> Material:
	if _definition == null or not _definition.sway_enabled:
		return null
	var shader := load("res://assets/shaders/vegetation_sway.gdshader") as Shader
	if shader == null:
		return null
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tile_size", float(tile_size))
	material.set_shader_parameter("sprite_height_px", _definition.sprite_size_px.y)
	material.set_shader_parameter("rigid_base_px", _definition.rigid_base_px)
	material.set_shader_parameter("sway_amount", _definition.sway_amount)
	material.set_shader_parameter("sway_speed", _definition.sway_speed)
	material.set_shader_parameter("explicit_phase_mix", 1.0)
	material.set_shader_parameter(
		"phase_seed",
		float((absi(_cell.x * 73 + _cell.y * 137) % 1024)) / 1024.0 * TAU
	)
	return material


func _make_atlas_texture(definition: WorldPropDefinition) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	var atlas_source := atlas_texture
	if not definition.atlas_texture_path.is_empty():
		var custom_atlas := load(definition.atlas_texture_path) as Texture2D
		if custom_atlas != null:
			atlas_source = custom_atlas
	atlas.atlas = atlas_source
	atlas.region = Rect2(
		definition.atlas_coord.x * tile_size,
		definition.atlas_coord.y * tile_size,
		tile_size,
		tile_size
	)
	return atlas
