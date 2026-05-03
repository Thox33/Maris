# Task: Unify Trees And Structures Under One Static World Object System

## Goal

Replace the current split between:
- chunk-native `WorldProp` objects such as trees and coral
- separately managed multi-tile structures such as furnace, anvil, workbench, and botanical table

with one shared static world object architecture.

The result should make trees and structures part of the same conceptual system:
- one shared definition model
- one shared runtime/object manager path
- one shared occupancy / breaking / hit / visual contract
- one shared chunk-based persistence strategy for static world objects

This is not just a visual refactor. It is a world-content architecture unification.

## Current State

The repo currently has three relevant content paths:

1. top tiles
- still tilemap-based and should remain tilemap-based for this task

2. world props
- trees and coral live in `WorldPropCatalog` / `WorldPropDefinition`
- base prop presence is generated into `ChunkData.prop_base_cells`
- runtime changes are stored in `ChunkData.prop_modifications`
- props are spawned visually through `ChunkManager`

3. structures
- multi-tile structures live in `StructureCatalog` / `StructureDefinition`
- runtime instances are tracked by `StructureManager`
- persistence is currently separate in `structures.json`

There is already an in-progress refactor in the current worktree:
- `StructureDefinition` and `StructureCatalog` were partially refactored toward per-cell structure definitions
- treat those edits as intentional WIP to either integrate cleanly or adjust as needed
- do not discard them blindly

## Target Direction

Introduce a unified static world object model.

Expected shape:
- `WorldObjectDefinition` as the shared definition base
- one catalog path for static world objects
- one runtime manager path for static world objects
- one chunk-based persistence model for static world objects

Trees and structures should differ by data and behavior flags, not by belonging to separate storage/logic architectures.

## Required Outcome

1. Trees and placeable structures use the same static world object definition model.
2. The shared model supports per-cell data.
3. The shared model can express:
   - occupied cells
   - breakable cells
   - collision
   - optional custom collision rects smaller than a full cell
   - visual atlas parts / per-cell visuals
   - hit coverage for tall/overhanging content
4. Runtime gameplay logic for these world objects is centralized:
   - placement validation
   - occupancy checks
   - break target resolution
   - break completion
   - visual spawning / lookup
5. Persistence for static world objects is chunk-based instead of split between props-in-chunk and global `structures.json`.
6. Generated world objects and player-placed world objects can coexist in the same shared architecture.
7. Existing gameplay behavior should remain sensible:
   - trees are still breakable and drop wood
   - stations still place correctly and remain breakable
   - upper decorative structure cells can remain non-occupied where intended

## Persistence Intent

The unified persistence model should be chunk-oriented.

Use the concept of:
- base/generated world objects for a chunk
- chunk-local additions for player-placed objects
- chunk-local removals for generated/base objects that were destroyed
- optional state overrides only if needed

This means:
- a generated tree should not need to be saved as a full instance unless changed
- a cut tree should persist as a removal/diff
- a player-placed furnace should persist as a chunk object addition

Do not keep the long-term architecture split where structures are saved separately in `structures.json`.

## Compatibility Expectations

The implementation may use compatibility wrappers/adapters while migrating, but the architectural end state should be clear:
- avoid forcing every gameplay caller to change at once if a temporary compatibility layer is cleaner
- however, do not leave the old prop-vs-structure split as the real long-term source of truth

Preserve current gameplay integrations where possible:
- item placement
- break visuals
- break drops
- join synchronization
- autosave / load
- player movement slowdown from overlapping world content

## Non-Goals

- do not convert normal top tiles into this new world object system
- do not edit `.ai/*` workflow files as part of the feature
- do not introduce ad hoc temporary orchestration configs

## Review Focus

Reviewer should prioritize:
- whether trees and structures truly moved toward one shared architecture
- whether persistence is now chunk-based for static world objects
- whether the old split remains as accidental duplicated truth
- whether breaking, placement, and occupancy logic stayed coherent
- whether migration compatibility left behind architectural regressions or dead paths
