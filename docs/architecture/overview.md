# Architecture Overview

See also:

- [`../index.md`](../index.md)
- [`actor_model.md`](actor_model.md)
- [`../decisions/authority_model.md`](../decisions/authority_model.md)

Status: 2026-04-10

## Multiplayer Model

The project uses Godot's built-in `MultiplayerAPI` with `ENetMultiplayerPeer`.
One player acts as host (server + client, peer id `1`), other peers connect as clients.
The current lobby flow uses port `7777` and supports up to 4 players.

The project uses a hybrid authority model rather than one blanket rule:

- player movement is trusted co-op and owning-peer-authoritative
- inventory, placement, chunk mutation, structure mutation, and persistence are host-authoritative
- primary use / breaking is host-authoritative for damage, cooldown, crack stage, and completion

See [`../decisions/authority_model.md`](../decisions/authority_model.md) for the accepted direction and tradeoffs.

### Current authority profile

- Movement:
  - the owning peer processes local input
  - that peer simulates its own movement locally
  - remote peers render replicated snapshots with interpolation / short extrapolation
- Inventory:
  - clients send intent RPCs
  - the host owns canonical inventory and held cursor-slot state
- Placement:
  - clients send placement intent
  - the host validates range, occupancy, and item placement
- Chunk and structure mutation:
  - the host applies canonical world changes
  - clients receive synchronized state
- Persistence:
  - the host writes world and player save data

### Current breaking behavior

- clients send primary-use keepalive intent while holding the target
- the host validates target identity, range, and cooldown cadence
- the host tracks shared damaged-target state so multiple players can mine the same target together
- the host resolves mining damage from the authoritative equipped item
- the host emits crack-stage updates that `BreakVisualService` applies to the target's world visual on every peer
- the host emits the final break mutation once durability is exhausted

## Scene Flow

```text
lobby_ui.tscn  (entry point)
  Host World     -> NetworkManager.host_game() -> change_scene_to "main.tscn"
  Join World     -> NetworkManager.join_game() -> on success change_scene_to "main.tscn"
  Settings       -> local ClientProfile only

main.tscn  (game session composition root)
  World (WorldGenerator)
    GroundLayer       - visible solid ground floor tiles
    GroundCollisionLayer - hidden collision tiles for liquid / void ground states
    LiquidLayer       - visible water / lava layer with shader animation
    TerrainLayer      - hidden authoritative top-tile layer for collision / speed checks
    BaseVisualLayer   - visible flat top-tile visuals
    ChunkManager
    StructureManager
    DepthSorted
      DecorLayer      - cheap sway decor tiles that still stay tile-based
      WorldProps      - node-based vegetation props with foot-pivot y-sorting
      Players         - populated by MultiplayerSpawner
      BreakEffects    - created at runtime by BreakVisualService for break particles only
    ChunkDebugCanvas
  Items               - world item entities
  PlayerSpawner       - MultiplayerSpawner for players
  ItemSpawner         - MultiplayerSpawner for dropped items
  InventoryManager
    InventoryAuthorityService
    WorldPlacementService
  SessionBootstrapService
  SessionJoinService
  SessionIdentityService
  CharacterSetupService
  PlayerSpawnService
  SessionPersistenceService
  WorldDropService
  UseAuthorityService
  BreakVisualService
  OverheadLayer (112)
  CharacterSetup (115)
```

Per-player local UI still lives on the player scene:

- `HotbarUI`
- `ChatUI`
- `DebugOverlay`
- `SessionMenu`

The runtime scene and naming are still player-specific. The reusable gameplay baseline for future living units is defined separately in [`actor_model.md`](actor_model.md).

## Session Service Ownership

The session composition root is intentionally thin. `main.gd` wires scene references and delegates runtime responsibilities to dedicated services instead of owning session logic directly.

Current service ownership:

- `SessionBootstrapService` - selected-world activation, seed load/create flow, world initialization order, and dedicated-server bootstrap differences
- `SessionJoinService` - `_client_ready`, join validation, duplicate-account rejection, and world-seed handoff
- `SessionIdentityService` - `peer_id -> account_id`, `peer_id -> display_name`, and identity snapshot broadcast
- `CharacterSetupService` - pending character setup state, setup UI wiring, and creation submission
- `PlayerSpawnService` - spawn payload creation, spawn restoration, chunk preload before spawn, and inventory restore handoff
- `SessionPersistenceService` - autosave orchestration, world save orchestration, disconnect save, and quit/leave save
- `WorldDropService` - break-result to drop mapping and item entity spawn requests
- `UseAuthorityService` - host-authoritative primary-use validation, cooldown handling, break damage, and damaged-target replication
- `BreakVisualService` - central fixed crack-frame asset loading, shared break-state application onto breakable world visuals, and prop break-completion feedback on detached visuals
- `InventoryManager` - RPC bridge and local client sync surface for inventory state
- `InventoryAuthorityService` - canonical host-side inventory rules and held-slot state
- `WorldPlacementService` - host-side placement validation against world and structure occupancy

