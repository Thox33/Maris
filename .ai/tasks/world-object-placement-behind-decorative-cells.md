# Task: Restore world-object placement behind non-occupied multi-tile visuals

## Goal
Fix the regression where world-object placement (coral, stations, other placeable world objects) is blocked by non-occupied decorative cells of existing multi-tile world objects such as the furnace top row and the upper tiles of botanical_table, anvil, and work_bench.

## Context
The new unified world-object path currently allows top-tile placement behind those decorative cells for normal tiles like sand, but still rejects world-object placement because `WorldObjectManager.can_place_world_object_at()` checks overlap against existing `_hit_cells` instead of only the footprint rules that should actually block placement.

Observed behavior:
- placing sand behind/over the decorative top tiles works
- placing coral or another station at the same cells fails

Expected behavior:
- non-occupied decorative cells should not block placement of other world objects
- occupied/support rules should remain authoritative for actual blocked cells
- break/hit detection for world objects should continue to work

## Suspected code
- `scripts/world/world_object_manager.gd`
- `scripts/main/world_placement_service.gd`
- any affected definition logic in `scripts/world/world_object_definition.gd` / `scripts/world/world_object_catalog.gd`

## Deliverable
Implement the fix through the orchestrator pipeline, preserve intended interaction/break behavior, and verify with headless Godot checks.
