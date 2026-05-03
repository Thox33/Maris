extends Node
var _world_object_catalog = preload("res://scripts/world/world_object_catalog.gd").new()

const TARGET_KIND_TILE := "tile"
const TARGET_KIND_WORLD_OBJECT := "world_object"

const _CRACK_TEXTURE_PATH := "res://assets/effects/break_cracks.png"
const _SAMPLE_COUNT: int = 12
const _PARTICLE_COUNT: int = 24
const _PARTICLE_SPEED_MIN: float = 12.0
const _PARTICLE_SPEED_MAX: float = 38.0
const _PARTICLE_LIFETIME_MIN: float = 0.3
const _PARTICLE_LIFETIME_MAX: float = 0.55

var world: Node2D
var _chunk_manager: Node
var _world_object_manager: Node
var _effect_parent: Node2D
var _effect_root: Node2D
var _crack_texture: Texture2D
var _active_damaged_targets: Dictionary = {}
var _detached_break_completion_visuals: Dictionary = {}
var _tile_colors_cache: Dictionary = {}
var _atlas_image_cache: Dictionary = {}
var _pixel_texture: ImageTexture = null


func setup(p_world: Node2D, p_visual_parent: Node2D) -> void:
	world = p_world
	_chunk_manager = p_world.chunk_manager if p_world != null else null
	_world_object_manager = p_world.world_object_manager if p_world != null else null
	_effect_parent = p_visual_parent
	_ensure_effect_root()
	_ensure_crack_texture()
	_connect_breakable_visual_signals()
	GameEvents.block_broken.connect(_on_block_broken)
	GameEvents.world_object_broken.connect(_on_world_object_broken)


func apply_damaged_target(target_key: String, target_data: Dictionary) -> void:
	if world == null:
		return
	_ensure_crack_texture()
	_active_damaged_targets[target_key] = target_data.duplicate(true)
	_apply_break_visual(_resolve_visual_for_target(target_key, _active_damaged_targets[target_key]), target_data)


func clear_damaged_target(target_key: String) -> void:
	var target_data := _active_damaged_targets.get(target_key, {}) as Dictionary
	_active_damaged_targets.erase(target_key)
	_clear_break_visual(_resolve_visual_for_target(target_key, target_data))


func _connect_breakable_visual_signals() -> void:
	var on_visual_created := Callable(self, "_on_breakable_world_visual_created")
	var on_visual_detached := Callable(self, "_on_breakable_world_visual_detached")
	if (
		_chunk_manager != null
		and _chunk_manager.has_signal("breakable_world_visual_created")
		and not _chunk_manager.is_connected("breakable_world_visual_created", on_visual_created)
	):
		_chunk_manager.connect("breakable_world_visual_created", on_visual_created)
	if (
		_world_object_manager != null
		and _world_object_manager.has_signal("breakable_world_visual_created")
		and not _world_object_manager.is_connected("breakable_world_visual_created", on_visual_created)
	):
		_world_object_manager.connect("breakable_world_visual_created", on_visual_created)
	if (
		_world_object_manager != null
		and _world_object_manager.has_signal("breakable_world_visual_detached")
		and not _world_object_manager.is_connected("breakable_world_visual_detached", on_visual_detached)
	):
		_world_object_manager.connect("breakable_world_visual_detached", on_visual_detached)


func _ensure_effect_root() -> void:
	if world == null:
		return
	if _effect_root != null and is_instance_valid(_effect_root):
		return
	if _effect_parent == null:
		return
	_effect_root = Node2D.new()
	_effect_root.name = "BreakEffects"
	_effect_parent.add_child(_effect_root)


func _ensure_crack_texture() -> void:
	if _crack_texture != null:
		return

	var texture := load(_CRACK_TEXTURE_PATH) as Texture2D
	if texture == null:
		push_error("BreakVisualService failed to load crack frames: %s" % _CRACK_TEXTURE_PATH)
		return
	var image := texture.get_image()
	if image == null:
		push_error("BreakVisualService failed to inspect crack frames: %s" % _CRACK_TEXTURE_PATH)
		return
	var expected_width := GameConstants.TILE_SIZE * GameConstants.BREAK_STAGE_COUNT
	var expected_height := GameConstants.TILE_SIZE
	if image.get_width() != expected_width or image.get_height() != expected_height:
		push_error(
			(
				"BreakVisualService crack frames at %s must be %sx%s, got %sx%s"
				% [
					_CRACK_TEXTURE_PATH,
					expected_width,
					expected_height,
					image.get_width(),
					image.get_height(),
				]
			)
		)
		return
	_crack_texture = texture


