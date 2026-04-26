# Overworld Sandbox - 2D Multiplayer Coop Game

Godot 4.6, GDScript, host-as-server multiplayer. The game is now a top-down overworld sandbox with free 4-direction movement and no gravity.

## Architecture

```text
[Entry point: scenes/ui/lobby_ui.tscn -> scenes/ui/lobby_ui.gd]
  -> on connect -> change_scene_to "main.tscn"

Main (Node2D)                         scenes/main/main.gd
|- World (WorldGenerator)             scenes/world/world_generator.gd
|  |- GroundLayer (TileMapLayer)      runtime ground atlas
|  |- GroundCollisionLayer            runtime collision-only tiles
|  |- LiquidLayer (TileMapLayer)      runtime liquid atlas
|  |- TerrainLayer (TileMapLayer)     terrain_tileset.tres
|  |- BaseVisualLayer (TileMapLayer)  terrain_tileset.tres
|  |- DepthSorted/DecorLayer          terrain_tileset.tres
|  |- ChunkManager (Node)             scripts/world/chunk_manager.gd
|  `- StructureManager (Node)         scripts/world/structure_manager.gd
|- Players (Node2D)
|  `- <PeerId> (CharacterBody2D)      scenes/player/player.gd
|     |- CollisionShape2D
|     |- VisualRoot/HumanoidVisual
|     |- Camera2D
|     |- BlockInteraction             scripts/player/block_interaction.gd
|     |- HotbarUI
|     |- DebugOverlay
|     `- ChatUI
|- Items (Node2D)
|  `- <ItemEntity> (CharacterBody2D)  scripts/items/item_entity.gd
|- PlayerSpawner (MultiplayerSpawner)
|- ItemSpawner (MultiplayerSpawner)
`- InventoryManager (Node)            scenes/main/inventory_manager.gd
```

## Key Systems

### Chunk System
- World is divided into `16x16`-tile chunks, loaded and unloaded around players.
- `ChunkManager` checks player positions every `0.2s`, load radius=`3`, unload radius=`5`.
- The host generates chunks from noise; clients request them via RPC.
- `ChunkData` stores `ground_base_tiles`, `top_base_tiles`, and per-layer modifications.
- `GroundLayer` and `LiquidLayer` are visual-only.
- `GroundCollisionLayer` blocks liquid and void cells.
- `TerrainLayer` remains the authoritative top-tile collision layer.

### Tile System
- Ground and top tiles are split across `GroundTileProperties` and `TileProperties`.
- `GroundTileProperties` defines floor states such as dirt, sand, stone, grass, water, and lava.
- `TileProperties` defines top-layer obstacles and decor such as sand blocks, stone blocks, and coral variants.
- `WorldPropCatalog` defines node-based vegetation props such as coral and trees.
- Props support per-definition sprite sizes (e.g. 16x32 or 32x32 for trees), custom atlas textures, and partial collision.
- Props declare `allowed_ground_names` for data-driven ground validation during world generation.
- Multi-cell props are automatically reserved during chunk generation to prevent overlaps.
- Non-solid top decor uses `move_speed_factor` for slowdown.
- Integer IDs are permanent and must never be reused.

### Atlas Architecture
- **World atlases** hold sprites rendered in the game world:
  - `ground_tiles.png` — ground layer tiles (dirt, sand, grass, etc.)
  - `liquid_tiles.png` — liquid layer tiles (water, lava)
  - `terrain_tiles.png` — top-layer tiles and coral decor (TileMapLayer + WorldProp)
  - `tree_props.png` — tree world props only
  - `structure_tiles.png` — structure visuals (furnace, etc.)
- **Item icon atlases** are split by category:
  - `block_icons.png` — block and material icons (sand, stone, coral, wood, furnace)
  - `tool_icons.png` — tool and weapon icons (pickaxe, etc.)
- New world sprites go into the appropriate world atlas; new item icons go into the matching category atlas.

### Inventory System
- `Inventory` is a generic container class (RefCounted, no Node).
- 40 slots per player, first 10 = hotbar.
- `InventoryManager` is the server-facing bridge on `Main`.
- `InventoryAuthorityService` owns canonical inventory mutation rules.
- `WorldPlacementService` validates range, occupancy, and placement legality.

### Item Drops
- Broken blocks spawn `ItemEntity` via `ItemSpawner`.
- Item drops collide with the world, drift gently, have pickup delay, and despawn after a timeout.
- Pickup is host-authoritative: the host adds items to inventory and removes the entity.

### Breaking And Placing
- `BlockInteraction` handles local input, range checks, and intent submission.
- `UseAuthorityService` is host-authoritative for primary use / breaking.
- `ChunkManager` applies canonical top-tile mutations and synchronizes them.
- `StructureManager` keeps structure occupancy separate from tile data.

### Networking
- Host-as-server or dedicated server.
- Max 4 players, default port `7777`.
- Player spawning uses `MultiplayerSpawner`.
- Item spawning uses `MultiplayerSpawner`.
- Movement is owning-peer-authoritative for trusted co-op.
- Inventory, placement, chunk mutation, structure mutation, and persistence are host-authoritative.

### Visual Effects
- `vegetation_sway.gdshader` animates decor on `DecorLayer`.
- `liquid.gdshader` animates water and lava on `LiquidLayer`.
- `BreakVisualService` applies host-replicated fixed crack-frame stages to breakable world visuals and drives break-completion feedback and particles.

## Autoloads
- `GameConstants` - world, movement, networking, inventory, and persistence tuning.
- `GameEvents` - central gameplay event bus.
- `NetworkManager` - ENet setup and peer lifecycle.
- `SaveManager` - world and player persistence.
- `ClientProfile` - local account identity and display name.
- `ChatManager` - chat state and session-local context.

## Save System
- Saves live under `user://saves/<world_name>/`.
- Only chunk modifications are written; base terrain is regenerated from the seed.
- Chunk files store top and ground modifications separately.
- Player saves are keyed by persistent `account_id`, not by transient `peer_id`.
- Writes are atomic via `.tmp` + rename.

## Conventions
- German communication, English code/comments.
- Prefer `.tres` / `.tscn` for editor-owned data and `.gd` for logic.
- Server infrastructure lives on `Main`, not on `Player`.
- Generic data classes such as `Inventory` and `ChunkData` are RefCounted scripts, not Nodes.

## Physics Layers
| Layer | Name | Used by |
|---|---|---|
| 1 | World | Ground/top collision tiles and structure visuals |
| 2 | Player | CharacterBody2D players |

## File Naming
- Scenes: `scenes/<category>/<name>.tscn` + `.gd`
- Scene-bound scripts: `scenes/<category>/<name>.gd`
- Pure data/logic scripts: `scripts/<category>/<name>.gd`
- Assets: `assets/<type>/`
- Shaders: `assets/shaders/<name>.gdshader`