This ownership split is current architecture, not an in-progress migration.

## Player Spawning Flow

```text
Host boot
  -> SessionBootstrapService activates the selected world
  -> load or create world seed
  -> world.initialize(seed)
  -> load structures from save
  -> host local join handled through SessionJoinService

Client boot
  -> SessionJoinService sends _client_ready(account_id, display_name) to the host

Host receives _client_ready
  -> validate account id / duplicate login
  -> _receive_world_seed.rpc_id(sender, seed)
  -> register peer identity
  -> if world has no character for account_id:
       CharacterSetupService opens setup UI
     else:
       PlayerSpawnService completes the join

PlayerSpawnService.complete_join()
  -> choose saved or default spawn position
  -> preload chunks around spawn
  -> sync structures to the joining peer
  -> PlayerSpawner.spawn({peer_id, x, y, character_name, appearance})
  -> create / restore inventory
```

`PlayerSpawner.spawn_function` is wired to `PlayerSpawnService.create_player()`.
That method instantiates the player scene, sets `multiplayer_authority`, injects session references, and applies character data.

## Identity & Persistence

- `peer_id` is session-local network identity only.
- `account_id` is the persistent player identity used for saves.
- current provider format: `local:<client_id>`
- player saves are keyed by `(world, account_id)`, not by `peer_id`
- each world stores exactly one character per `account_id`

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

## Autoloads

- **GameConstants** - static configuration values for world, networking, inventory, and persistence.
- **GameEvents** - cross-system gameplay event bus.
- **NetworkManager** - ENet connection setup, peer lifecycle, ping, and visible-name state sync.
- **SaveManager** - world and player persistence.
- **ClientProfile** - local persistent account identity and default display name.
- **ChatManager** - chat state and session-local chat context.

## Tile System

`TileProperties` (`scripts/world/tile_properties.gd`) is the single source of truth for top-layer tiles.
`WorldPropCatalog` (`scripts/world/world_prop_catalog.gd`) is the static registry for node-based world props such as coral and trees.

Current gameplay-facing fields:

| Field | Purpose |
|---|---|
| `id` | Stable integer ID. Never reuse a removed ID. |
| `name` | Canonical string key used in code and save data. |
| `atlas_coord` | Base atlas coord in `terrain_tileset.tres`. |
| `solid` | Whether the tile blocks movement. |
| `move_speed_factor` | Speed multiplier when overlapping a non-solid top tile. |
| `breakable` | Whether the tile can be mined. |
| `hardness` | Target durability for host-authoritative breaking. |
| `render_kind` | Which tile render path this top tile uses (`FLAT_BASE`, `SWAY_DECOR`, `TALL_STRUCTURE`). |
| `drop_tile_id` | Which gameplay tile id to use for drop lookup. |
| `placement_variants` | Optional tile ids used for randomized placement visuals. |
| `body_atlas_coord` / `cap_atlas_coord` / `cap_offset_px` | Visual data for tall-structure block rendering. |

Current registry surface:

```text
TileProperties.registry   - int ID -> TileProperties
TileProperties.by_name    - string name -> int ID
TileProperties.EMPTY      - no top tile
```

Integer IDs are permanent and must never be reassigned.

Current world prop surface:

```text
WorldPropCatalog.registry - int ID -> WorldPropDefinition
WorldPropCatalog.by_name  - string name -> int ID
WorldPropCatalog.EMPTY    - no prop at this cell
```

Coral and trees live on this prop path. Trees use a separate atlas (`tree_props.png`)
with 16x32 sprites (1 tile wide, 2 tiles tall) anchored at the foot pivot. The legacy
coral tile IDs remain in `TileProperties` for compatibility with old saves and item/icon
references, but runtime chunk loading migrates old coral top-tile modifications into
sparse prop modifications.

## Asset Workflow

