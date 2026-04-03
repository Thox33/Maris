# Architecture Notes

## Multiplayer Model

Godot's built-in `MultiplayerAPI` with `ENetMultiplayerPeer`. One player acts as host
(server + client, peer id 1), others connect as clients. Max 4 players, port 7777.

- Game state (world tiles, player positions) is authoritative on the host.
- Clients send input/actions to the host; host validates and broadcasts state.
- Uses `@rpc` annotations for remote procedure calls.

## Scene Flow

```text
lobby_ui.tscn  (entry point)
  Host World     -> NetworkManager.host_game() -> change_scene_to "main.tscn"
  Join World     -> NetworkManager.join_game() -> change_scene_to "main.tscn"
  Settings       -> local profile/settings only

main.tscn  (game world)
  World (WorldGenerator)
    TerrainLayer (TileMapLayer) - authoritative gameplay tiles
    PlantLayer (TileMapLayer)   - plant/coral visual overlay + sway shader
    ChunkManager
  Players (Node2D)              - populated by MultiplayerSpawner
  PlayerSpawner (MultiplayerSpawner)
  CharacterSetup (CanvasLayer)  - shown when a world has no character for this account
```

## Player Spawning Flow

```text
Host _ready()
  -> world.initialize(seed)
  -> load_chunks_around(spawn_pos)
  -> PlayerSpawner.spawn({peer_id, x, y})   <- replicates to all peers automatically

Client _ready()
  -> _client_ready.rpc_id(1)

Host receives _client_ready from client
  -> _receive_world_seed.rpc_id(sender, seed)
  -> if world has no character for account_id:
       open character setup
       wait for character submit
  -> else:
       PlayerSpawner.spawn({peer_id, x, y, character_name, appearance})
         <- replicates to all peers automatically

Client receives _receive_world_seed
  -> world.initialize(seed)
  -> load_chunks_around(spawn_pos)
```

`MultiplayerSpawner` calls `_create_player(data)` on every peer to reconstruct the node,
including setting `multiplayer_authority`. No manual `_request_spawn_player` RPC needed.

## Identity & Persistence

- `peer_id` is session-local network identity only.
- `account_id` is the persistent player identity used for saves.
- Current provider format: `local:<client_id>`.
- Player saves are keyed by `(world, account_id)`, not by `peer_id`.
- Each world stores exactly one character per `account_id`.

Normalized player save shape:

```text
account
  account_id
  display_name
character
  name
  appearance
progress
  x, y, inventory
```

Legacy flat saves are normalized on load so old worlds remain readable.

## Autoloads (Singletons)

- **GameConstants** - static configuration values (tile size, chunk size, swim speeds, port).
- **NetworkManager** - ENet connection setup, `players` dict, connect/disconnect signals.

## Tile System

`TileProperties` (`scripts/world/tile_properties.gd`) is the single source of truth for
all tile types.

Core gameplay fields:

| Field | Purpose |
|---|---|
| `id` | Stable integer ID - never reuse a removed ID |
| `name` | Canonical string key - used in saves/code |
| `atlas_coord` | Default atlas coord in `terrain_tileset.tres` |
| `solid` | Whether the tile has physics collision |
| `swim_speed_factor` | Speed multiplier when overlapping |
| `breakable` | Can the player mine this tile? |
| `hardness` | Seconds to break |

Render metadata:

| Field | Purpose |
|---|---|
| `render_mode` | Direct atlas tile or terrain-connect tile |
| `terrain_set_id` / `terrain_id` | Terrain metadata for autotiling |
| `visual_layer` | Optional overlay tilemap for animated visuals |
| `shader_profile` | Which overlay shader profile to use |
| `family` | High-level content family for asset organization |

```text
TileProperties.registry              - int ID -> TileProperties
TileProperties.by_name               - string -> int ID
TileProperties.get_id_from_atlas()   - atlas coord -> int ID
TileProperties.EMPTY                 - no tile
```

Integer IDs are permanent and must never be reassigned.

### Tile families

The tileset is organized by content family rather than one-off special cases:

- `terrain_base`
  Use for normal world tiles such as sand and stone. These can start as direct atlas
  tiles and later move to terrain-connect without changing gameplay code.
- `coral_cluster`
  Connected coral mass that should use `set_cells_terrain_connect()` and the coral
  visual overlay. This is the current role of the existing `coral` tile ID.
- `coral_plant`
  Decorative stem/fan coral that should not use blob autotiling. These belong on an
  overlay/decor layer with stronger sway and multiple standalone variants.

This split matters because a 47-tile blob set is correct for colonies and walls, but
wrong for individual stems.

### Recommended asset structure

For each future family, use the same pattern:

- Base terrain family:
  - atlas region for direct fallback tiles
  - optional terrain set with 47 blob variants
- Overlay family:
  - separate tilemap layer
  - one shader profile
  - multiple art variants for singles/end caps where repetition would be obvious

For coral specifically:

- `coral_cluster`
  - 47-tile terrain set in the main tileset
  - optional duplicates for especially common masks to reduce repetition
  - mirrored onto `PlantLayer` for sway
- `coral_plant`
  - 4-8 standalone variants
  - no terrain-connect
  - stronger sway profile than clusters

## Chunk System

- World divided into 16x16-tile chunks.
- `ChunkData` stores `base_tiles` (PackedByteArray) + `modifications` (Dictionary).
- `ChunkManager` polls player positions every 0.2s, load radius=3, unload radius=5.
- Host generates chunks via `FastNoiseLite`; clients request via `_request_chunk` RPC.
- Tile visuals are resolved generically from `TileProperties`:
  - direct atlas tiles go straight to `TerrainLayer`
  - terrain families use `set_cells_terrain_connect()`
  - optional overlay layers such as `PlantLayer` mirror the same terrain family visually
- `TerrainLayer` remains the authority for physics and speed checks.
- Modifications (broken tiles) persist across load/unload cycles in `ChunkData`.

## Block Breaking

```text
Client holds LMB within range
  -> BlockInteraction accumulates progress, shows crack overlay
  -> on completion: ChunkManager.break_tile(coord)

ChunkManager.break_tile (server)
  -> _do_break_tile (erase from terrain + overlays, record modification)
  -> _sync_break_tile.rpc (broadcast to all clients)
```

## Visual Effects

- **Underwater shader** (`assets/shaders/underwater.gdshader`) - fullscreen wave distortion
  + blue tint. Applied to a `ColorRect` on `CanvasLayer 100`.
- **Coral sway shader** (`assets/shaders/coral_sway.gdshader`) - vertex displacement on
  `PlantLayer` only. Neighboring coral tiles get phase/amplitude variation so they do not
  move in lockstep.
- **Bubbles** - `CPUParticles2D` in `UnderwaterEffects`, local player only.

### CanvasLayer convention

Use `CanvasLayer` to separate world rendering, fullscreen effects, and UI:

- `0` - world rendering (default gameplay scene content)
- `50` - world-adjacent overlays/effects if needed later
- `100` - fullscreen world effects such as the underwater distortion/tint
- `110` - HUD such as hotbar, status bars, and crosshair
- `120` - menus and windows such as inventory, crafting, and session UI
- `130` - modal popups and debug overlays

Rule of thumb:

- Content at or below `100` is allowed to be affected by fullscreen world shaders.
- UI that must remain crisp and readable belongs above `100`.

## Underwater Physics

No gravity. Players swim freely in all directions via `move_and_slide()` with a
velocity vector controlled fully by input (X and Y). Speed is modulated by the tile
the player overlaps: open water = 1.0x, coral = 0.4x.
