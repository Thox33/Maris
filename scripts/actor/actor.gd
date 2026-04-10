class_name Actor
extends CharacterBody2D
## Base class for all actor types (players, NPCs, creatures).
## Manages the locomotion state machine and exposes a uniform actor state API
## so visual components (HumanoidVisual) can attach without coupling to Player.

signal actor_state_changed

const ACTOR_STATE := preload("res://scripts/actor/actor_state.gd")
const ACTOR_MOVE_DEADZONE: float = 4.0

var _facing: String = ACTOR_STATE.FACING_DOWN
var _locomotion_state: String = ACTOR_STATE.LOCOMOTION_IDLE
var _active_action: String = ACTOR_STATE.ACTION_NONE
var _side_view_mirrored: bool = false


func get_actor_state() -> Dictionary:
	return {
		"facing": _facing,
		"locomotion_state": _locomotion_state,
		"active_action": _active_action,
		"side_view_mirrored": _side_view_mirrored,
	}


func get_actor_facing() -> String:
	return _facing


func get_actor_locomotion_state() -> String:
	return _locomotion_state


func get_actor_active_action() -> String:
	return _active_action


func is_actor_side_view_mirrored() -> bool:
	return _side_view_mirrored


func _update_actor_motion_state(current_velocity: Vector2) -> void:
	var next_locomotion_state := ACTOR_STATE.LOCOMOTION_IDLE
	var next_facing := _facing
	var next_side_view_mirrored := _side_view_mirrored
	var speed := current_velocity.length()

	if speed >= ACTOR_MOVE_DEADZONE:
		next_locomotion_state = ACTOR_STATE.LOCOMOTION_MOVE
		if absf(current_velocity.y) > absf(current_velocity.x):
			next_facing = (
				ACTOR_STATE.FACING_UP
				if current_velocity.y < 0.0
				else ACTOR_STATE.FACING_DOWN
			)
		else:
			next_facing = ACTOR_STATE.FACING_SIDE
			if not is_zero_approx(current_velocity.x):
				next_side_view_mirrored = current_velocity.x < 0.0

	var changed := (
		next_locomotion_state != _locomotion_state
		or next_facing != _facing
		or next_side_view_mirrored != _side_view_mirrored
	)
	_locomotion_state = next_locomotion_state
	_facing = next_facing
	_side_view_mirrored = next_side_view_mirrored

	if changed:
		actor_state_changed.emit()
