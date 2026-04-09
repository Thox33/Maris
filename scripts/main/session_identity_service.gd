extends Node

## Server-side session identity mappings for connected peers.
## Keeps persistent identity concerns out of the main scene coordinator.

var _peer_to_account_id: Dictionary = {}
var _peer_to_display_name: Dictionary = {}


func register_peer(peer_id: int, account_id: String, display_name: String) -> void:
	if peer_id <= 0:
		return
	_peer_to_account_id[peer_id] = account_id
	_peer_to_display_name[peer_id] = _sanitize_display_name(display_name, peer_id)


func remove_peer(peer_id: int) -> void:
	_peer_to_account_id.erase(peer_id)
	_peer_to_display_name.erase(peer_id)


func get_account_id(peer_id: int) -> String:
	return String(_peer_to_account_id.get(peer_id, ""))


func get_display_name(peer_id: int) -> String:
	return _sanitize_display_name(String(_peer_to_display_name.get(peer_id, "")), peer_id)


func has_duplicate_account(account_id: String) -> bool:
	return account_id in _peer_to_account_id.values()


func broadcast_player_identities() -> void:
	if not multiplayer.is_server():
		return
	NetworkManager._sync_player_identities.rpc(_build_player_identity_snapshot())


func _build_player_identity_snapshot() -> Array:
	var snapshot: Array = []
	for peer_id_variant in _peer_to_display_name.keys():
		var peer_id := int(peer_id_variant)
		var account_id := get_account_id(peer_id)
		var record := SaveManager.load_player(account_id)
		var character := SaveManager.get_character_record(record)
		snapshot.append(
			{
				"peer_id": peer_id,
				"display_name": get_display_name(peer_id),
				"character_name": String(character.get("name", "")),
			}
		)
	return snapshot


func _sanitize_display_name(display_name: String, peer_id: int) -> String:
	var safe_name := display_name.strip_edges().left(32)
	if safe_name.is_empty():
		safe_name = "Player_%d" % peer_id
	return safe_name
