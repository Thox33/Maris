# Task: Keep Cross-Chunk World Objects Alive Via Covered-Chunk Activation

## Goal

Fix the remaining runtime regression in the unified static world object architecture where a multi-cell world object can span multiple chunks but is still owned only by its origin chunk for runtime activation/unload.

Do not solve this by force-loading extra chunks or expanding the effective chunk load radius.

## Problem

Right now a world object can legally cover cells in neighboring chunks, but runtime lifecycle is still anchored to the origin chunk.

That creates the known failure mode:
- a world object overlaps chunk A and chunk B
- chunk A unloads while chunk B stays loaded
- the object is removed even though part of it is still relevant in chunk B

The desired solution is chunk-aware activation/reference tracking, not recursive chunk loading.

## Required Outcome

1. A world object computes and stores the set of chunks it covers.
2. Runtime activation of a world object should remain valid while at least one covered chunk is loaded.
3. Unload should only remove a world object when none of its covered chunks remain loaded.
4. Chunk loading should not automatically load additional neighboring chunks just because an object overlaps them.
5. Existing persistence model should remain chunk-based.

## Architectural Direction

Use a covered-chunk lifecycle model.

Expected behavior:
- world object definitions still compute hit/occupied/break/collision cells in world space
- the manager derives `covered_chunks` from those cells
- the manager tracks which loaded chunks currently reference each object
- object visuals/occupancy remain active while the reference set is non-empty

This is a runtime ownership/lifecycle fix, not a world streaming policy change.

## Constraints

- do not solve this by loading neighboring chunks
- do not revert the unified world object architecture
- do not reintroduce prop-vs-structure split logic
- keep the fix focused on cross-chunk object lifecycle

## Validation

At minimum:
- headless Godot parse / boot checks should pass
- world object runtime registration should no longer be tied only to the origin chunk
- code should clearly show that unload only frees an object when no covered chunk is still loaded

## Review Focus

Reviewer should prioritize:
- whether covered-chunk tracking is actually implemented
- whether the fix avoids force-loading adjacent chunks
- whether object activation/removal is now based on loaded covered chunks instead of only origin-chunk ownership
- whether persistence assumptions still remain coherent
