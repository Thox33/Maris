# Overworld Migration Plan

See also:

- [`../index.md`](../index.md)
- [`../architecture/overview.md`](../architecture/overview.md)
- [`../systems/character_pipeline.md`](../systems/character_pipeline.md)

Status: 2026-04-12

## Purpose

Shift the game's setting and data model from an underwater narrative to a top-down overworld
in the style of Forager / Corekeeper. The perspective and movement model stay the same
(free 4-direction movement, no gravity). What changes is the visual framing, naming, tile
content, and the world data model — which gains a second per-cell slot for a ground layer.

## Current Baseline

Already in place:

- free 4-direction movement with friction and acceleration (mechanically identical to top-down walking)
- chunk-based world with procedural noise generation
- single tile ID per cell stored in `ChunkData.base_tiles`
- tile registry with sand, stone, and coral variants (IDs 0–7)
- `vegetation_sway.gdshader` applied to the decor layer
- underwater fullscreen distortion shader on `ScreenEffects`
- ambient bubble particles on the local player via `UnderwaterEffects`

## The New Tile Model

Each cell will hold two tile slots:

**Ground layer** — the floor of the cell:
- Solid ground (dirt, sand, stone) → player walks over it freely
- Liquid (water, lava) → impassable
- Void (chasm) → impassable
- The player can modify ground (fill lava, bridge chasms)

**Top layer** — what sits on the ground:
- Empty → player moves freely (if ground is solid)
- Vegetation (grass, fern, mushroom, flower) → walk-through, gameplay drops and speed modifiers
- Placed block or structure → impassable
- Placement rule: a top tile can only be placed if the ground below is solid

Collision summary:

| Ground | Top | Result |
|---|---|---|
| Solid | Empty | Player moves freely |
| Solid | Vegetation | Player passes through, possible speed modifier |
| Solid | Block / Structure | Player blocked by top tile |
| Liquid / Void | any | Player blocked by ground |

---

## Remaining Work

### Phase 1 — Remove underwater visual effects

Goal:
Strip all underwater-specific visual effects so the game no longer looks or feels like an
underwater scene.

Tasks:

- remove `set_underwater()` and `_underwater_overlay` reference from `screen_effects.gd`
- delete `assets/shaders/underwater.gdshader`
- remove the `UnderwaterOverlay` ColorRect from `main.tscn`
- delete `scripts/player/underwater_effects.gd`
- remove the `UnderwaterEffects` node from `scenes/player/player.tscn`
- delete `assets/shaders/coral_sway.gdshader` (content is identical to `vegetation_sway.gdshader`)

Done when:

- no blue tint or wave distortion appears on screen
- no bubble particles spawn around the player
- no dead references remain to the deleted files

---

### Phase 2 — Rename swimming constants and input actions

Goal:
Replace all swim-specific naming with neutral movement terminology so the codebase no
longer implies an underwater context.

Tasks:

- rename in `GameConstants`: `SWIM_SPEED` → `MOVE_SPEED`, `SWIM_ACCELERATION` → `MOVE_ACCELERATION`, `SWIM_FRICTION` → `MOVE_FRICTION`, `WORLD_DEPTH_SCALE` → `WORLD_SCALE`
- rename input actions in `project.godot`: `swim_left/right/up/down` → `move_left/right/up/down`
- update all `Input.get_axis("swim_*")` calls in `player.gd`
- rename `swim_speed_factor` → `move_speed_factor` in `TileProperties` and all usages

Done when:

- no symbol containing `swim` or `underwater` remains in code or project settings

---

### Phase 3 — Introduce the ground/top data model

Goal:
Extend `ChunkData` to store two tile IDs per cell and wire all systems that read or write
tile data through the new model. Add the first ground-layer tile registry and sprites.

Tasks:

- extend `ChunkData` with `ground_tiles[]` alongside the existing `base_tiles[]` (renamed to `top_tiles[]`)
- update serialization and network sync to include both arrays
- add a `GroundLayer` (TileMapLayer) to `world_generator.tscn` below the existing layers
- wire `GroundLayer` into `ChunkManager.setup()` and `_apply_cell()` / `_erase_chunk()`
- add physics collision on `GroundLayer` for liquid and void tile IDs only
- create a new ground tile registry in `TileProperties` (separate from existing top-tile IDs):
  - `dirt` — solid ground
  - `sand` — solid ground
  - `stone` — solid ground
  - `grass` — solid ground (surface variant)
- draw sprites for the four ground tiles and add them to the terrain atlas
- update `ChunkManager.is_cell_empty()` and placement validation in `WorldPlacementService` to check both layers

Done when:

- `ChunkData` stores and syncs ground + top independently
- the ground layer renders visually in the world
- solid ground tiles are walkable, liquid/void tiles block the player
- existing top-tile behavior (coral, stone block) is unaffected

---

### Phase 4 — Update world generation

Goal:
Generate ground and top tiles separately so the world reads as a top-down overworld
rather than a depth-density underwater cave system.

Tasks:

- rewrite `_get_tile_for_position()` in `world_generator.gd` to return a ground ID and a top ID
- ground generation: noise determines dirt / sand / stone / void distribution; separate noise pass places liquid pools
- top generation: vegetation (starting with grass decor) spawns on solid ground with noise-based probability
- update `generate_chunk()` to write both values into `ChunkData`
- update spawn-position logic to land the player on a solid-ground cell with no top tile

Done when:

- newly generated worlds have visible ground variety (dirt, sand, stone patches)
- vegetation appears on solid ground
- the player spawns standing on solid ground

---

### Phase 5 — Update documentation

Tasks:

- update `CLAUDE.md`: overworld narrative, renamed constants, new tile model, remove underwater shader references
- update `docs/plans/roadmap.md`: replace underwater-specific feature entries with overworld equivalents
