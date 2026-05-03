extends Node
const CHARACTER_APPEARANCE := preload("res://scripts/actor/character_appearance.gd")
## Manages world persistence — chunk modifications, player data, and world metadata.
## Autoloaded as "SaveManager". All write operations are server-only.
##
## Directory layout per world:
##   user://saves/<world_name>/
##   ├── world.json                    ← seed, version, timestamps
##   ├── chunks/
##   │   └── chunk_<x>_<y>.dat        ← binary, modifications only
##   └── players/
##       └── player_<storage_key>.json ← inventory, position, stats

## Current save format version. Bump when the on-disk format changes,
## then add migration logic in _migrate_world_meta().
## v2: chunk saves split into {"top": ..., "ground": ...} dicts (ground/top layer model).
## v3: chunk saves add sparse {"props": ...} modifications for node-based world props.
## v4: chunk saves replace prop/structure split with chunk-local static world object diffs.
const SAVE_VERSION: int = 4

## Emitted on the server when an auto-save tick fires.
## Main connects to this to orchestrate saving all systems.
signal auto_save_requested

var _world_dir: String = ""
var _world_name: String = ""
var _auto_save_timer: float = 0.0


func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return

	_auto_save_timer += delta
	if _auto_save_timer >= GameConstants.AUTO_SAVE_INTERVAL:
		_auto_save_timer = 0.0
		auto_save_requested.emit()


# --- World setup ---


## Activates a world save directory. Creates folders if they don't exist.
func set_world(world_name: String) -> void:
	_world_name = world_name
	_world_dir = GameConstants.SAVE_DIR + world_name + "/"
	DirAccess.make_dir_recursive_absolute(_world_dir + "chunks")
	DirAccess.make_dir_recursive_absolute(_world_dir + "players")


## Returns true if a save for the given world name exists on disk.
func has_world_save(world_name: String) -> bool:
	return FileAccess.file_exists(GameConstants.SAVE_DIR + world_name + "/world.json")


