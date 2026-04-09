extends CharacterBody2D
## Player controller with swim physics.
## Only the owning peer processes input. Remote peers are rendered from a
## short snapshot buffer for smoother movement.

signal actor_state_changed

const ACTOR_STATE := preload("res://scripts/actor/actor_state.gd")
const CHARACTER_APPEARANCE := preload("res://scripts/player/character_appearance.gd")
const ITEM_PROPERTIES := preload("res://scripts/items/item_properties.gd")
const ACTOR_MOVE_DEADZONE: float = 4.0

@export var swim_speed: float = GameConstants.SWIM_SPEED
@export var swim_acceleration: float = GameConstants.SWIM_ACCELERATION
@export var swim_friction: float = GameConstants.SWIM_FRICTION

var _chunk_manager: Node
var _sync_timer: float = 0.0
var _state_buffer: Array[Dictionary] = []
@onready var _overhead_source: OverheadSource = $OverheadSource
@onready var _humanoid_visual: HumanoidVisual = $VisualRoot/HumanoidVisual
@onready var _block_interaction: Node = $BlockInteraction

var _character_name: String = ""
var _appearance: Dictionary = CHARACTER_APPEARANCE.create_default_appearance()
var _facing: String = ACTOR_STATE.FACING_DOWN
var _locomotion_state: String = ACTOR_STATE.LOCOMOTION_IDLE
var _active_action: String = ACTOR_STATE.ACTION_NONE
var _side_view_mirrored: bool = false
var _held_item_id: int = ITEM_PROPERTIES.NONE
var _inventory_manager: Node


func setup_session(
	world: Node2D, inventory_manager: Node, items_node: Node = null, use_authority_service: Node = null
) -> void:
	_inventory_manager = inventory_manager
	if world != null:
		_chunk_manager = world.get_node_or_null("ChunkManager")
		var block_interaction := get_node_or_null("BlockInteraction")
		if block_interaction != null and block_interaction.has_method("setup_session"):
			block_interaction.setup_session(
				world.get_node_or_null("TerrainLayer"),
				world.get_node_or_null("ChunkManager"),
				world.get_node_or_null("StructureManager"),
				inventory_manager,
				use_authority_service
			)
	var hotbar_ui := get_node_or_null("HotbarUI")
	var block_interaction_node := get_node_or_null("BlockInteraction")
	if hotbar_ui != null and hotbar_ui.has_method("setup_session"):
		hotbar_ui.setup_session(block_interaction_node, inventory_manager)
	if _humanoid_visual != null and _humanoid_visual.has_method("set_inventory_manager"):
		_humanoid_visual.set_inventory_manager(inventory_manager)
	var debug_overlay := get_node_or_null("DebugOverlay")
	if debug_overlay != null and debug_overlay.has_method("setup_session"):
		debug_overlay.setup_session(
			world,
			items_node,
			world.get_node_or_null("DepthSorted/Players") if world != null else null,
			world.get_node_or_null("ChunkDebugCanvas/ChunkDebugOverlay") if world != null else null
		)


func _ready() -> void:
	$Camera2D.enabled = is_multiplayer_authority()

	if not is_multiplayer_authority():
		_push_remote_state(position, Vector2.ZERO)

	NetworkManager.player_identity_updated.connect(_on_player_identity_updated)
	if _humanoid_visual != null:
		_humanoid_visual.apply_appearance(_appearance)
	_refresh_equipped_item_state()
	_update_actor_motion_state(velocity)
	_refresh_overhead()


func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if is_multiplayer_authority():
		_refresh_equipped_item_state()
	if not is_multiplayer_authority():
		_update_remote_motion(delta)


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not is_multiplayer_authority():
		return

	if ChatManager.is_chat_open:
		velocity = velocity.move_toward(Vector2.ZERO, swim_friction * delta)
		move_and_slide()
		_update_actor_motion_state(velocity)
		return

	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("swim_left", "swim_right")
	input_dir.y = Input.get_axis("swim_up", "swim_down")

	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	var speed_factor: float = _get_tile_speed_factor()
	var effective_speed: float = swim_speed * speed_factor

	if input_dir != Vector2.ZERO:
		velocity = velocity.move_toward(input_dir * effective_speed, swim_acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, swim_friction * delta)

	move_and_slide()
	_update_actor_motion_state(velocity)

	_sync_timer += delta
	if _sync_timer >= GameConstants.POSITION_SYNC_INTERVAL:
		_sync_timer = 0.0
		_sync_state.rpc(position, velocity, _held_item_id)


func _update_remote_motion(delta: float) -> void:
	var now := Time.get_ticks_usec() * 0.000001
	var render_time := now - GameConstants.REMOTE_PLAYER_INTERPOLATION_BACK_TIME
	var target_position := position
	var target_velocity := velocity

	while _state_buffer.size() >= 2 and render_time > _state_buffer[1]["time"]:
		_state_buffer.remove_at(0)

	if _state_buffer.size() >= 2:
		var from_state: Dictionary = _state_buffer[0]
		var to_state: Dictionary = _state_buffer[1]
		var span: float = maxf(to_state["time"] - from_state["time"], 0.0001)
		var alpha: float = clampf((render_time - from_state["time"]) / span, 0.0, 1.0)
		target_position = (from_state["position"] as Vector2).lerp(to_state["position"], alpha)
		target_velocity = (from_state["velocity"] as Vector2).lerp(to_state["velocity"], alpha)
	elif _state_buffer.size() == 1:
		var latest: Dictionary = _state_buffer[0]
		var age: float = minf(
			now - latest["time"],
			GameConstants.REMOTE_PLAYER_MAX_EXTRAPOLATION
		)
		target_velocity = latest["velocity"]
		target_position = latest["position"] + target_velocity * age

	position = position.lerp(
		target_position,
		minf(GameConstants.REMOTE_PLAYER_SMOOTHING * delta, 1.0)
	)
	velocity = target_velocity
	_update_actor_motion_state(velocity)


