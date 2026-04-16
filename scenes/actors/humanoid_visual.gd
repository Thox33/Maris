class_name HumanoidVisual
extends Node2D

const ACTOR_STATE := preload("res://scripts/actor/actor_state.gd")
const ITEM_ICON_VISUALS := preload("res://scripts/items/item_icon_visuals.gd")
const CHARACTER_APPEARANCE := preload("res://scripts/actor/character_appearance.gd")
const HUMANOID_VISUAL_PROFILE := preload("res://scripts/actor/humanoid_visual_profile.gd")
const ITEM_PROPERTIES := preload("res://scripts/items/item_properties.gd")


@export var visual_profile: HumanoidVisualProfile

@onready var _body: AnimatedSprite2D = $Body
@onready var _hair: Sprite2D = $Hair
@onready var _face: Sprite2D = $Face
@onready var _held_item_anchor: Node2D = $HeldItemAnchor

var _actor: Node
var _appearance: Dictionary = CHARACTER_APPEARANCE.create_default_appearance()
var _current_animation: String = ""
var _held_item_grip_offset: Vector2 = Vector2.ZERO
var _profile: HumanoidVisualProfile
var _held_item_sprite: Sprite2D
var _displayed_held_item_id: int = ITEM_PROPERTIES.NONE
var _current_held_item_id: int = ITEM_PROPERTIES.NONE
var _current_head_item_id: int = ITEM_PROPERTIES.NONE
var _head_anchor: Node2D
var _eye_sprite: Sprite2D
var _mouth_sprite: Sprite2D

# Eye frame indices matching eyes_directions.png layout
const _EYE_NEUTRAL := 0
const _EYE_RIGHT := 1
const _EYE_UP_RIGHT := 2
const _EYE_UP := 3
const _EYE_UP_LEFT := 4
const _EYE_LEFT := 5
const _EYE_DOWN_LEFT := 6
const _EYE_DOWN := 7
const _EYE_DOWN_RIGHT := 8


func _ready() -> void:
	_profile = visual_profile if visual_profile != null else HUMANOID_VISUAL_PROFILE.create_default_profile()
	_load_sprites()
	_ensure_held_item_sprite()
	_body.frame_changed.connect(_on_body_frame_changed)
	_apply_appearance_colors()
	_refresh_hair_visual()
	_refresh_held_item_visual()


## Call this from the owning actor's _ready() to wire up state updates.
## Replaces the fragile get_parent().get_parent() tree walk.
func setup(actor: Node) -> void:
	_actor = actor
	if actor.has_signal("actor_state_changed"):
		actor.actor_state_changed.connect(_on_actor_state_changed)
	if actor.has_method("get_actor_appearance"):
		_appearance = CHARACTER_APPEARANCE.normalize_appearance(actor.get_actor_appearance())
	_refresh_from_actor()
	_apply_appearance_colors()
	_refresh_hair_visual()
	_refresh_held_item_visual()


func apply_appearance(appearance: Dictionary) -> void:
	_appearance = CHARACTER_APPEARANCE.normalize_appearance(appearance)
	_apply_appearance_colors()
	_refresh_hair_visual()


func set_visual_profile(profile: HumanoidVisualProfile) -> void:
	if profile == null:
		return
	visual_profile = profile
	_profile = profile
	if is_node_ready():
		_load_sprites()
		_update_held_item_anchor()
		_update_head_anchor()


func get_held_item_anchor() -> Node2D:
	return _held_item_anchor


func set_inventory_manager(_inventory_manager: Node) -> void:
	pass


func set_held_item_grip_offset(offset: Vector2) -> void:
	_held_item_grip_offset = offset
	_update_held_item_anchor()


func clear_held_item_grip_offset() -> void:
	set_held_item_grip_offset(Vector2.ZERO)


func _on_actor_state_changed() -> void:
	_refresh_from_actor()


func _on_body_frame_changed() -> void:
	_update_held_item_anchor()
	_update_head_anchor()


