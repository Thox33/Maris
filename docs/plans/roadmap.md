# Roadmap & Feature Backlog

See also:

- [`../index.md`](../index.md)
- [`../architecture/overview.md`](../architecture/overview.md)

## Architectural Groundwork (do early, expensive to retrofit)

### Session Architecture Refactor
The refactor baseline is complete and its current shape is reflected in [`../architecture/overview.md`](../architecture/overview.md).

- [x] Split `main.gd` into smaller session services
- [x] Reduce direct scene-path coupling between runtime systems
- [x] Narrow `InventoryManager` into an RPC bridge backed by dedicated authority / placement services
- [x] Decide and document the authority model baseline
- [x] Move block and structure breaking to host-authoritative item-use damage + cooldown

### Autotiling / Terrain Blending
Tiles should visually blend with same-type neighbors (grass patches, seamless sand/stone).

**Godot system:** TileSet Terrain Sets + `set_cells_terrain_connect()`

**What's needed:**
- For each tile type: a **blob tileset** with up to 47 sprite variants
  (8-directional corner+side matching - the standard "Wang blob" layout)
- Open question: should vegetation-heavy ground patches do full blob or just 4-direction side matching?
- Add a Terrain Set to `terrain_tileset.tres` in the editor
- Assign terrain patterns to each atlas tile variant
- Replace `terrain_layer.set_cell()` in `ChunkManager._apply_chunk()` with
  `terrain_layer.set_cells_terrain_connect()` - Godot handles variant selection
  and chunk border refresh automatically

**Chunk border handling:** Godot's terrain API updates border tiles of adjacent
chunks automatically when a new chunk is applied. No extra code needed.

---

### Inventory + Item Data Model
Prerequisite for: block placing, crafting, drops, chests, hotbar.

- [x] Item registry (similar to TileProperties - string name + stable int ID)
- [x] Stack-based slot system
- [x] Serialization for network sync + save files

---

### World Persistence (Save / Load)
ChunkData already has `base_tiles` + `modifications` separately - the hard part is done.

- [x] World metadata + chunk/player save files
- [x] Periodic save + on-quit save
- [x] Stable `account_id` save keys instead of `peer_id`
- [x] World-bound character record (`account` / `character` / `progress`)

---

## Gameplay Features

- [x] Block placing (right click)
- [x] Hotbar UI
- [ ] More tile types (shrubs, ore nodes, ruins, ...)
- [ ] Biomes (starter/heat/cold/overgrown/rocky zones with different generation parameters)
- [ ] Passive overworld creatures
- [ ] Enemies
- [ ] Crafting
- [ ] Chests / loot
- [ ] Environmental hazards and terrain effects
- [ ] Character editing after first creation

---

## Visual / Feel

- [ ] Dynamic lighting (`CanvasLight2D`) - torches, campfires, lava glow
- [ ] Atmospheric light shafts / fog layers
- [ ] Animated tiles (AnimatedSprite2D or animated atlas - grass, foliage, lava details)
- [ ] Better ambient particles (dust, leaves, embers)
- [ ] Minimap (SubViewport rendering a zoomed-out world view)
- [x] Player animation baseline (side-view `idle` / `run`)
- [ ] Additional player action states (`use`, `hurt`, `attack`)
- [ ] Background parallax layers (distant rock formations, fog)

---

## Technical / Infrastructure

- [ ] Shared settings screen between lobby and in-game menu
- [ ] Stronger identity provider later (e.g. Steam-backed account identity)
- [ ] `MultiplayerSynchronizer` for property sync (health, state) - complement to spawner
- [ ] Async chunk generation (ResourceLoader threaded load, no frame spikes)
- [ ] TileSet custom data layers (per-tile metadata: light emission, spawn weight, biome tag)
- [ ] Sound (AudioStreamPlayer, positional AudioStreamPlayer2D)
- [ ] Navigation mesh for enemy pathfinding (NavigationRegion2D + NavigationAgent2D)
