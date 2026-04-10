class_name HumanoidActor
extends Actor
## Intermediate base class for all humanoid actors (players, humanoid NPCs).
## Adds appearance, held-item state, and HumanoidVisual wiring on top of Actor.
## Non-humanoid creatures (fish, jellyfish) extend Actor directly instead.

const CHARACTER_APPEARANCE := preload("res://scripts/actor/character_appearance.gd")
const ITEM_PROPERTIES := preload("res://scripts/items/item_properties.gd")

var _humanoid_visual: HumanoidVisual
var _appearance: Dictionary = CHARACTER_APPEARANCE.create_default_appearance()
var _held_item_id: int = ITEM_PROPERTIES.NONE
var _character_name: String = ""


func _ready() -> void:
	_humanoid_visual = get_node_or_null("VisualRoot/HumanoidVisual") as HumanoidVisual
	if _humanoid_visual != null:
		_humanoid_visual.setup(self)


func apply_appearance(appearance: Dictionary) -> void:
	_appearance = CHARACTER_APPEARANCE.normalize_appearance(appearance)
	if _humanoid_visual != null:
		_humanoid_visual.apply_appearance(_appearance)
	actor_state_changed.emit()


func get_actor_appearance() -> Dictionary:
	return _appearance.duplicate(true)


## Override in subclasses to provide a display name from a different source.
func get_actor_display_name() -> String:
	return _character_name


func get_actor_state() -> Dictionary:
	var state := super.get_actor_state()
	state["display_name"] = get_actor_display_name()
	state["held_item_id"] = _held_item_id
	state["appearance"] = _appearance
	return state