func _on_block_broken(coord: Vector2i, tile_id: int) -> void:
	_spawn_break_particles(_cell_center(coord), _sample_tile_colors(tile_id))


func _on_world_object_broken(object_id: String, origin: Vector2i, world_pos: Vector2) -> void:
	var target_key := _world_object_target_key(object_id, origin)
	var detached_visual := _consume_detached_break_completion_visual(target_key)
	if detached_visual != null:
		_clear_break_visual(detached_visual)

	var center := world_pos
	if detached_visual != null and detached_visual.has_method("get_break_visual_center"):
		center = detached_visual.get_break_visual_center()

	_spawn_break_particles(center, _sample_world_object_colors(object_id))

	if detached_visual != null:
		if detached_visual.has_method("play_break_completion_feedback"):
			detached_visual.play_break_completion_feedback(_PARTICLE_LIFETIME_MAX)
		else:
			detached_visual.queue_free()


func _sample_tile_colors(tile_id: int) -> Array[Color]:
	if _tile_colors_cache.has(tile_id):
		return _tile_colors_cache[tile_id]

	var props := TileProperties.get_properties(tile_id)
	if props == null:
		return [Color.WHITE]

	var atlas_path := "res://assets/tilesets/terrain_tiles.png"
	var image := _load_atlas_image(atlas_path)
	if image == null:
		return [Color.WHITE]

	var ts := GameConstants.TILE_SIZE
	var region_x := props.atlas_coord.x * ts
	var region_y := props.atlas_coord.y * ts
	var sampled := _sample_region(image, region_x, region_y, ts, ts)

	_tile_colors_cache[tile_id] = sampled
	return sampled


func _sample_world_object_colors(object_id: String) -> Array[Color]:
	var cache_key := "w:" + object_id
	if _tile_colors_cache.has(cache_key):
		return _tile_colors_cache[cache_key]

	var definition = _world_object_catalog.call("get_definition", object_id)
	if definition == null:
		return [Color.WHITE]

	var visual_parts: Array = definition.build_visual_parts()
	if visual_parts.is_empty():
		return [Color.WHITE]

	var image := _load_atlas_image(definition.atlas_texture_path)
	if image == null:
		return [Color.WHITE]

	var ts := GameConstants.TILE_SIZE
	var all_pixels: Array[Color] = []
	for part in visual_parts:
		var coord := part.get("atlas_coord", Vector2i.ZERO) as Vector2i
		var size_px := part.get("size_px", Vector2(ts, ts)) as Vector2
		var part_pixels := _sample_region(
			image,
			coord.x * ts,
			coord.y * ts,
			maxi(1, int(size_px.x)),
			maxi(1, int(size_px.y))
		)
		all_pixels.append_array(part_pixels)

	# Shuffle and trim to _SAMPLE_COUNT so all parts contribute roughly equally.
	all_pixels.shuffle()
	var sampled: Array[Color] = all_pixels.slice(0, _SAMPLE_COUNT)
	if sampled.is_empty():
		sampled.append(Color.WHITE)

	_tile_colors_cache[cache_key] = sampled
	return sampled