func _refresh_from_actor() -> void:
	if _actor == null or not _actor.has_method("get_actor_state"):
		return
	_apply_actor_state(_actor.get_actor_state())


func _apply_actor_state(actor_state: Dictionary) -> void:
	var locomotion := ACTOR_STATE.normalize_locomotion(
		String(actor_state.get("locomotion_state", ACTOR_STATE.LOCOMOTION_IDLE))
	)
	var mirrored := bool(actor_state.get("side_view_mirrored", false))
	scale.x = -1.0 if mirrored else 1.0
	var anim := "run" if locomotion == ACTOR_STATE.LOCOMOTION_MOVE else "idle"
	_play_animation(anim)
	_apply_held_item_id(int(actor_state.get("held_item_id", ITEM_PROPERTIES.NONE)))
	_apply_head_item_id(int(actor_state.get("equipped_head_item_id", ITEM_PROPERTIES.NONE)))


func _apply_appearance_colors() -> void:
	var body_palette := CHARACTER_APPEARANCE.get_outfit_color_palette(
		String(_appearance.get("top_color_id", CHARACTER_APPEARANCE.DEFAULT_TOP_COLOR_ID))
	)
	var hair_palette := CHARACTER_APPEARANCE.get_hair_color_palette(
		String(_appearance.get("hair_color_id", CHARACTER_APPEARANCE.DEFAULT_HAIR_COLOR_ID))
	)
	_body.modulate = CHARACTER_APPEARANCE.get_palette_base(body_palette)
	_hair.modulate = CHARACTER_APPEARANCE.get_palette_base(hair_palette)


func _play_animation(anim_name: String) -> void:
	if _current_animation == anim_name:
		return
	_current_animation = anim_name
	if _body.sprite_frames != null and _body.sprite_frames.has_animation(anim_name):
		_body.play(anim_name)
	_update_held_item_anchor()
	_update_head_anchor()


func set_look_direction(world_dir: Vector2) -> void:
	if _eye_sprite == null:
		return
	_set_eye_frame(_look_dir_to_eye_frame(world_dir))


func _load_sprites() -> void:
	var body_frames := _build_body_frames()
	if body_frames != null:
		_body.sprite_frames = body_frames
		_body.play("idle")
		_update_held_item_anchor()
	_face.visible = false
	_setup_head_layers()
	_refresh_hair_visual()


func _setup_head_layers() -> void:
	if _head_anchor == null:
		_head_anchor = Node2D.new()
		_head_anchor.name = "HeadAnchor"
		add_child(_head_anchor)
		# Head layers must render above the body but below the held item.
		if _held_item_anchor != null:
			move_child(_head_anchor, _held_item_anchor.get_index())
	if _hair != null and _hair.get_parent() != _head_anchor:
		var hair_parent := _hair.get_parent()
		if hair_parent != null:
			hair_parent.remove_child(_hair)
		_head_anchor.add_child(_hair)
	_hair.centered = true
	_hair.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hair.position = _profile.hair_local_offset
	if _eye_sprite == null:
		_eye_sprite = Sprite2D.new()
		_eye_sprite.name = "EyeSprite"
		_eye_sprite.centered = true
		_eye_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_head_anchor.add_child(_eye_sprite)
	var eye_texture := _load_texture(_profile.eye_path)
	if eye_texture != null:
		_eye_sprite.texture = eye_texture
		_eye_sprite.region_enabled = true
		_set_eye_frame(_EYE_NEUTRAL)
	_eye_sprite.position = _profile.eye_local_offset
	if _mouth_sprite == null:
		_mouth_sprite = Sprite2D.new()
		_mouth_sprite.name = "MouthSprite"
		_mouth_sprite.centered = true
		_mouth_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_head_anchor.add_child(_mouth_sprite)
	var mouth_texture := _load_texture(_profile.mouth_path)
	if mouth_texture != null:
		_mouth_sprite.texture = mouth_texture
		_mouth_sprite.region_enabled = true
		_mouth_sprite.region_rect = Rect2(0, 0, _profile.mouth_frame_width, _profile.mouth_frame_height)
	_mouth_sprite.position = _profile.mouth_local_offset
	_mouth_sprite.scale.x = scale.x
	_update_head_anchor()


