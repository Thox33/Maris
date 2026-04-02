# Underwater Sandbox — 2D Multiplayer Coop Game

Godot 4.6, GDScript, host-as-server multiplayer. Terraria-inspired but entirely underwater (no sky/gravity — free-swimming movement).

## Architecture

```
[Entry point: scenes/ui/lobby_ui.tscn → scenes/ui/lobby_ui.gd]
  └── on connect → change_scene_to "main.tscn"

Main (Node2D)                         scenes/main/main.gd
├── World (WorldGenerator)            scenes/world/world_generator.gd
│   ├── TerrainLayer (TileMapLayer)   terrain_tileset.tres
│   ├── PlantLayer (TileMapLayer)     terrain_tileset.tres  ← plant/coral overlay, carries coral_sway shader
│   └── ChunkManager (Node)           scripts/world/chunk_manager.gd
├── Players (Node2D)
│   └── <PeerId> (CharacterBody2D)    scenes/player/player.gd
│       ├── CollisionShape2D
│       ├── Sprite2D
│       ├── Camera2D
│       ├── BlockInteraction          scripts/player/block_interaction.gd
│       └── UnderwaterEffects         scripts/player/underwater_effects.gd
├── Items (Node2D)
│   └── <ItemEntity> (CharacterBody2D) scripts/items/item_entity.gd
├── PlayerSpawner (MultiplayerSpawner)
├── ItemSpawner (MultiplayerSpawner)
└── InventoryManager (Node)           scenes/main/inventory_manager.gd
```

## Key Systems

### Chunk System
- World is divided into 16x16-tile chunks, loaded/unloaded around players
- `ChunkManager` checks player positions every 0.2s, load radius=3, unload radius=5 (hysteresis)
- Host generates chunks from noise, clients request via RPC
- `ChunkData` stores base_tiles + modifications separately (compact save format)
- Plant/coral tiles are mirrored onto `PlantLayer` for the sway shader; `TerrainLayer` remains the authority for physics/speed checks

### Tile System
- 3 tile types: Sand (solid), Stone (solid), Coral (swim-through, slows to 40%)
- `TileProperties` is the single source of truth: each entry has a stable integer `id`, string `name`, `atlas_coord`, and gameplay attributes
- `TileProperties.registry` — int ID → TileProperties
- `TileProperties.by_name` — string name → int ID (keep in sync with registry)
- `TileProperties.get_id_from_atlas(coord)` — decouples tile ID from atlas position
- Integer IDs are permanent — never reuse a removed ID
- New tile type = one entry in `registry` + one in `by_name`
- Physics layer set up via `_diagnose_and_fix_physics()` at runtime (iterates registry, applies solid/non-solid rules)
- Collision: TileSet physics_layer_0 (layer=1 World), Player (layer=2, mask=1)

### Item System
- `ItemProperties` — separate registry from tiles, linked via optional `tile_id` field
- `ItemProperties.registry` — int ID → ItemProperties (id, name, max_stack, tile_id)
- `ItemProperties.from_tile(tile_id)` — maps a tile to its drop item
- Items that aren't tiles (tools, materials) have `tile_id = -1`
- New item type = one entry in `ItemProperties.registry` + one in `ItemProperties.by_name`

### Inventory System (Minecraft-style)
- `Inventory` — generic container class (RefCounted, no Node). Knows nothing about players or networking. Usable for player inventories, chests, or any future container.
- 40 slots per player, first 10 = hotbar (view on inventory, not a separate structure)
- `InventoryManager` — host-authoritative, lives on Main as server infrastructure
  - Manages all player inventories keyed by peer_id
  - Full inventory sync on join, delta sync (single slot) on changes
  - Transaction model: client sends intents, host validates and applies

### Item Drops (World Entities)
- Broken blocks spawn `ItemEntity` (CharacterBody2D) in the world via `ItemSpawner`
- Items collide with terrain, drift/float underwater, have pickup delay + despawn timer
- Pickup via Area2D overlap → host adds to player inventory → entity removed
- If inventory full, item stays in world (Minecraft behavior)

### Block Breaking (Terraria-style)
- `BlockInteraction` handles input, range check, progress tracking, crack overlay
- `ChunkManager` handles the actual break + network sync (has host authority)
- On break: tile_id captured before erasure → item drop spawned at tile center
- Modifications persist in ChunkData across chunk load/unload cycles

### Block Placing
- `BlockInteraction` detects right-click on empty cell, sends intent (slot + coord) to `InventoryManager`
- `InventoryManager` validates on host: item exists in slot, is placeable, target empty, player in range
- Host calls `ChunkManager.place_tile()` + removes item from inventory, syncs both

