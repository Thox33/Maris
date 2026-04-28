# Repo Rules — Overworld Sandbox

Project-specific rules that all AI roles (planner, builder, reviewer) must follow.
These extend `CLAUDE.md` with the concrete patterns that are easy to violate.

## Architecture patterns

### Service layer
- New server-side logic belongs in `scripts/main/<name>_service.gd`.
- Do **not** add logic directly on `Main`, and do **not** turn session-local services into autoloads.
- Services follow the shape: `extends Node`, `setup(deps...)` for dependency injection, per-peer state in `_private` dictionaries.
- Every server-side method starts with a `multiplayer.is_server()` gate (or equivalent authority check).

### Authority model
- Host-authoritative: inventory, placement, chunk mutation, structure mutation, persistence.
- Peer-authoritative (owning peer): movement.
- Client → Host via `rpc_id(1, ...)`. The client never mutates authoritative state directly — not even "optimistically".
- The canonical flow is: **Input → `request_*()` on client → RPC to host → authority service validates → manager mutates → `GameEvents` signal fires.**

### Cross-system communication
- Systems communicate via `GameEvents` signals where possible. New signals document their emitter (`Fired by: ...`) and listener contract.
- Services that need to push state to clients receive `Callable` sync bridges through `setup()`, not direct node references.

### Data classes vs nodes
- `Inventory`, `ChunkData`, `TileProperties`, `GroundTileProperties`, `StructureDefinition` are `RefCounted` — never treat them as nodes, never `add_child` them.
- Logic that operates on them lives in services or managers, not on the data class itself beyond pure helpers.

### Tile / structure registry
- Integer tile IDs in `TileProperties` and `GroundTileProperties` are **permanent**. Never reuse, never renumber, never "clean up" the numbering.
- Top-tile collision authority is `TerrainLayer`. `GroundCollisionLayer` only blocks liquid/void. Visual-only layers must stay visual-only.
- Structures live in `StructureManager` with their own occupancy map — do not encode structures into tile data.

### Persistence
- Player saves are keyed by `account_id` (persistent). Never key persistence by `peer_id` (transient).
- Only chunk *modifications* are written; base terrain regenerates from the seed.
- Writes go through the `.tmp` + rename atomic pattern already used in `SaveManager`.

### Scene / asset workflow
- Prefer `.tres` for editor-owned data, `.gd` for logic.
- Gameplay raster assets are atlas-only: world visuals and item icons belong in the shared atlas files under `assets/tilesets/`.
- Atlas PNGs are the canonical source for gameplay art in this repo.
- Do **not** add standalone structure/icon/preview/source PNGs for the same gameplay art as part of normal feature work.
- Do **not** keep unnecessary duplicate copies of the same image or code. Extend existing assets/helpers unless there is a concrete reason not to.
- Do **not** use scripts to generate, compose, or bake gameplay graphics or atlas content.
- If a task appears to require a standalone gameplay PNG, duplicate raster asset, or graphics-generation script, stop and flag the workflow conflict instead of improvising a new asset path.

## Assets & scope

- **PNG-only for tiles and characters.** No vector graphics (`Polygon2D`, `Line2D`, procedural shape generation) as placeholder or substitute.
- No half-finished / filler solutions. No `TODO: proper asset later`, no stub implementations with "wird später ersetzt".
- If an asset or system is missing for a task: state it explicitly in the response and stop. Do not bridge it with a placeholder.
- Prefer reducing scope over shipping a stub.

## Style

- Communication with the user: German. Code, comments, identifiers, commit messages: English.
- Default: no comments. Only add a comment when the *why* is non-obvious (hidden constraint, subtle invariant, workaround).
- No speculative abstractions, no unrelated refactors bundled into a task.

## Physics layers

| Layer | Name   | Used by                                            |
|-------|--------|----------------------------------------------------|
| 1     | World  | Ground/top collision tiles, structure visuals      |
| 2     | Player | `CharacterBody2D` players                          |
