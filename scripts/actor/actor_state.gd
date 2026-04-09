class_name ActorState
extends RefCounted

const FACING_DOWN: String = "down"
const FACING_SIDE: String = "side"
const FACING_UP: String = "up"

const LOCOMOTION_IDLE: String = "idle"
const LOCOMOTION_MOVE: String = "move"

const ACTION_NONE: String = "none"
const ACTION_USE: String = "use"
const ACTION_ATTACK: String = "attack"
const ACTION_HURT: String = "hurt"
const ACTION_DEAD: String = "dead"


static func normalize_facing(value: String) -> String:
	match value:
		FACING_DOWN, FACING_SIDE, FACING_UP:
			return value
		_:
			return FACING_DOWN


static func normalize_locomotion(value: String) -> String:
	match value:
		LOCOMOTION_IDLE, LOCOMOTION_MOVE:
			return value
		_:
			return LOCOMOTION_IDLE


static func normalize_action(value: String) -> String:
	match value:
		ACTION_NONE, ACTION_USE, ACTION_ATTACK, ACTION_HURT, ACTION_DEAD:
			return value
		_:
			return ACTION_NONE