func _update_head_anchor() -> void:
	if _head_anchor == null:
		return
	var anim_name: String = (
		_current_animation if not _current_animation.is_empty() else String(_body.animation)
	)
	var frame_index: int = _body.frame if _body != null else 0
	_head_anchor.position = _profile.get_head_offset(anim_name, frame_index)


func _set_eye_frame(frame: int) -> void:
	if _eye_sprite == null:
		return
	var fw := _profile.eye_frame_width
	var fh := _profile.eye_frame_height
	_eye_sprite.region_rect = Rect2(frame * fw, 0, fw, fh)
	# Counteract parent scale so face textures are never auto-mirrored
	# (all 8 directions are explicitly painted)
	_eye_sprite.scale.x = scale.x
	if _mouth_sprite != null:
		_mouth_sprite.scale.x = scale.x


func _look_dir_to_eye_frame(dir: Vector2) -> int:
	if dir.is_zero_approx():
		return _EYE_NEUTRAL
	# angle(): 0=right, π/2=down, ±π=left, -π/2=up
	var sector := int(round(dir.angle() / (PI / 4.0))) % 8
	if sector < 0:
		sector += 8
	match sector:
		0: return _EYE_RIGHT
		1: return _EYE_DOWN_RIGHT
		2: return _EYE_DOWN
		3: return _EYE_DOWN_LEFT
		4: return _EYE_LEFT
		5: return _EYE_UP_LEFT
		6: return _EYE_UP
		7: return _EYE_UP_RIGHT
	return _EYE_NEUTRAL


func _build_body_frames() -> SpriteFrames:
	var idle_texture := _load_texture(_profile.body_idle_path)
	var run_texture := _load_texture(_profile.body_run_path)
	if idle_texture == null or run_texture == null:
		return null
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	_add_profile_animation_to_frames(frames, idle_texture, HumanoidVisualProfile.ANIM_IDLE)
	_add_profile_animation_to_frames(frames, run_texture, HumanoidVisualProfile.ANIM_RUN)
	return frames


func _load_texture(texture_path: String) -> Texture2D:
	if not ResourceLoader.exists(texture_path):
		return null
	return load(texture_path) as Texture2D


func _refresh_hair_visual() -> void:
	if _hair == null:
		return
	_hair.position = _profile.hair_local_offset
	var hair_path := _profile.get_hair_path(
		String(_appearance.get("hair_style_id", CHARACTER_APPEARANCE.DEFAULT_HAIR_STYLE_ID))
	)
	_hair.texture = _load_texture(hair_path)
	_refresh_head_layer_visibility()


func _refresh_head_layer_visibility() -> void:
	if _hair == null:
		return
	var headgear_equipped := _current_head_item_id != ITEM_PROPERTIES.NONE
	_hair.visible = _hair.texture != null and not headgear_equipped


func _ensure_held_item_sprite() -> void:
	if _held_item_anchor == null or _held_item_sprite != null:
		return
	_held_item_sprite = Sprite2D.new()
	_held_item_sprite.name = "HeldItemSprite"
	_held_item_sprite.centered = false
	_held_item_sprite.offset = Vector2.ZERO
	_held_item_sprite.scale = Vector2.ONE
	_held_item_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_held_item_sprite.visible = false
	_held_item_anchor.add_child(_held_item_sprite)


func _add_profile_animation_to_frames(
	frames: SpriteFrames, texture: Texture2D, anim_name: String
) -> void:
	var layout := _profile.get_animation_layout(anim_name)
	if layout.is_empty():
		return
	var columns := int(layout.get("columns", 1))
	var rows := int(layout.get("rows", 1))
	var speed := float(layout.get("speed", 1.0))
	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, true)
	frames.set_animation_speed(anim_name, speed)
	for row in rows:
		for column in columns:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(
				column * _profile.frame_width,
				row * _profile.frame_height,
				_profile.frame_width,
				_profile.frame_height
			)
			frames.add_frame(anim_name, atlas)


