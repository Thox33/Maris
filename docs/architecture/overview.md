# Architecture Overview

See also:

- [`../index.md`](../index.md)
- [`actor_model.md`](actor_model.md)

## Multiplayer Model

Godot's built-in `MultiplayerAPI` with `ENetMultiplayerPeer`. One player acts as host
(server + client, peer id 1), others connect as clients. Max 4 players, port 7777.

- The project uses a hybrid authority model rather than a single rule for every subsystem.
- Player movement is currently trusted co-op and owning-peer-authoritative with remote smoothing.
- World mutation, structures, placement, inventory, and persistence are authoritative on the host.
- Breaking now uses host-authoritative target damage, cooldown, and completion.
- Uses `@rpc` annotations for remote procedure calls.

See [`../decisions/authority_model.md`](../decisions/authority_model.md) for the accepted direction and tradeoffs.

### Current authority profile

- Movement:
  - input is processed on the owning peer
  - the owning peer simulates movement locally
  - remote peers render replicated state with smoothing
- Inventory:
  - clients send requests
  - the host owns canonical inventory and held-slot state
- Placement:
  - clients send placement intent
  - the host validates range, occupancy, and item placement
- Chunk and structure mutation:
  - the host applies canonical world changes
  - clients receive synchronized state
- Persistence:
  - the host writes world and player save data

### Current breaking behavior

- clients may start crack visuals immediately
- clients send item-use intent instead of owning break completion
- the host validates target, range, equipped item, and hit cadence
- the host tracks shared damaged-target state so multiple players can mine the same target together
- the host applies discrete hits through a unified item-use cooldown model
- the host emits crack-stage updates and the final break mutation

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

Note:

- the current runtime scene and spawning flow are still player-specific in naming
- the reusable gameplay baseline for future living units is defined separately in [`actor_model.md`](actor_model.md)

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

## Chunk System

- World divided into 16x16-tile chunks.
- `ChunkData` stores `base_tiles` (PackedByteArray) + `modifications` (Dictionary).
- `ChunkManager` polls player positions every 0.2s, load radius=3, unload radius=5.
- Host generates chunks via `FastNoiseLite`; clients request via `_request_chunk` RPC.
- Tile visuals are resolved generically from `TileProperties`:
  - direct atlas tiles go straight to `TerrainLayer`
  - terrain-connect rendering is possible through tile metadata when needed
  - optional overlay layers such as `PlantLayer` can mirror base content visually when needed
- `TerrainLayer` remains the authority for physics and speed checks.
- Modifications (broken tiles) persist across load/unload cycles in `ChunkData`.

## Block Breaking

```text
Client holds LMB within range
  -> local crack feedback can start immediately
  -> client sends "start primary use on target" intent to host

Host use authority
  -> resolves active item from authoritative inventory state
  -> validates range, target, and cooldown
  -> applies discrete break damage to the target
  -> keeps damaged targets alive for a short timeout
  -> aggregates hits from multiple players on the same target
  -> replicates crack stage to all peers
  -> on durability exhaustion: mutates world and broadcasts break result
```

Design intent:

- breaking is treated as one kind of item use, not as a separate time-simulation subsystem
- better tools can reduce cooldown and/or increase break damage
- the same cooldown lane can later prevent simultaneous use of incompatible actions such as mining and attacking in the same frame window

Current item-use scaffold:

- `ItemProperties` now exposes server-authoritative `break_damage` and `use_cooldown`
- `ItemProperties` also exposes a lightweight `tool_kind` classification for future rules
- the host resolves these values from the active slot when applying a mining hit
- all current items still use the default baseline values, so no gameplay balance changed yet
- the first tool can be introduced before a dedicated tool-atlas pipeline exists by using a temporary placeholder icon in the current item rendering path

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
