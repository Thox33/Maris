extends Node2D
## Main scene — active once a network connection is established.
## The server initializes the world and waits for clients (including itself
## when not running in dedicated mode). All players join through the same
## _client_ready path — the host is no longer a special case.
##
## Player identity: peer_id drives networking; account_id drives persistence.
## The host maintains peer_to_account_id and peer_to_display_name maps at runtime.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ITEM_ENTITY_SCENE := preload("res://scenes/items/item_entity.tscn")
const MENU_STYLES := preload("res://scripts/ui/menu_styles.gd")
const CHARACTER_APPEARANCE := preload("res://scripts/player/character_appearance.gd")

## Fallback world name when the lobby passes none.
const DEFAULT_WORLD_NAME: String = "default"

## Fixed spawn position in tile-space (converted to pixels on spawn).
const SPAWN_TILE := Vector2i(0, 4)

## Set by the lobby before loading this scene to choose which world to load.
## Falls back to DEFAULT_WORLD_NAME if empty.
static var selected_world_name: String = ""

## Set to true before loading this scene to run a playerless server.
static var dedicated_server: bool = false

@onready var world: Node2D = $World
@onready var _players: Node = $World/DepthSorted/Players
@onready var _player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _item_spawner: MultiplayerSpawner = $ItemSpawner
@onready var inventory_manager: Node = $InventoryManager
@onready var _character_setup_root: Control = $CharacterSetup/Root
@onready var _character_setup_title: Label = $CharacterSetup/Root/PanelContainer/VBoxContainer/TitleLabel
@onready var _character_setup_message: Label = $CharacterSetup/Root/PanelContainer/VBoxContainer/MessageLabel
@onready var _character_name_edit: LineEdit = $CharacterSetup/Root/PanelContainer/VBoxContainer/CharacterNameEdit
@onready var _character_color_option: OptionButton = $CharacterSetup/Root/PanelContainer/VBoxContainer/ColorOptionButton
@onready var _character_color_preview: ColorRect = $CharacterSetup/Root/PanelContainer/VBoxContainer/ColorPreview
@onready var _character_create_button: Button = $CharacterSetup/Root/PanelContainer/VBoxContainer/CreateButton

## Server-only: maps network peer_id → persistent account_id.
var _peer_to_account_id: Dictionary = {}
## Server-only: maps network peer_id → display name.
var _peer_to_display_name: Dictionary = {}
## Server-only: peers that must finish character setup before spawning.
var _pending_character_setup: Dictionary = {}

var _is_app_quitting: bool = false


func _ready() -> void:
	_player_spawner.spawn_function = _create_player
	_item_spawner.spawn_function = _create_item_entity
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.session_ended.connect(_on_session_ended)
	GameEvents.game_leaving.connect(_on_game_leaving)
	GameEvents.block_broken.connect(_on_block_broken)
	GameEvents.structure_broken.connect(_on_structure_broken)
	get_tree().auto_accept_quit = false
	_character_setup_root.theme = MENU_STYLES.create_theme()
	_character_setup_root.visible = false
	_populate_character_color_options()
	_character_create_button.pressed.connect(_on_character_create_pressed)
	_character_name_edit.text_submitted.connect(_on_character_name_submitted)
	_character_color_option.item_selected.connect(_on_character_color_selected)

	# Give InventoryManager references it needs.
	inventory_manager.item_spawner = _item_spawner
	inventory_manager.chunk_manager = world.chunk_manager
	inventory_manager.structure_manager = world.structure_manager

	if multiplayer.is_server():
		var world_name := selected_world_name if not selected_world_name.is_empty() else DEFAULT_WORLD_NAME
		SaveManager.set_world(world_name)
		SaveManager.auto_save_requested.connect(_on_auto_save)

		var seed_value: int = _load_or_create_seed()
		print("[Main] Initializing world '%s' with seed %d" % [world_name, seed_value])
		world.initialize(seed_value)
		world.structure_manager.load_from_save()

		if dedicated_server:
			# Dedicated server: load spawn area but don't join as a player.
			world.chunk_manager.load_chunks_around(_get_spawn_position())
			print("[Main] Running as dedicated server (no local player)")
		else:
			# Host-as-player: join through the same path as any client.
			_server_handle_join(
				multiplayer.get_unique_id(), ClientProfile.get_account_id(), ClientProfile.display_name
			)
	else:
		_client_ready.rpc_id(1, ClientProfile.get_account_id(), ClientProfile.display_name)


# --- Player spawning ---


