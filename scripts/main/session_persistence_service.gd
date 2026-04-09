extends Node

## Coordinates session-level saving without owning join or spawn logic.

var world: Node2D
var players_node: Node
var inventory_manager: Node
var identity_service: Node

var _is_initialized: bool = false


func setup(
	p_world: Node2D,
	p_players_node: Node,
	p_inventory_manager: Node,
	p_identity_service: Node
) -> void:
	world = p_world
	players_node = p_players_node
	inventory_manager = p_inventory_manager
	identity_service = p_identity_service

	if _is_initialized:
		return

	GameEvents.game_leaving.connect(_on_game_leaving)
	_is_initialized = true


func activate_world(world_name: String) -> void:
	if not multiplayer.is_server():
		return
	SaveManager.set_world(world_name)
	if not SaveManager.auto_save_requested.is_connected(_on_auto_save):
		SaveManager.auto_save_requested.connect(_on_auto_save)


func load_or_create_seed() -> int:
	var meta := SaveManager.load_world_meta()
	if meta.has("seed"):
		print("[SessionPersistenceService] Loaded existing world '%s'" % SaveManager.get_world_name())
		return int(meta["seed"])

	var new_seed: int = randi()
	SaveManager.save_world_meta(new_seed)
	print("[SessionPersistenceService] Created new world '%s'" % SaveManager.get_world_name())
	return new_seed


func save_player(peer_id: int) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return

	var account_id := String(identity_service.get_account_id(peer_id))
	if account_id.is_empty():
		push_error("[SessionPersistenceService] No account_id for peer %d - skipping save" % peer_id)
		return

	var data: Dictionary = {}
	var player_node := players_node.get_node_or_null(str(peer_id))
	if player_node != null:
		data["progress"] = {
			"x": player_node.global_position.x,
			"y": player_node.global_position.y,
		}
	else:
		data["progress"] = {}

	data["account"] = {
		"account_id": account_id,
		"display_name": identity_service.get_display_name(peer_id),
	}

	var existing_record := SaveManager.load_player(account_id)
	var existing_character := SaveManager.get_character_record(existing_record)
	if not existing_character.is_empty():
		data["character"] = existing_character

	var serialized_inventory: Array = inventory_manager.get_persistent_inventory_snapshot(peer_id)
	if not serialized_inventory.is_empty():
		data["progress"]["inventory"] = serialized_inventory

	SaveManager.save_player(account_id, data)
	print("[SessionPersistenceService] Saved player %s (peer %d)" % [account_id, peer_id])


func save_world() -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return

	SaveManager.save_world_meta(world.world_seed)
	SaveManager.save_all_chunks(world.chunk_manager.loaded_chunks)
	world.structure_manager.save_to_disk()

	for player in players_node.get_children():
		var peer_id: int = player.name.to_int()
		if peer_id > 0:
			save_player(peer_id)

	print("[SessionPersistenceService] World saved")


func _on_auto_save() -> void:
	save_world()


func _on_game_leaving() -> void:
	save_world()