func _spawn_break_particles(center: Vector2, colors: Array[Color]) -> void:
	_ensure_effect_root()
	if _effect_root == null:
		return

	for i in range(_PARTICLE_COUNT):
		var angle := randf() * TAU
		var speed := randf_range(_PARTICLE_SPEED_MIN, _PARTICLE_SPEED_MAX)
		var end_pos := center + Vector2.from_angle(angle) * speed
		var duration := randf_range(_PARTICLE_LIFETIME_MIN, _PARTICLE_LIFETIME_MAX)

		var sprite := Sprite2D.new()
		sprite.texture = _get_pixel_texture()
		sprite.modulate = colors[i % colors.size()]
		sprite.scale = Vector2(2.0, 2.0)
		sprite.z_index = 25
		_effect_root.add_child(sprite)
		sprite.global_position = center

		var tween := sprite.create_tween()
		tween.set_parallel(true)
		(
			tween
			. tween_property(sprite, "global_position", end_pos, duration)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		tween.tween_property(sprite, "modulate:a", 0.0, duration)
		tween.set_parallel(false)
		tween.tween_callback(sprite.queue_free)


func _load_atlas_image(atlas_path: String) -> Image:
	if _atlas_image_cache.has(atlas_path):
		return _atlas_image_cache[atlas_path]
	var tex := load(atlas_path) as Texture2D
	var image: Image = tex.get_image() if tex != null else null
	_atlas_image_cache[atlas_path] = image
	return image


func _sample_region(image: Image, region_x: int, region_y: int, w: int, h: int) -> Array[Color]:
	var sampled: Array[Color] = []
	var attempts := 0
	while sampled.size() < _SAMPLE_COUNT and attempts < 300:
		attempts += 1
		var px := region_x + randi() % w
		var py := region_y + randi() % h
		if px < image.get_width() and py < image.get_height():
			var color := image.get_pixel(px, py)
			if color.a > 0.5:
				sampled.append(color)
	if sampled.is_empty():
		sampled.append(Color.WHITE)
	return sampled


func _get_pixel_texture() -> ImageTexture:
	if _pixel_texture != null:
		return _pixel_texture
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	_pixel_texture = ImageTexture.create_from_image(img)
	return _pixel_texture


func _resolve_visual_for_target(target_key: String, target_data: Dictionary) -> Node:
	var kind := String(target_data.get("kind", _target_kind_from_key(target_key)))
	if kind == TARGET_KIND_TILE:
		return _get_breakable_tile_visual(_coord_from_target(target_key, target_data))
	if kind == TARGET_KIND_WORLD_OBJECT:
		var world_object_target := _world_object_target_from_data(target_key, target_data)
		if world_object_target.is_empty():
			return null
		return _get_world_object_visual(
			String(world_object_target.get("object_id", "")),
			world_object_target.get("origin", Vector2i.ZERO) as Vector2i
		)
	return null


func _apply_break_visual(target_visual: Node, target_data: Dictionary) -> void:
	if target_visual == null or not target_visual.has_method("apply_break_visual"):
		return
	target_visual.apply_break_visual(
		clampi(int(target_data.get("stage", 0)), 0, GameConstants.BREAK_STAGE_COUNT - 1),
		_crack_texture
	)


func _clear_break_visual(target_visual: Node) -> void:
	if target_visual == null or not target_visual.has_method("clear_break_visual"):
		return
	target_visual.clear_break_visual()


func _get_breakable_tile_visual(coord: Vector2i) -> Node:
	if _chunk_manager == null or not _chunk_manager.has_method("get_breakable_tile_visual"):
		return null
	return _chunk_manager.get_breakable_tile_visual(coord) as Node


func _get_world_object_visual(object_id: String, origin: Vector2i) -> Node:
	if _world_object_manager == null or not _world_object_manager.has_method("get_world_object_visual"):
		return null
	return _world_object_manager.get_world_object_visual(object_id, origin) as Node


func _on_breakable_world_visual_created(target_key: String, visual: Node) -> void:
	var target_data := _active_damaged_targets.get(target_key, {}) as Dictionary
	if target_data.is_empty():
		return
	_apply_break_visual(visual, target_data)


func _on_breakable_world_visual_detached(target_key: String, visual: Node) -> void:
	var previous_visual := _detached_break_completion_visuals.get(target_key) as Node
	if previous_visual != null and is_instance_valid(previous_visual) and previous_visual != visual:
		previous_visual.queue_free()
	_detached_break_completion_visuals[target_key] = visual


func _target_kind_from_key(target_key: String) -> String:
	var parts := target_key.split(":")
	if parts.is_empty():
		return ""
	return parts[0]


func _coord_from_target(target_key: String, target_data: Dictionary) -> Vector2i:
	if target_data.has("coord_x") and target_data.has("coord_y"):
		return Vector2i(int(target_data.get("coord_x", 0)), int(target_data.get("coord_y", 0)))
	var parts := target_key.split(":")
	if parts.size() != 3:
		return Vector2i.ZERO
	return Vector2i(int(parts[1]), int(parts[2]))


func _world_object_target_from_data(target_key: String, target_data: Dictionary) -> Dictionary:
	if target_data.has("object_id") and target_data.has("origin_x") and target_data.has("origin_y"):
		return {
			"object_id": String(target_data.get("object_id", "")),
			"origin": Vector2i(int(target_data.get("origin_x", 0)), int(target_data.get("origin_y", 0))),
		}

	var parts := target_key.split(":")
	if parts.size() != 4:
		return {}
	return {
		"object_id": parts[1],
		"origin": Vector2i(int(parts[2]), int(parts[3])),
	}


func _consume_detached_break_completion_visual(target_key: String) -> Node:
	var visual := _detached_break_completion_visuals.get(target_key) as Node
	_detached_break_completion_visuals.erase(target_key)
	if visual == null or not is_instance_valid(visual):
		return null
	return visual


func _world_object_target_key(object_id: String, origin: Vector2i) -> String:
	return "world_object:%s:%s:%s" % [object_id, origin.x, origin.y]


func _cell_center(coord: Vector2i) -> Vector2:
	return Vector2(
		coord.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
		coord.y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0
	)