## Creates a player node from spawn data — called on all peers by the spawner.
func _create_player(data: Dictionary) -> Node:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(data["peer_id"])
	player.position = Vector2(data["x"], data["y"])
	player.set_multiplayer_authority(data["peer_id"])
	player.add_to_group("players")
	player.apply_character_data(
		String(data.get("character_name", "")),
		String(data.get("body_color_preset", CHARACTER_APPEARANCE.DEFAULT_PRESET_ID))
	)
	return player


## Server-only: full join sequence for a new player.
func _server_handle_join(peer_id: int, p_account_id: String, p_display_name: String) -> void:
	if not multiplayer.is_server():
		return

	var safe_name := _sanitize_display_name(p_display_name, peer_id)
	_peer_to_account_id[peer_id] = p_account_id
	_peer_to_display_name[peer_id] = safe_name

	var player_record := SaveManager.load_player(p_account_id)
	if not SaveManager.has_character(p_account_id):
		_pending_character_setup[peer_id] = {
			"account_id": p_account_id,
			"display_name": safe_name,
		}
		_show_character_setup(peer_id, safe_name)
		return

	_complete_join(peer_id, player_record)


func _complete_join(peer_id: int, player_record: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	var safe_name := _peer_to_display_name.get(peer_id, "") as String
	NetworkManager.set_player_display_name(peer_id, safe_name)
	var progress := SaveManager.get_progress_record(player_record)
	var character := SaveManager.get_character_record(player_record)
	var character_name := String(character.get("name", ""))
	var appearance := character.get("appearance", {}) as Dictionary
	var body_color_preset := CHARACTER_APPEARANCE.normalize_preset_id(
		String(appearance.get("body_color_preset", CHARACTER_APPEARANCE.DEFAULT_PRESET_ID))
	)
	NetworkManager.set_player_character_name(peer_id, character_name)

	# Determine spawn position — use saved position if available.
	var pos := _get_spawn_position()
	if progress.has("x") and progress.has("y"):
		pos = Vector2(progress["x"], progress["y"])

	# Ensure terrain exists before the player lands.
	world.chunk_manager.load_chunks_around(pos)
	world.structure_manager.sync_full_state_to_peer(peer_id)

	# Spawn the player (MultiplayerSpawner replicates to all peers).
	var player_id := str(peer_id)
	if not _players.has_node(player_id):
		_player_spawner.spawn({
			"peer_id": peer_id,
			"x": pos.x,
			"y": pos.y,
			"character_name": character_name,
			"body_color_preset": body_color_preset,
		})

	# Create inventory and restore saved items if available.
	inventory_manager.create_inventory(peer_id)
	if progress.has("inventory"):
		_restore_inventory(peer_id, progress["inventory"])

	_pending_character_setup.erase(peer_id)
	_broadcast_player_identities()
	GameEvents.player_joined.emit(peer_id)


func _on_player_disconnected(peer_id: int) -> void:
	var visible_name := NetworkManager.get_player_visible_name(peer_id)
	GameEvents.player_left.emit(peer_id, visible_name)
	# Save player state before cleanup.
	_save_player(peer_id)
	# Remove identity mappings after save (save needs them).
	_peer_to_account_id.erase(peer_id)
	_peer_to_display_name.erase(peer_id)
	_pending_character_setup.erase(peer_id)
	_broadcast_player_identities()
	# Clean up inventory.
	inventory_manager.remove_inventory(peer_id)
	# queue_free on a spawner-tracked node automatically despawns on all peers.
	var node := _players.get_node_or_null(str(peer_id))
	if node:
		node.queue_free()


# --- Item entity spawning ---


## Creates an item entity from spawn data — called on all peers by the spawner.
func _create_item_entity(data: Dictionary) -> Node:
	var entity := ITEM_ENTITY_SCENE.instantiate()
	entity.initialize(data["item_id"], data["count"])
	entity.position = Vector2(data["x"], data["y"])
	return entity


## Handles item drops when a block is broken. Listens to GameEvents.block_broken.
func _on_block_broken(coord: Vector2i, tile_id: int) -> void:
	if not multiplayer.is_server():
		return
	var props := TileProperties.get_properties(tile_id)
	if props == null:
		return
	var drop_id: int = props.drop_tile_id if props else tile_id
	var item_id: int = ItemProperties.from_tile(drop_id)
	if item_id == ItemProperties.NONE:
		return
	var tile_center := Vector2(
		coord.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
		coord.y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
	)
	spawn_item_drop(item_id, 1, tile_center)


func _on_structure_broken(structure_id: String, world_pos: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var item_id := ItemProperties.from_structure(structure_id)
	if item_id == ItemProperties.NONE:
		return
	spawn_item_drop(item_id, 1, world_pos)


## Server-only: spawns an item drop in the world at the given position.
func spawn_item_drop(item_id: int, count: int, world_pos: Vector2) -> void:
	if not multiplayer.is_server():
		return
	_item_spawner.spawn({
		"item_id": item_id,
		"count": count,
		"x": world_pos.x,
		"y": world_pos.y,
	})


# --- Client join RPC ---


## Client calls this when the main scene is loaded and ready.
## Carries the persistent account_id and chosen display_name.
@rpc("any_peer", "reliable")
func _client_ready(p_account_id: String, p_display_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()

	# Reject joins with a malformed account_id to prevent save-path manipulation.
	if not ClientProfile.is_valid_account_id(p_account_id):
		_reject_join(sender_id, "Invalid client identity.")
		return

	# Reject duplicate account_ids — two sessions sharing the same identity would
	# overwrite each other's save on disconnect (last writer wins).
	if p_account_id in _peer_to_account_id.values():
		_reject_join(sender_id, "This player identity is already connected.")
		return

	# Sanitize display name: strip whitespace, cap length, provide fallback.
	var safe_name := _sanitize_display_name(p_display_name, sender_id)

	_receive_world_seed.rpc_id(sender_id, world.world_seed)
	_server_handle_join(sender_id, p_account_id, safe_name)


func _reject_join(peer_id: int, reason: String) -> void:
	print("[Main] Rejecting join for peer %d: %s" % [peer_id, reason])
	push_error("[Main] Rejected join from peer %d: %s" % [peer_id, reason])
	_join_rejected.rpc_id(peer_id, reason)


@rpc("authority", "reliable")
func _join_rejected(reason: String) -> void:
	if multiplayer.is_server():
		return
	print("[Main] Join rejected by host: %s" % reason)
	push_warning("[Main] Join rejected: %s" % reason)
	NetworkManager.leave_game("connection_failed")


@rpc("authority", "reliable")
func _open_character_setup(default_name: String) -> void:
	_character_setup_title.text = "Create Character"
	_character_setup_message.text = "This world needs a character before you can join."
	_character_name_edit.text = default_name
	_character_color_option.select(0)
	_refresh_character_color_preview(0)
	_character_setup_root.visible = true
	_character_name_edit.grab_focus()


@rpc("authority", "reliable")
func _close_character_setup() -> void:
	_character_setup_root.visible = false


@rpc("any_peer", "reliable")
func _submit_character_setup(character_name: String, color_index: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		sender_id = multiplayer.get_unique_id()
	var pending := _pending_character_setup.get(sender_id, {}) as Dictionary
	if pending.is_empty():
		return

	var safe_character_name := _sanitize_character_name(
		character_name, String(pending.get("display_name", ""))
	)
	var preset_id := CHARACTER_APPEARANCE.get_preset_id(color_index)
	var account_id := String(pending.get("account_id", ""))
	if account_id.is_empty():
		_reject_join(sender_id, "Character setup failed.")
		return

	var player_record := SaveManager.load_player(account_id)
	player_record["account"] = {
		"account_id": account_id,
		"display_name": String(pending.get("display_name", "")),
	}
	player_record["character"] = {
		"name": safe_character_name,
		"appearance": {
			"body_color_preset": preset_id,
		},
		"created_at": Time.get_datetime_string_from_system(true),
	}
	SaveManager.save_player(account_id, player_record)
	_hide_character_setup(sender_id)
	_complete_join(sender_id, player_record)


## Client receives the world seed and initializes terrain.
@rpc("authority", "reliable")
func _receive_world_seed(seed_value: int) -> void:
	world.initialize(seed_value)
	world.chunk_manager.load_chunks_around(_get_spawn_position())


func _get_spawn_position() -> Vector2:
	return Vector2(
		SPAWN_TILE.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
		SPAWN_TILE.y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
	)


func _sanitize_character_name(character_name: String, fallback_name: String) -> String:
	var safe_name := character_name.strip_edges().left(24)
	if safe_name.is_empty():
		safe_name = fallback_name.strip_edges().left(24)
	if safe_name.is_empty():
		safe_name = "Diver"
	return safe_name


func _populate_character_color_options() -> void:
	_character_color_option.clear()
	for index in range(CHARACTER_APPEARANCE.get_preset_count()):
		_character_color_option.add_item(CHARACTER_APPEARANCE.get_preset_label(index))


func _refresh_character_color_preview(index: int) -> void:
	var preset_id := CHARACTER_APPEARANCE.get_preset_id(index)
	_character_color_preview.color = CHARACTER_APPEARANCE.get_color_for_preset(preset_id)


func _show_character_setup(peer_id: int, default_name: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		_open_character_setup(default_name)
	else:
		_open_character_setup.rpc_id(peer_id, default_name)


func _hide_character_setup(peer_id: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		_close_character_setup()
	else:
		_close_character_setup.rpc_id(peer_id)


# --- Persistence helpers ---


## Returns the saved seed or generates a new one for a fresh world.
func _load_or_create_seed() -> int:
	var meta := SaveManager.load_world_meta()
	if meta.has("seed"):
		print("[Main] Loaded existing world '%s'" % SaveManager.get_world_name())
		return int(meta["seed"])
	var new_seed: int = randi()
	SaveManager.save_world_meta(new_seed)
	print("[Main] Created new world '%s'" % SaveManager.get_world_name())
	return new_seed


## Serializes a player's current state and writes it to disk.
## Uses account_id (not peer_id) as the save key.
func _save_player(peer_id: int) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	var account_id := _peer_to_account_id.get(peer_id, "") as String
	if account_id.is_empty():
		push_error("[Main] No account_id for peer %d — skipping save" % peer_id)
		return

	var data: Dictionary = {}

	# Position from the player node.
	var player_node := _players.get_node_or_null(str(peer_id))
	if player_node:
		data["progress"] = {
			"x": player_node.global_position.x,
			"y": player_node.global_position.y,
		}
	else:
		data["progress"] = {}

	data["account"] = {
		"account_id": account_id,
		"display_name": _peer_to_display_name.get(peer_id, ""),
	}

	var existing_record := SaveManager.load_player(account_id)
	var existing_character := SaveManager.get_character_record(existing_record)
	if not existing_character.is_empty():
		data["character"] = existing_character

	# Inventory.
	var inv: Inventory = inventory_manager.get_inventory(peer_id)
	if inv:
		data["progress"]["inventory"] = inv.serialize()

	SaveManager.save_player(account_id, data)
	print("[Main] Saved player %s (peer %d)" % [account_id, peer_id])


## Restores inventory from saved data into the already-created inventory,
## then re-syncs to the owning client.
func _restore_inventory(peer_id: int, saved_slots: Array) -> void:
	var inv: Inventory = inventory_manager.get_inventory(peer_id)
	if inv == null:
		return
	for i in range(mini(saved_slots.size(), inv.size)):
		var slot: Dictionary = saved_slots[i]
		inv.set_slot(i, slot.get("item_id", ItemProperties.NONE), slot.get("count", 0))
	inventory_manager.sync_inventory(peer_id)


func _broadcast_player_identities() -> void:
	if not multiplayer.is_server():
		return
	NetworkManager._sync_player_identities.rpc(_build_player_identity_snapshot())


func _build_player_identity_snapshot() -> Array:
	var snapshot: Array = []
	for peer_id: int in _peer_to_display_name.keys():
		var account_id := _peer_to_account_id.get(peer_id, "") as String
		var record := SaveManager.load_player(account_id)
		var character := SaveManager.get_character_record(record)
		snapshot.append({
			"peer_id": peer_id,
			"display_name": _peer_to_display_name[peer_id],
			"character_name": String(character.get("name", "")),
		})
	return snapshot


func _sanitize_display_name(display_name: String, peer_id: int) -> String:
	var safe_name := display_name.strip_edges().left(32)
	if safe_name.is_empty():
		safe_name = "Player_%d" % peer_id
	return safe_name


## Saves all world state: chunks, players, world meta.
func _save_world() -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	SaveManager.save_world_meta(world.world_seed)
	SaveManager.save_all_chunks(world.chunk_manager.loaded_chunks)
	world.structure_manager.save_to_disk()
	# Save all connected players.
	for player in _players.get_children():
		var peer_id: int = player.name.to_int()
		if peer_id > 0:
			_save_player(peer_id)
	print("[Main] World saved")


func _on_auto_save() -> void:
	_save_world()


## Fired by GameEvents.game_leaving BEFORE the peer closes.
## Covers all leave paths: user_left, connection_lost, app_quit.
func _on_game_leaving() -> void:
	_save_world()


func _on_session_ended(reason: String) -> void:
	if reason == "app_quit":
		get_tree().quit()


func _exit_tree() -> void:
	get_tree().auto_accept_quit = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _is_app_quitting:
			return
		_is_app_quitting = true
		NetworkManager.leave_game("app_quit")


func _on_character_create_pressed() -> void:
	if multiplayer.is_server():
		_submit_character_setup(_character_name_edit.text, _character_color_option.selected)
	else:
		_submit_character_setup.rpc_id(
			1,
			_character_name_edit.text,
			_character_color_option.selected
		)


func _on_character_name_submitted(_text: String) -> void:
	_on_character_create_pressed()


func _on_character_color_selected(index: int) -> void:
	_refresh_character_color_preview(index)