func _update_held_item_anchor() -> void:
	if _held_item_anchor == null:
		return
	var anim_name: String = (
		_current_animation if not _current_animation.is_empty() else String(_body.animation)
	)
	var frame_index: int = _body.frame if _body != null else 0
	_held_item_anchor.position = (
		_profile.get_held_item_offset(anim_name, frame_index) + _held_item_grip_offset
	)
	_update_held_item_rotation(anim_name, frame_index)


func _apply_held_item_id(item_id: int) -> void:
	if _current_held_item_id == item_id:
		return
	_current_held_item_id = item_id
	_refresh_held_item_visual()


func _apply_head_item_id(item_id: int) -> void:
	if _current_head_item_id == item_id:
		return
	_current_head_item_id = item_id
	_refresh_head_layer_visibility()


func _refresh_held_item_visual() -> void:
	_ensure_held_item_sprite()
	if _held_item_sprite == null:
		return
	if not _should_show_held_item_visual():
		_hide_held_item_visual()
		return
	var item_id: int = _current_held_item_id
	if item_id == ITEM_PROPERTIES.NONE:
		_hide_held_item_visual()
		return
	if item_id == _displayed_held_item_id and _held_item_sprite.texture != null:
		_apply_held_item_visual_style(ITEM_PROPERTIES.get_properties(item_id))
		_held_item_sprite.visible = true
		return
	var props: ItemProperties = ITEM_PROPERTIES.get_properties(item_id)
	if props == null:
		_hide_held_item_visual()
		return
	var icon_texture: Texture2D = ITEM_ICON_VISUALS.build_outlined_icon_texture(item_id)
	if icon_texture == null:
		_hide_held_item_visual()
		return
	_displayed_held_item_id = item_id
	_held_item_sprite.texture = icon_texture
	_apply_held_item_visual_style(props)
	_held_item_sprite.visible = true


func _apply_held_item_visual_style(props: ItemProperties) -> void:
	if _held_item_sprite == null:
		return
	var grip_point := Vector2.ZERO
	var texture := _held_item_sprite.texture
	if props != null and texture != null:
		var texture_size := Vector2(float(texture.get_width()), float(texture.get_height()))
		grip_point = props.get_hold_grip_point(texture_size)
	_held_item_sprite.scale = props.get_hold_scale() if props != null else Vector2.ONE
	_held_item_sprite.position = Vector2.ZERO
	_held_item_sprite.offset = -grip_point
	_update_held_item_rotation()


func _hide_held_item_visual() -> void:
	_displayed_held_item_id = ITEM_PROPERTIES.NONE
	if _held_item_sprite == null:
		return
	_held_item_sprite.texture = null
	_held_item_sprite.visible = false
	_held_item_sprite.rotation = 0.0
	_held_item_sprite.position = Vector2.ZERO
	_held_item_sprite.offset = Vector2.ZERO
	_held_item_sprite.scale = Vector2.ONE


func _should_show_held_item_visual() -> bool:
	return true


func _update_held_item_rotation(anim_name: String = "", frame_index: int = -1) -> void:
	if _held_item_sprite == null:
		return
	var resolved_anim: String = anim_name
	if resolved_anim.is_empty():
		resolved_anim = _current_animation if not _current_animation.is_empty() else String(_body.animation)
	var resolved_frame: int = frame_index
	if resolved_frame < 0:
		resolved_frame = _body.frame if _body != null else 0
	var props: ItemProperties = ITEM_PROPERTIES.get_properties(_current_held_item_id)
	var is_tool := props != null and props.is_tool()
	var base_rotation := _profile.get_held_item_base_rotation(is_tool)
	_held_item_sprite.rotation = (
		base_rotation + _profile.get_held_item_rotation_offset(resolved_anim, resolved_frame)
	)
