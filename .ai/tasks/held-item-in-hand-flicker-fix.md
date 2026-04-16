# Task: Fix transient held-item flicker during cursor pickup

## Context

The held-item-in-hand feature is mostly implemented and docs were updated.
The latest reviewer pass found one remaining low-severity issue in the local authority path:

- `scenes/player/player.gd:353`
- `scripts/main/inventory_authority_service.gd:171`

When the player picks up an item from the currently selected hotbar slot into the mouse cursor, `local_slot_changed` fires before `local_held_slot_changed`.
That means `_on_local_inventory_slot_changed()` can refresh too early and briefly replicate `held_item_id = NONE` before the held-slot update arrives.
The result is a transient hand-visual flicker and possible short remote desync.

## Goal

Keep the intended feature behavior:

- if the cursor is holding an item, the player hand should show that item
- otherwise the hand should show the selected hotbar item
- remote peers must see the same replicated held-item state as the owner

But eliminate the transient flicker/desync caused by refreshing from `local_slot_changed` too early.

## Constraints

- Preserve the current replicated source-of-truth approach in `Player`
- Do not reintroduce a local-only visual override in `HumanoidVisual`
- Keep the fix as small and targeted as possible
- Update docs only if the externally visible behavior or documented flow changes
- Run the relevant Godot validation/check command after the change

## Suggested direction

The simplest acceptable fix is likely to stop refreshing the hand state from `local_slot_changed` for the selected hotbar slot and rely on:

- `local_held_slot_changed`
- `local_inventory_synced`
- the existing `_process()` refresh path

If you find a better minimal fix, use it, but avoid broad refactors.

## Deliverable

Make the code change, update docs only if needed, and summarize:

1. what changed
2. whether docs changed
3. what validation command you ran and whether it passed
