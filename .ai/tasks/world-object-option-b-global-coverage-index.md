# Task: Replace origin-bound covered-chunk activation with a global world-object coverage index

## Goal
Implement the Option-B direction for static world objects: activation and lookup must no longer depend on the origin chunk being loaded first. Any loaded chunk that is covered by a world object's world-space footprint must be able to activate and reference that object.

## Problem
The current covered-chunk approach is lifecycle-only and origin-bound:
- `ChunkData` persists world objects only in their origin chunk
- `WorldObjectManager.apply_chunk_objects()` only registers objects that exist in the just-loaded chunk's effective object list
- `_add_existing_chunk_references()` can only attach already-active runtime objects
- `_sync_place_world_object()` on clients only materializes the object if the local origin chunk is loaded

As a result, cross-chunk objects fail when a covered chunk is loaded before the origin chunk, and clients can miss freshly placed multi-chunk objects.

## Target architecture
Use a global spatial/coverage index for static world objects.
- World objects remain canonical by `object_id + world origin`
- Activation should come from querying objects whose covered world cells/chunks intersect a loaded chunk
- Runtime activation and client replication must work even if the local origin chunk is not loaded
- Persistence may remain chunk-based if that stays pragmatic, but runtime lookup must not be origin-load dependent

## Constraints
- Keep the unified world-object model
- Do not reintroduce separate prop/structure runtime systems
- Do not force-load neighboring chunks as a workaround
- Preserve placement, breaking, occupancy, hit detection, slowdown, and save behavior
- Keep host-authoritative mutation rules intact

## Likely files
- `scripts/world/world_object_manager.gd`
- `scripts/world/chunk_data.gd`
- `scripts/world/chunk_manager.gd`
- `scripts/autoload/save_manager.gd`
- any sync/load call sites touched by the activation model

## Deliverable
Implement the global coverage-index approach through the orchestrator pipeline, verify with reviewer pass if possible, and run local headless checks afterward.