func _push_remote_state(pos: Vector2, vel: Vector2) -> void:
	_state_buffer.append({
		"position": pos,
		"velocity": vel,
		"time": Time.get_ticks_usec() * 0.000001,
	})
	while _state_buffer.size() > 4:
		_state_buffer.remove_at(0)


## Returns the swim speed factor for the tile at the player's center position.
## 1.0 = open water (full speed), < 1.0 = slowed (e.g. coral).
func _get_tile_speed_factor() -> float:
	if _chunk_manager == null:
		return 1.0

	var tile_coord := Vector2i(
		floori(global_position.x / GameConstants.TILE_SIZE),
		floori(global_position.y / GameConstants.TILE_SIZE),
	)
	var tile_id: int = _chunk_manager.get_tile_at(tile_coord)
	if tile_id == TileProperties.EMPTY:
		return 1.0

	var props: TileProperties = TileProperties.get_properties(tile_id)
	if props and not props.solid:
		return props.swim_speed_factor

	return 1.0


@rpc("authority", "unreliable")
func _sync_state(pos: Vector2, vel: Vector2, held_item_id: int) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not is_multiplayer_authority():
		_apply_remote_held_item_state(held_item_id)
		_push_remote_state(pos, vel)


func apply_server_teleport(pos: Vector2) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_apply_server_teleport(pos)
		var authority_id := get_multiplayer_authority()
		if authority_id != multiplayer.get_unique_id():
			_apply_server_teleport.rpc_id(authority_id, pos)
	else:
		_apply_server_teleport(pos)


@rpc("any_peer", "reliable", "call_local")
func _apply_server_teleport(pos: Vector2) -> void:
	if not multiplayer.is_server():
		var sender_id := multiplayer.get_remote_sender_id()
		if sender_id != 1:
			return
	position = pos
	global_position = pos
	velocity = Vector2.ZERO
	_sync_timer = 0.0
	_state_buffer.clear()
	_update_actor_motion_state(Vector2.ZERO)
	if not is_multiplayer_authority():
		_push_remote_state(pos, Vector2.ZERO)


func apply_character_data(character_name: String, appearance: Dictionary) -> void:
	_character_name = character_name.strip_edges()
	_appearance = CHARACTER_APPEARANCE.normalize_appearance(appearance)
	if _humanoid_visual != null:
		_humanoid_visual.apply_appearance(_appearance)
	actor_state_changed.emit()
	_refresh_overhead()


func _on_player_identity_updated(peer_id: int, _display_name: String, character_name: String) -> void:
	if peer_id != get_multiplayer_authority():
		return
	_character_name = character_name.strip_edges()
	_refresh_overhead()


func _refresh_overhead() -> void:
	if _overhead_source == null:
		return
	_overhead_source.set_display_name(get_actor_display_name())
	_overhead_source.set_overhead_visible(not is_multiplayer_authority())


func get_actor_state() -> Dictionary:
	return {
		"velocity": velocity,
		"display_name": get_actor_display_name(),
		"facing": _facing,
		"locomotion_state": _locomotion_state,
		"active_action": _active_action,
		"side_view_mirrored": _side_view_mirrored,
		"held_item_id": _held_item_id,
		"appearance": _appearance,
	}


func get_actor_display_name() -> String:
	return (
		_character_name
		if not _character_name.is_empty()
		else NetworkManager.get_player_visible_name(get_multiplayer_authority())
	)


func get_actor_facing() -> String:
	return _facing


func get_actor_locomotion_state() -> String:
	return _locomotion_state


func get_actor_active_action() -> String:
	return _active_action


func get_actor_appearance() -> Dictionary:
	return _appearance.duplicate(true)


func is_actor_side_view_mirrored() -> bool:
	return _side_view_mirrored


func _refresh_equipped_item_state() -> void:
	if not is_multiplayer_authority():
		return
	var next_item_id := _resolve_selected_hotbar_item_id()
	if next_item_id == _held_item_id:
		return
	_held_item_id = next_item_id
	actor_state_changed.emit()
	if multiplayer.multiplayer_peer != null:
		_sync_held_item_state.rpc(_held_item_id)


func _resolve_selected_hotbar_item_id() -> int:
	if _inventory_manager == null or _inventory_manager.local_inventory == null:
		return ITEM_PROPERTIES.NONE
	if _block_interaction == null:
		return ITEM_PROPERTIES.NONE
	var slot_index: int = int(_block_interaction.selected_hotbar_slot)
	if slot_index < 0 or slot_index >= _inventory_manager.local_inventory.size:
		return ITEM_PROPERTIES.NONE
	var slot: Dictionary = _inventory_manager.local_inventory.get_slot(slot_index)
	return int(slot.get("item_id", ITEM_PROPERTIES.NONE))


func _apply_remote_held_item_state(item_id: int) -> void:
	if _held_item_id == item_id:
		return
	_held_item_id = item_id
	actor_state_changed.emit()


@rpc("authority", "reliable", "call_local")
func _sync_held_item_state(item_id: int) -> void:
	if is_multiplayer_authority():
		return
	_apply_remote_held_item_state(item_id)


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