### Networking
- Host-as-server OR dedicated server (configurable via `Main.dedicated_server` flag)
- Max 4 players, port 7777
- Scene flow: `lobby_ui.tscn` → connection → `change_scene_to_file("main.tscn")`
- Player spawning: `MultiplayerSpawner` ($PlayerSpawner) with custom `spawn_function`
- Item spawning: `MultiplayerSpawner` ($ItemSpawner) with custom `spawn_function`
- Host joins through same path as clients (no special case) — `_server_handle_join()`
- All players (including host) go through `_client_ready` → host sends seed + spawns player + creates inventory
- Block breaks: client → host (request) → all clients (sync) + item drop spawned
- Block places: client intent → host validates → host applies + syncs
- Inventory: full sync on join, delta (slot-level) on changes
- Player position: authority → all peers (unreliable)

### Visual Effects
Three-layer separation: World-Rendering | Screen-Effects | Gameplay-Data

- `coral_sway.gdshader` — vertex displacement on `PlantLayer` (World-layer, active)
- `underwater.gdshader` — fullscreen wave distortion + blue tint (Screen-layer)
  - Owned by `ScreenEffects` node in `main.tscn` (CanvasLayer 100 → ColorRect)
  - `ScreenEffects.set_underwater(bool)` to toggle — currently always on
  - ColorRect size set from `get_viewport_rect()` + `size_changed` signal
- `UnderwaterEffects` — CPUParticles2D bubbles only (World-layer, local player only)
  - Bubbles are world-space → correctly live on the Player node

### Screen Effects Architecture
New effects go in `ScreenEffects` (scripts/main/screen_effects.gd), not on Player:
- Damage flash, vignette, pause blur → add method + ColorRect/node to ScreenEffects
- Player detects state → emits event or calls ScreenEffects directly
- Player is the trigger, ScreenEffects is the owner

CanvasLayer convention:
- `0` world
- `100` fullscreen world shaders/effects
- `110` HUD
- `120` menus/windows
- `130` modal/debug
- UI that must not be distorted by fullscreen shaders must live above `100`

## Autoloads
- `GameConstants` — all tuning values (tile size, chunk config, swim speeds, network, inventory, item drops)
- `GameEvents` — central event bus (decouples systems via signals)
- `NetworkManager` — ENet multiplayer, signals for connect/disconnect
- `SaveManager` — world persistence (server-only writes), atomic file I/O

### GameEvents (Event Bus)
- `game_leaving` — fired by NetworkManager before peer closes (any disconnect path)
- `block_broken(coord, tile_id)` — fired by ChunkManager after break (server-side)
- `block_placed(coord, tile_id)` — fired by ChunkManager after place (server-side)
- `player_joined(peer_id)` — fired by Main after full join sequence
- `player_left(peer_id)` — fired by Main before disconnect cleanup
- `item_picked_up(peer_id, item_id, count)` — fired by ItemEntity after pickup
- New systems (sound, particles, achievements) connect to GameEvents — no direct coupling needed

### Save System
- Directory layout: `user://saves/<world_name>/` with `world.json`, `chunks/`, `players/`
- Only chunk **modifications** are saved (base terrain regenerated from seed)
- Atomic writes: data → `.tmp` file → rename (crash-safe)
- Chunks saved on unload, restored on load via `_generate_and_restore()`
- Player state (position + inventory) saved on disconnect, restored on join
- Auto-save every 120s (configurable via `GameConstants.AUTO_SAVE_INTERVAL`)
- Full save on window close (`NOTIFICATION_WM_CLOSE_REQUEST`)
- Player identity: keyed by `peer_id` (string) — swap to persistent IDs when lobby adds player names
- `SAVE_VERSION` constant for future format migrations

## Conventions
- GDScript style enforced via `gdtoolkit` (gdlint + gdformat)
- Pre-commit config ready (`.pre-commit-config.yaml`), needs `git init` + `pre-commit install`
- German communication, English code/comments
- Prefer .tres/.tscn for editor-owned data, .gd for logic
- New tile types = one entry in `TileProperties.registry` + one in `TileProperties.by_name`
- New item types = one entry in `ItemProperties.registry` + one in `ItemProperties.by_name`
- Server infrastructure (InventoryManager, ChunkManager, Spawners) lives on Main, not on Player
- Generic data classes (Inventory, ChunkData) are RefCounted in `scripts/`, not Nodes

## Physics Layers
| Layer | Name   | Used by                    |
|-------|--------|----------------------------|
| 1     | World  | TileSet solid tiles        |
| 2     | Player | CharacterBody2D (players)  |

## File Naming
- Scenes: `scenes/<category>/<name>.tscn` + `.gd`
- Scene-bound scripts (have RPCs, need scene tree): `scenes/<category>/<name>.gd`
- Pure data/logic scripts: `scripts/<category>/<name>.gd`
- Assets: `assets/<type>/`
- Shaders: `assets/shaders/<name>.gdshader`
