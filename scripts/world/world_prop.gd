class_name WorldProp
extends Node2D

@export var atlas_texture: Texture2D
@export var tile_size: int = GameConstants.TILE_SIZE

@onready var _sprite: Sprite2D = $Sprite
@onready var _static_body: StaticBody2D = $StaticBody2D

var _definition: WorldPropDefinition = null
var _cell: Vector2i = Vector2i.ZERO
var _break_stage: int = -1
var _crack_texture: Texture2D = null
var _is_breaking: bool = false


func configure(definition: WorldPropDefinition, cell: Vector2i) -> void:
	_definition = definition
	_cell = cell
	if is_node_ready():
		_refresh_visual()


func _ready() -> void:
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


func get_break_visual_center() -> Vector2:
	if _definition == null:
		return global_position
	return to_global(_definition.get_sprite_offset() + (_definition.sprite_size_px * 0.5))


func play_break_completion_feedback(duration: float) -> void:
	if _is_breaking:
		return
	_is_breaking = true
	clear_break_visual()
	_disable_collision()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_sprite, "modulate:a", 0.0, duration)
	tween.tween_property(_sprite, "scale", Vector2(0.92, 0.92), duration)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)


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
	_sprite.material = _build_visual_material()

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
	_refresh_break_visual()


func _build_visual_material() -> Material:
	if _definition == null:
		return null
	var shader := load("res://assets/shaders/vegetation_sway.gdshader") as Shader
	if shader == null:
		return null
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	shader_material.set_shader_parameter("tile_size", float(tile_size))
	shader_material.set_shader_parameter("sprite_height_px", _definition.sprite_size_px.y)
	shader_material.set_shader_parameter(
		"rigid_base_px",
		_definition.rigid_base_px if _definition.sway_enabled else 0.0
	)
	shader_material.set_shader_parameter(
		"sway_amount",
		_definition.sway_amount if _definition.sway_enabled else 0.0
	)
	shader_material.set_shader_parameter(
		"sway_speed",
		_definition.sway_speed if _definition.sway_enabled else 0.0
	)
	shader_material.set_shader_parameter("explicit_phase_mix", 1.0)
	shader_material.set_shader_parameter(
		"phase_seed",
		float((absi(_cell.x * 73 + _cell.y * 137) % 1024)) / 1024.0 * TAU
	)
	shader_material.set_shader_parameter("crack_enabled", false)
	shader_material.set_shader_parameter("crack_stage", -1.0)
	shader_material.set_shader_parameter("crack_frame_count", float(GameConstants.BREAK_STAGE_COUNT))
	shader_material.set_shader_parameter(
		"crack_visual_origin_px",
		_definition.get_sprite_offset() + _definition.anchor_offset_px
	)
	return shader_material


func _refresh_break_visual() -> void:
	var shader_material := _sprite.material as ShaderMaterial
	if shader_material == null:
		return
	var crack_enabled := _break_stage >= 0 and _crack_texture != null
	shader_material.set_shader_parameter("crack_enabled", crack_enabled)
	shader_material.set_shader_parameter("crack_texture", _crack_texture)
	shader_material.set_shader_parameter("crack_stage", float(_break_stage))
	shader_material.set_shader_parameter(
		"crack_visual_origin_px",
		_definition.get_sprite_offset() + _definition.anchor_offset_px
	)


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
		definition.sprite_size_px.x,
		definition.sprite_size_px.y
	)
	return atlas


func _disable_collision() -> void:
	for child in _static_body.get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).set_deferred("disabled", true)
	_static_body.process_mode = Node.PROCESS_MODE_DISABLED
