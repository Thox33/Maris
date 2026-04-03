extends Node
## Manages the local client identity: a stable client_id and a display name.
## Autoloaded as "ClientProfile". Available before any game scene loads.
##
## client_id is generated once on first run and persists indefinitely.
## It is the stable key for player saves within each world — independent of
## the ephemeral network peer_id. display_name is the name shown to other
## players and can be changed freely without affecting save data.

const DEFAULT_PROFILE_SLOT: String = "default"
const LOCAL_ACCOUNT_PREFIX: String = "local:"

## Stable identity for this installation. Never changes after generation.
var client_id: String = ""
## Display name shown to other players in-game. User-editable.
var display_name: String = "Player"
## Profile slot name used to keep multiple local test identities separate.
var profile_slot: String = DEFAULT_PROFILE_SLOT


func _ready() -> void:
	profile_slot = _resolve_profile_slot()
	_load_or_create()


## Persists current client_id and display_name to disk (atomic write).
func save_profile() -> void:
	DirAccess.make_dir_recursive_absolute("user://config")
	var data := {"client_id": client_id, "display_name": display_name}
	var path := _profile_path()
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error(
			"[ClientProfile] Cannot write %s: %s" % [tmp, error_string(FileAccess.get_open_error())]
		)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp, path)


## Returns the canonical persistent account id for this installation.
## Prefixing the provider keeps the on-disk/network format extensible, e.g.
## local:<client_id> today and steam:<steam_id> later.
func get_account_id() -> String:
	return make_local_account_id(client_id)


## Returns true if id matches the expected format: 4 × 8 lowercase hex chars
## separated by dashes (e.g. "a1b2c3d4-e5f6a7b8-c9d0e1f2-a3b4c5d6").
## Used server-side to reject obviously invalid values sent by clients.
func is_valid_client_id(id: String) -> bool:
	if id.length() != 35:
		return false
	var parts := id.split("-")
	if parts.size() != 4:
		return false
	for part: String in parts:
		if part.length() != 8:
			return false
		for c: String in part:
			if not c in "0123456789abcdef":
				return false
	return true


## Returns a canonical account id for a locally generated client id.
func make_local_account_id(id: String) -> String:
	return LOCAL_ACCOUNT_PREFIX + id


## Returns true if the account id belongs to the local provider and carries a
## valid client_id payload. Additional providers can be added here later.
func is_valid_account_id(account_id: String) -> bool:
	if not account_id.begins_with(LOCAL_ACCOUNT_PREFIX):
		return false
	return is_valid_client_id(account_id.trim_prefix(LOCAL_ACCOUNT_PREFIX))


## Returns the embedded client_id for local:<id> accounts, else empty string.
func get_local_client_id(account_id: String) -> String:
	if not account_id.begins_with(LOCAL_ACCOUNT_PREFIX):
		return ""
	var id := account_id.trim_prefix(LOCAL_ACCOUNT_PREFIX)
	return id if is_valid_client_id(id) else ""


func _load_or_create() -> void:
	var path := _profile_path()
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			var text := file.get_as_text()
			file.close()
			var json := JSON.new()
			if json.parse(text) == OK and json.data is Dictionary:
				var data: Dictionary = json.data
				var stored_id: String = data.get("client_id", "")
				if is_valid_client_id(stored_id):
					client_id = stored_id
				var stored_name = data.get("display_name", "")
				if stored_name is String and not (stored_name as String).is_empty():
					display_name = stored_name

	if client_id.is_empty():
		client_id = _generate_client_id()
		save_profile()
		print("[ClientProfile] Generated new client_id: %s (slot=%s)" % [client_id, profile_slot])
	else:
		print("[ClientProfile] Loaded client_id: %s (slot=%s)" % [client_id, profile_slot])


func _generate_client_id() -> String:
	return "%08x-%08x-%08x-%08x" % [randi(), randi(), randi(), randi()]


func _profile_path() -> String:
	return "user://config/client_profile_%s.json" % profile_slot


func _resolve_profile_slot() -> String:
	var slot := _scan_profile_slot(OS.get_cmdline_args(), DEFAULT_PROFILE_SLOT)
	slot = _scan_profile_slot(OS.get_cmdline_user_args(), slot)
	slot = slot.strip_edges()
	return _sanitize_slot(slot) if not slot.is_empty() else DEFAULT_PROFILE_SLOT


func _scan_profile_slot(args: PackedStringArray, current: String) -> String:
	var slot := current
	for i in range(args.size()):
		var arg := args[i]
		if arg == "--client-profile" and i + 1 < args.size():
			slot = args[i + 1]
		elif arg.begins_with("--client-profile="):
			slot = arg.get_slice("=", 1)
	return slot


func _sanitize_slot(raw: String) -> String:
	var allowed := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
	var result := ""
	for c: String in raw:
		if c in allowed:
			result += c
	return result if not result.is_empty() else DEFAULT_PROFILE_SLOT
