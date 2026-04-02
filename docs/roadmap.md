# Roadmap & Feature Backlog

## Architectural Groundwork (do early, expensive to retrofit)

### Autotiling / Terrain Blending
Tiles should visually blend with same-type neighbors (coral colony, seamless sand/stone).

**Godot system:** TileSet Terrain Sets + `set_cells_terrain_connect()`

**What's needed:**
- For each tile type: a **blob tileset** with up to 47 sprite variants
  (8-directional corner+side matching - the standard "Wang blob" layout)
- Open question: should coral do full blob (colony-look) or just 4-direction side matching?
- Add a Terrain Set to `terrain_tileset.tres` in the editor
- Assign terrain patterns to each atlas tile variant
- Replace `terrain_layer.set_cell()` in `ChunkManager._apply_chunk()` with
  `terrain_layer.set_cells_terrain_connect()` - Godot handles variant selection
  and chunk border refresh automatically

**Chunk border handling:** Godot's terrain API updates border tiles of adjacent
chunks automatically when a new chunk is applied. No extra code needed.

**Effort:** Mostly asset work (sprite sheets). Code change is ~5 lines in chunk_manager.gd.

---

### Inventory + Item Data Model
Prerequisite for: block placing, crafting, drops, chests, hotbar.

- [x] Item registry (similar to TileProperties - string name + stable int ID)
- [x] Stack-based slot system
- [x] Serialization for network sync + save files

---

### World Persistence (Save / Load)
ChunkData already has `base_tiles` + `modifications` separately - the hard part is done.

- Define save file format (one file per chunk, or one big world file)
- `FileAccess` for reading/writing
- Decide: save on chunk unload, or periodic + on quit

---

## Gameplay Features

- [x] Block placing (right click)
- [x] Hotbar UI
- [ ] More tile types (seaweed, obsidian, treasure blocks, ...)
- [ ] Biomes (cold/warm/deep zones with different generation parameters)
- [ ] Fish / passive sea creatures
- [ ] Enemies
- [ ] Crafting
- [ ] Chests / loot
- [ ] Water currents (push player in a direction)

---

## Visual / Feel

- [ ] Dynamic lighting (`CanvasLight2D`) - headlamp, glowing coral, bioluminescence
- [ ] Light rays from above (shader effect)
- [ ] Animated tiles (AnimatedSprite2D or animated atlas - waving seaweed, pulsing coral)
- [ ] Better bubble particles (GPUParticles2D instead of CPUParticles2D)
- [ ] Minimap (SubViewport rendering a zoomed-out world view)
- [ ] Player animation (swim cycle, idle)
- [ ] Background parallax layers (distant rock formations, fog)

---

## Technical / Infrastructure

- [ ] `MultiplayerSynchronizer` for property sync (health, state) - complement to spawner
- [ ] Async chunk generation (ResourceLoader threaded load, no frame spikes)
- [ ] TileSet custom data layers (per-tile metadata: light emission, spawn weight, biome tag)
- [ ] Sound (AudioStreamPlayer, positional AudioStreamPlayer2D)
- [ ] Navigation mesh for enemy pathfinding (NavigationRegion2D + NavigationAgent2D)
