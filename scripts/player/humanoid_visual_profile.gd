class_name HumanoidVisualProfile
extends RefCounted

const ANIM_IDLE := "idle"
const ANIM_RUN := "run"

var body_idle_path: String = ""
var body_run_path: String = ""
var frame_width: int = 16
var frame_height: int = 24
var animation_layouts: Dictionary = {}
var held_item_offsets: Dictionary = {}


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
	profile.held_item_offsets = {
		ANIM_IDLE: [
			Vector2(-1, 5),
			Vector2(-1, 5),
			Vector2(-1, 4),
			Vector2(-1, 4),
			Vector2(-1, 4),
			Vector2(-1, 4),
			Vector2(-1, 4),
			Vector2(-1, 5),
			Vector2(-1, 5),
			Vector2(-1, 5),
			Vector2(-1, 5),
			Vector2(-1, 5),
		],
		ANIM_RUN: [
			Vector2(-5, 5),
			Vector2(-3, 5),
			Vector2(-2, 4),
			Vector2(-1, 4),
			Vector2(0, 5),
			Vector2(-1, 5),
			Vector2(-2, 4),
			Vector2(-3, 4),
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
