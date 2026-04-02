# Underwater Sandbox — 2D Multiplayer Coop Game

Godot 4.6, GDScript, host-as-server multiplayer. Terraria-inspired but entirely underwater (no sky/gravity — free-swimming movement).

## Architecture

```
[Entry point: scenes/ui/lobby_ui.tscn → scenes/ui/lobby_ui.gd]
  └── on connect → change_scene_to "main.tscn"

Main (Node2D)                         scenes/main/main.gd
├── World (WorldGenerator)            scenes/world/world_generator.gd
│   ├── TerrainLayer (TileMapLayer)   terrain_tileset.tres
│   ├── CoralLayer (TileMapLayer)     terrain_tileset.tres  ← coral-only, carries coral_sway shader
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
- Coral tiles are mirrored onto `CoralLayer` for the sway shader; `TerrainLayer` remains the authority for physics/speed checks

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
- `underwater.gdshader` — fullscreen wave distortion + blue tint (active, on CanvasLayer 100)
- `coral_sway.gdshader` — vertex displacement on `CoralLayer` (active)
- `UnderwaterEffects` — CPUParticles2D bubbles + water shader overlay (local player only)
- Underwater shader ColorRect size set explicitly from `get_viewport_rect()` + `size_changed` signal

## Autoloads
- `GameConstants` — all tuning values (tile size, chunk config, swim speeds, network, inventory, item drops)
- `NetworkManager` — ENet multiplayer, signals for connect/disconnect

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