## Returns all world names that have a world.json on disk, sorted alphabetically.
func list_worlds() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(GameConstants.SAVE_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and entry != "." and entry != "..":
			if has_world_save(entry):
				result.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result


## Returns the active world name (empty string if none set).
func get_world_name() -> String:
	return _world_name


# --- World metadata ---


## Saves world-level metadata (seed, version, timestamps).
func save_world_meta(seed_value: int) -> void:
	var meta := {
		"version": SAVE_VERSION,
		"seed": seed_value,
		"saved_at": Time.get_datetime_string_from_system(),
	}
	# Preserve created_at from existing save.
	var existing := load_world_meta()
	if existing.has("created_at"):
		meta["created_at"] = existing["created_at"]
	else:
		meta["created_at"] = meta["saved_at"]
	_write_json(_world_dir + "world.json", meta)


## Loads world metadata. Returns empty Dictionary if no save exists.
func load_world_meta() -> Dictionary:
	return _read_json(_world_dir + "world.json")


# --- Chunk persistence ---


## Saves top, ground, and static world object modifications for a chunk.
## Deletes the save file if the chunk has no modifications (keeps disk clean).
func save_chunk(coord: Vector2i, chunk: ChunkData) -> void:
	var path := _chunk_path(coord)
	if not chunk.has_any_modifications():
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	var data := {
		"top": chunk.top_modifications,
		"ground": chunk.ground_modifications,
		"world_object_additions": chunk.world_object_additions,
		"world_object_removals": chunk.world_object_removals,
	}
	_write_bytes(path, var_to_bytes(data))


## Loads chunk modifications from disk. Returns empty Dictionary if none saved.
## Supports legacy prop modifications and migrated world object diffs.
func load_chunk_modifications(coord: Vector2i) -> Dictionary:
	var path := _chunk_path(coord)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[SaveManager] Failed to read %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes_to_var(bytes)


## Saves all loaded chunks that have modifications. Called during auto-save.
func save_all_chunks(loaded_chunks: Dictionary) -> void:
	var saved_count: int = 0
	for coord: Vector2i in loaded_chunks:
		var chunk: ChunkData = loaded_chunks[coord]
		if chunk != null and chunk.has_any_modifications():
			save_chunk(coord, chunk)
			saved_count += 1
	if saved_count > 0:
		print("[SaveManager] Saved %d modified chunk(s)" % saved_count)

func load_structures() -> Array:
	var data := _read_json(_world_dir + "structures.json")
	var structures: Variant = data.get("structures", [])
	return structures if structures is Array else []


func delete_legacy_structures_save() -> void:
	var path := _world_dir + "structures.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# --- Player persistence ---


## Saves player state (inventory, position) to disk.
## account_id is the canonical persistent identity key, e.g. local:<client_id>.
func save_player(account_id: String, data: Dictionary) -> void:
	var normalized := normalize_player_record(account_id, data)
	_write_json(_player_path(account_id), normalized)


## Loads player state from disk. Returns empty Dictionary if no save exists.
## Supports the legacy client_id filename format for backwards compatibility.
func load_player(account_id: String) -> Dictionary:
	var path := _player_path(account_id)
	var data := _read_json(path)
	if not data.is_empty():
		return normalize_player_record(account_id, data)

	for legacy_path: String in _legacy_player_paths(account_id):
		data = _read_json(legacy_path)
		if not data.is_empty():
			return normalize_player_record(account_id, data)
	return {}


## Returns true if a save file exists for the given player.
func has_player_save(account_id: String) -> bool:
	if FileAccess.file_exists(_player_path(account_id)):
		return true
	for legacy_path: String in _legacy_player_paths(account_id):
		if FileAccess.file_exists(legacy_path):
			return true
	return false


## Returns true when this world already has a character record for the account.
## The existence of the character section is what later drives character creation.
func has_character(account_id: String) -> bool:
	var record := load_player(account_id)
	return not get_character_record(record).is_empty()


## Normalizes both legacy saves and new saves to a stable record shape:
## {
##   "account": { "account_id", "display_name" },
##   "character": { ... },
##   "progress": { "x", "y", "inventory" }
## }
func normalize_player_record(account_id: String, raw: Dictionary) -> Dictionary:
	var normalized := {
		"account": _normalize_account_record(account_id, raw),
		"character": _normalize_character_record(raw),
		"progress": _normalize_progress_record(raw),
	}
	return normalized


func get_account_record(record: Dictionary) -> Dictionary:
	var account: Variant = record.get("account", {})
	return account if account is Dictionary else {}


func get_character_record(record: Dictionary) -> Dictionary:
	var character: Variant = record.get("character", {})
	return character if character is Dictionary else {}


func get_progress_record(record: Dictionary) -> Dictionary:
	var progress: Variant = record.get("progress", {})
	return progress if progress is Dictionary else {}


# --- Internal helpers ---


func _chunk_path(coord: Vector2i) -> String:
	return _world_dir + "chunks/chunk_%d_%d.dat" % [coord.x, coord.y]


func _player_path(account_id: String) -> String:
	return _world_dir + "players/player_%s.json" % _storage_key(account_id)


func _legacy_player_paths(account_id: String) -> Array[String]:
	var paths: Array[String] = []
	var local_client_id := ClientProfile.get_local_client_id(account_id)
	if not local_client_id.is_empty():
		paths.append(_world_dir + "players/" + local_client_id + ".json")

	return paths


func _storage_key(raw_id: String) -> String:
	return raw_id.sha256_text()


func _normalize_account_record(account_id: String, raw: Dictionary) -> Dictionary:
	var account: Variant = raw.get("account", {})
	if not (account is Dictionary):
		account = {}

	return {
		"account_id": String(account.get("account_id", raw.get("account_id", account_id))),
		"display_name": String(account.get("display_name", raw.get("display_name", ""))),
	}


func _normalize_character_record(raw: Dictionary) -> Dictionary:
	var character: Variant = raw.get("character", {})
	if character is Dictionary:
		var normalized: Dictionary = (character as Dictionary).duplicate(true)
		var appearance: Variant = normalized.get("appearance", {})
		normalized["appearance"] = (
			CHARACTER_APPEARANCE.normalize_appearance(appearance)
			if appearance is Dictionary
			else CHARACTER_APPEARANCE.create_default_appearance()
		)
		return normalized
	return {}


func _normalize_progress_record(raw: Dictionary) -> Dictionary:
	var progress: Variant = raw.get("progress", {})
	if not (progress is Dictionary):
		progress = {}

	var x: Variant = progress.get("x", raw.get("x", null))
	var y: Variant = progress.get("y", raw.get("y", null))
	var inventory: Variant = progress.get("inventory", raw.get("inventory", null))

	var normalized: Dictionary = {}
	if x != null:
		normalized["x"] = x
	if y != null:
		normalized["y"] = y
	if inventory != null:
		normalized["inventory"] = inventory
	return normalized


## Writes a Dictionary as pretty-printed JSON with atomic rename.
func _write_json(path: String, data: Dictionary) -> void:
	var json_str := JSON.stringify(data, "\t")
	_write_string(path, json_str)


## Reads a JSON file into a Dictionary. Returns {} on any failure.
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[SaveManager] Failed to read %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("[SaveManager] Failed to parse %s: %s" % [path, json.get_error_message()])
		return {}
	if json.data is Dictionary:
		return json.data
	push_error("[SaveManager] Expected Dictionary in %s" % path)
	return {}


## Atomic write: data -> .tmp file -> rename to final path.
## Prevents corruption if the game crashes mid-write.
func _write_string(path: String, content: String) -> void:
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] Failed to write %s: %s" % [tmp_path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(content)
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp_path, path)


## Atomic write for binary data.
func _write_bytes(path: String, data: PackedByteArray) -> void:
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] Failed to write %s: %s" % [tmp_path, error_string(FileAccess.get_open_error())])
		return
	file.store_buffer(data)
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp_path, path)
