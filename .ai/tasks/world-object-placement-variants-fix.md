# Task: Restore Placement Variant Resolution In Unified World Object Placement

## Goal

Fix only the reviewer finding about placement variants in the unified world object architecture.

Do not address the separate reviewer concern about chunk-crossing world object placement in this task.

## Problem

After the world object unification, the placement path no longer resolves `placement_variants` when a player places a world object.

This regressed old behavior where props such as coral used randomized placement variants.

The reviewer specifically identified:
- `WorldObjectCatalog.resolve_placement_object_id()` still exists
- `WorldObjectManager.place_world_object()` does not use it
- placed objects therefore always use the base object id instead of resolving a placement variant first

## Required Outcome

1. `WorldObjectManager.place_world_object()` resolves the final placed object id through `WorldObjectCatalog.resolve_placement_object_id()`.
2. Validation, persistence, runtime registration, and sync should all use the resolved final id.
3. Existing unified world object architecture stays intact.
4. No unrelated architecture changes.

## Constraints

- do not address the chunk-boundary placement finding in this task
- keep the world object unification in place
- make the fix minimal

## Validation

At minimum:
- headless Godot parse / boot checks should still pass
- the placement path should clearly use the resolved object id before storing or syncing

## Review Focus

Reviewer should prioritize:
- whether `placement_variants` are restored for placed world objects
- whether the resolved id is consistently used across validation, save data, and sync
- whether the fix stayed minimal and did not reopen the old prop-vs-structure split