- Runtime gameplay art is atlas-first and atlas-only.
- `ground_tiles.png`, `liquid_tiles.png`, `terrain_tiles.png`, `tree_props.png`, `structure_tiles.png`, `block_icons.png`, and `tool_icons.png` are the canonical committed raster assets for gameplay rendering.
- When a new gameplay sprite or icon is added, extend the existing matching atlas instead of adding a standalone PNG for that same runtime asset.
- Do not keep duplicate raster copies of the same gameplay art in separate source, preview, or helper files as part of normal feature delivery.
- Do not use scripts to generate or compose gameplay graphics. Atlas PNGs are authored and edited directly.
- Some runtime definitions can technically point to custom texture paths, but that is not the normal asset workflow for this repo and should be treated as an explicit exception rather than the default path.

## Chunk System And World Rendering

- the world is divided into `16x16`-tile chunks
- `ChunkData` stores `ground_base_tiles`, `top_base_tiles`, and sparse `prop_base_cells`, plus per-layer modifications
- `ChunkManager` polls player positions every `0.2s`
- load radius is `3`, unload radius is `5`
- the host generates chunks via `FastNoiseLite`
- clients request missing chunks through `_request_chunk`

Current layer split:

- `GroundLayer` renders solid walkable floor tiles
- `GroundCollisionLayer` blocks liquid and void cells independently from visuals
- `LiquidLayer` renders water and lava visuals
- `TerrainLayer` is the authoritative top-tile occupancy layer used for collision and movement-speed checks
- `BaseVisualLayer` renders the visible flat block sprites for `FLAT_BASE` tiles
- `DecorLayer` lives inside the depth-sorted branch for cheap tile-based sway decor that still renders via `TileMapLayer`
- `WorldProps` lives inside the depth-sorted branch and owns node-based prop instances such as coral and trees
- tall structure blocks use runtime `Node2D` visuals instead of a single flat tile
- coral and trees are generated, replicated, saved, and broken through the prop layer
- trees use per-prop atlas textures with tall sprite regions (16x32) and trunk-only collision
- break crack-state is rendered on the actual world visual node for breakable tiles, props, and structures, so occlusion and y-sorting follow the same render object

Persistence behavior:

- modified chunks are kept in `ChunkData.top_modifications`, `ChunkData.ground_modifications`, and `ChunkData.prop_modifications`
- modified chunks are saved on unload and during autosave
- chunk base terrain is regenerated from seed on load

Current pragmatic runtime note:

- `world_generator.gd` still diagnoses and repairs missing TileSet physics data during `initialize()`

## Block Breaking

```text
Client holds LMB within range
  -> client sends / refreshes primary-use target intent to host

Host use authority
  -> resolves active item from authoritative inventory state
  -> validates range, target, and cooldown
  -> applies discrete break damage to the target
  -> keeps damaged targets alive for a short timeout
  -> aggregates hits from multiple players on the same target
  -> replicates crack stage to all peers
  -> BreakVisualService applies the shared crack texture to the target's actual visual node
  -> on durability exhaustion: mutates world or structure state and broadcasts the result
```

Design intent:

- breaking is one kind of item use, not a separate client-timed subsystem
- better tools can reduce cooldown and/or increase break damage
- the same cooldown lane can later cover additional primary-use actions

Current item-use scaffold:

- `ItemProperties` exposes server-authoritative `break_damage` and `use_cooldown`
- `ItemProperties` exposes `tool_kind` for future rule branching
- the host resolves these values from the active slot when applying a hit
- `stone_pickaxe` already exists and uses custom values plus a custom tool atlas icon

## Visual Effects

- **Vegetation sway shader** (`assets/shaders/vegetation_sway.gdshader`) - shared sway on tile decor and prop sprites
- **Liquid shader** (`assets/shaders/liquid.gdshader`) - shimmer animation on `LiquidLayer`
- **BreakVisualService** - fixed crack-frame texture atlas loading, shared break-stage application on world visuals, prop break-completion feedback, and break particles

### Current CanvasLayer usage

These numbers describe the current implementation, not a strict future-proof convention:

- `110` - hotbar, chat, session menu, chunk debug canvas
- `112` - overhead labels
- `115` - character setup modal
- `120` - player debug overlay

## Movement Model

There is no gravity. Players move freely in all directions via `move_and_slide()` with a velocity vector controlled by input on both axes. Movement speed is modulated by the non-solid world content the player overlaps: empty cells use `1.0x`, props such as coral and trees use the prop definition's `move_speed_factor`, and non-solid top tiles still use their tile `move_speed_factor`.
