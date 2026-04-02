extends Node
## Host-authoritative manager for all player inventories.
## Lives as a child of Main — server infrastructure, not player logic.
## Handles inventory RPCs: full sync on join, delta sync on changes.

## Host-only: authoritative inventory for each connected peer.
var _inventories: Dictionary = {}  # { peer_id: Inventory }

## Client-only: local copy of this client's inventory (for UI reads).
var local_inventory: Inventory

## Emitted on the client that owns this inventory when a slot changes.
signal local_slot_changed(index: int)

## Reference to the item spawner (set by main.gd).
var item_spawner: MultiplayerSpawner

## Reference to the chunk manager (set by main.gd).
var chunk_manager: Node


# --- Lifecycle (called by main.gd) ---


## Host creates an inventory for a newly connected player.
func create_inventory(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var inv := Inventory.new(GameConstants.INVENTORY_SIZE)
	_inventories[peer_id] = inv
	_sync_full_inventory_to_peer(peer_id, inv)


## Host cleans up when a player disconnects. Returns the inventory for
## potential persistence (save to disk) before it is erased.
func remove_inventory(peer_id: int) -> Inventory:
	if not multiplayer.is_server():
		return null
	var inv: Inventory = _inventories.get(peer_id)
	_inventories.erase(peer_id)
	return inv


## Returns the host-authoritative inventory for a peer, or null.
func get_inventory(peer_id: int) -> Inventory:
	return _inventories.get(peer_id)


# --- Host-side item operations ---


## Adds items to a player's inventory. Returns the remainder that did not fit.
## Automatically syncs changed slots to the owning client.
func server_add_item(peer_id: int, item_id: int, count: int) -> int:
	if not multiplayer.is_server():
		return count
	var inv: Inventory = _inventories.get(peer_id)
	if inv == null:
		return count

	# Track which slots change so we only sync those.
	var changed_slots: Array[int] = []
	var _on_change := func(index: int) -> void:
		if not (index in changed_slots):
			changed_slots.append(index)
	inv.slot_changed.connect(_on_change)

	var remainder: int = inv.add_item(item_id, count)

	inv.slot_changed.disconnect(_on_change)

	# Delta-sync each changed slot to the client.
	for slot_index in changed_slots:
		var slot: Dictionary = inv.get_slot(slot_index)
		_sync_slot_to_peer(peer_id, slot_index, slot)

	return remainder


## Removes items from a player's inventory. Returns true if successful.
## Automatically syncs changed slots to the owning client.
func server_remove_item(peer_id: int, item_id: int, count: int) -> bool:
	if not multiplayer.is_server():
		return false
	var inv: Inventory = _inventories.get(peer_id)
	if inv == null:
		return false

	var changed_slots: Array[int] = []
	var _on_change := func(index: int) -> void:
		if not (index in changed_slots):
			changed_slots.append(index)
	inv.slot_changed.connect(_on_change)

	var success: bool = inv.remove_item(item_id, count)

	inv.slot_changed.disconnect(_on_change)

	if success:
		for slot_index in changed_slots:
			var slot: Dictionary = inv.get_slot(slot_index)
			_sync_slot_to_peer(peer_id, slot_index, slot)

	return success


## Removes one item from a specific slot. Returns the item_id removed, or NONE.
## Used for block placing (player picks a specific hotbar slot).
func server_remove_from_slot(peer_id: int, slot_index: int) -> int:
	if not multiplayer.is_server():
		return ItemProperties.NONE
	var inv: Inventory = _inventories.get(peer_id)
	if inv == null:
		return ItemProperties.NONE

	var item_id: int = inv.remove_from_slot(slot_index)
	if item_id != ItemProperties.NONE:
		var slot: Dictionary = inv.get_slot(slot_index)
		_sync_slot_to_peer(peer_id, slot_index, slot)

	return item_id


func _sync_full_inventory_to_peer(peer_id: int, inv: Inventory) -> void:
	var data: PackedByteArray = var_to_bytes(inv.serialize())
	if peer_id == multiplayer.get_unique_id():
		_sync_full_inventory(data)
	else:
		_sync_full_inventory.rpc_id(peer_id, data)


func _sync_slot_to_peer(peer_id: int, index: int, slot: Dictionary) -> void:
	if peer_id == multiplayer.get_unique_id():
		_sync_slot(index, slot["item_id"], slot["count"])
	else:
		_sync_slot.rpc_id(peer_id, index, slot["item_id"], slot["count"])


# --- RPCs: Host -> Client (sync) ---


## Sends the full inventory to a client (on join or resync).
@rpc("authority", "reliable")
func _sync_full_inventory(data: PackedByteArray) -> void:
	var slots: Array = bytes_to_var(data)
	local_inventory = Inventory.deserialize(slots)
	local_inventory.slot_changed.connect(func(index: int) -> void:
		local_slot_changed.emit(index)
	)
	print("[InventoryManager] Received full inventory (%d slots)" % local_inventory.size)


## Updates a single slot on the client.
@rpc("authority", "reliable")
func _sync_slot(index: int, item_id: int, count: int) -> void:
	if local_inventory == null:
		return
	local_inventory.set_slot(index, item_id, count)


# --- RPCs: Client -> Host (requests / intents) ---


## Client requests to place a block from a specific inventory slot.
@rpc("any_peer", "reliable")
func _request_place_block(slot_index: int, tx: int, ty: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	var inv: Inventory = _inventories.get(sender_id)
	if inv == null:
		return

	# Validate: slot has an item.
	var slot: Dictionary = inv.get_slot(slot_index)
	if slot["item_id"] == ItemProperties.NONE:
		return

	# Validate: item is placeable.
	var item_props := ItemProperties.get_properties(slot["item_id"])
	if item_props == null or not item_props.is_placeable():
		return

	# Validate: target cell is empty.
	var coord := Vector2i(tx, ty)
	if chunk_manager == null:
		return
	if not chunk_manager.is_cell_empty(coord):
		return

	# Validate: player is in range.
	var players_node: Node = get_tree().get_root().get_node_or_null("Main/Players")
	if players_node == null:
		return
	var player_node := players_node.get_node_or_null(str(sender_id))
	if player_node == null:
		return
	var tile_center := Vector2(
		tx * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
		ty * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
	)
	if player_node.global_position.distance_to(tile_center) > GameConstants.BLOCK_INTERACT_RANGE:
		return

	# All checks passed — place block and consume item.
	chunk_manager.place_tile(coord, item_props.tile_id)
	server_remove_from_slot(sender_id, slot_index)
