class_name HumanoidVisualProfile
extends Resource

const ANIM_IDLE := "idle"
const ANIM_RUN := "run"

@export var body_idle_path: String = ""
@export var body_run_path: String = ""
@export var frame_width: int = 16
@export var frame_height: int = 24
@export var animation_layouts: Dictionary = {}
@export var held_item_offsets: Dictionary = {}
@export var held_item_rotation_offsets_deg: Dictionary = {}
@export var held_item_base_rotation_deg: float = 0.0
@export var held_tool_base_rotation_deg: float = 0.0

# Face layer: chin anchor position per animation frame (offset from sprite center)
@export var face_offsets: Dictionary = {}
# Eye spritesheet: 9 frames (neutral + 8 directions), each eye_frame_width x eye_frame_height
@export var eye_path: String = ""
@export var eye_frame_width: int = 9
@export var eye_frame_height: int = 3
# Eye sprite position relative to chin anchor (negative y = up)
@export var eye_local_offset: Vector2 = Vector2(0.0, -4.0)
# Mouth spritesheet: frames side by side (neutral, happy, frown), each mouth_frame_width x mouth_frame_height
@export var mouth_path: String = ""
@export var mouth_frame_width: int = 7
@export var mouth_frame_height: int = 2
# Mouth sprite position relative to chin anchor
@export var mouth_local_offset: Vector2 = Vector2(0.0, -1.0)


static func create_default_profile() -> HumanoidVisualProfile:
	var profile := HumanoidVisualProfile.new()
	profile.body_idle_path = "res://assets/sprites/characters/humanoid_v1/body_idle_side.png"
	profile.body_run_path = "res://assets/sprites/characters/humanoid_v1/body_run_side.png"
	profile.animation_layouts = {
		ANIM_IDLE: {
			"columns": 4,
			"rows": 3,
			"speed": 4.0,
		},
		ANIM_RUN: {
			"columns": 8,
			"rows": 1,
			"speed": 10.0,
		},
	}
	profile.held_item_base_rotation_deg = 0.0
	profile.held_tool_base_rotation_deg = 0.0
	profile.held_item_offsets = {
		ANIM_IDLE: [
			Vector2(-2, 5),
			Vector2(-2, 5),
			Vector2(-2, 4),
			Vector2(-2, 4),
			Vector2(-2, 4),
			Vector2(-2, 4),
			Vector2(-2, 4),
			Vector2(-2, 5),
			Vector2(-2, 5),
			Vector2(-2, 5),
			Vector2(-2, 5),
			Vector2(-2, 5),
		],
		ANIM_RUN: [
			Vector2(-6, 5),
			Vector2(-5, 5),
			Vector2(-3, 4),
			Vector2(-2, 4),
			Vector2(-1, 5),
			Vector2(-2, 5),
			Vector2(-3, 4),
			Vector2(-4, 4),
		],
	}
	profile.eye_path = "res://assets/sprites/characters/humanoid_v1/faces/eyes_directions.png"
	profile.mouth_path = "res://assets/sprites/characters/humanoid_v1/faces/mouth_expressions.png"
	profile.eye_frame_width = 9
	profile.eye_frame_height = 3
	profile.eye_local_offset = Vector2(0.0, -4.0)
	# Chin anchor offsets from sprite center, measured from marker PNGs
	profile.face_offsets = {
		ANIM_IDLE: [
			Vector2(1, 2),
			Vector2(1, 2),
			Vector2(1, 2),
			Vector2(1, 1),
			Vector2(1, 1),
			Vector2(1, 1),
			Vector2(1, 1),
			Vector2(1, 1),
			Vector2(1, 1),
			Vector2(1, 2),
			Vector2(1, 2),
			Vector2(1, 2),
		],
		ANIM_RUN: [
			Vector2(1, 3),
			Vector2(1, 3),
			Vector2(1, 2),
			Vector2(1, 2),
			Vector2(1, 3),
			Vector2(1, 3),
			Vector2(1, 2),
			Vector2(1, 2),
		],
	}
	profile.held_item_rotation_offsets_deg = {
		ANIM_IDLE: [
			18.0,
			18.0,
			24.0,
			24.0,
			24.0,
			24.0,
			24.0,
			18.0,
			18.0,
			18.0,
			18.0,
			18.0,
		],
		ANIM_RUN: [
			80.0,
			70.0,
			50.0,
			30.0,
			20.0,
			30.0,
			50.0,
			70.0,
		],
	}
	return profile


func get_animation_layout(anim_name: String) -> Dictionary:
	return animation_layouts.get(anim_name, {})


func get_held_item_offset(anim_name: String, frame_index: int) -> Vector2:
	var offsets: Array = held_item_offsets.get(anim_name, [])
	if offsets.is_empty():
		return Vector2.ZERO
	var clamped_index := clampi(frame_index, 0, offsets.size() - 1)
	return offsets[clamped_index] as Vector2


func get_held_item_rotation_offset(anim_name: String, frame_index: int) -> float:
	var offsets: Array = held_item_rotation_offsets_deg.get(anim_name, [])
	if offsets.is_empty():
		return 0.0
	var clamped_index := clampi(frame_index, 0, offsets.size() - 1)
	return deg_to_rad(float(offsets[clamped_index]))


func get_face_offset(anim_name: String, frame_index: int) -> Vector2:
	var offsets: Array = face_offsets.get(anim_name, [])
	if offsets.is_empty():
		return Vector2.ZERO
	var clamped_index := clampi(frame_index, 0, offsets.size() - 1)
	return offsets[clamped_index] as Vector2


func get_held_item_base_rotation(is_tool: bool) -> float:
	return deg_to_rad(held_tool_base_rotation_deg if is_tool else held_item_base_rotation_deg)
