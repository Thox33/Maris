# Inventory Plan

See also:

- [`../index.md`](../index.md)
- [`../architecture/overview.md`](../architecture/overview.md)

Status: core HUD and host-authoritative interaction loop implemented by 2026-04-10

## Goal

The inventory should behave like an expanded hotbar rather than a separate full-screen inventory mode.

Current design goals remain:

- hotbar always visible
- inventory expands upward above the hotbar
- no global inventory mode that pauses the world
- mouse stays visible
- world interaction should continue while the inventory is open, except when the cursor is actually over blocking UI

Crafting is still out of scope for this document, but the current HUD should remain extensible enough for later chest and crafting panels.

## Current Implemented Shape

The data model is already shared:

- one `Inventory` with `40` slots
- the first `10` slots are the hotbar
- hotbar and main inventory are just two views over the same underlying data
- inventory state remains host-authoritative

Current HUD layout:

```text
closed
  [ 0 ][ 1 ][ 2 ][ 3 ][ 4 ][ 5 ][ 6 ][ 7 ][ 8 ][ 9 ]

open
  [30][31][32][33][34][35][36][37][38][39]
  [20][21][22][23][24][25][26][27][28][29]
  [10][11][12][13][14][15][16][17][18][19]
  [ 0 ][ 1 ][ 2 ][ 3 ][ 4 ][ 5 ][ 6 ][ 7 ][ 8 ][ 9 ]
```

The hotbar stays anchored at the bottom. Opening the inventory currently shows or hides the upper inventory panel; there is not yet a dedicated open/close tween.

## Current UI Structure

The active HUD lives in the player's `HotbarUI` `CanvasLayer`.

Current node shape:

```text
HotbarUI
  Root
    BottomDock
      Stack
        InventoryPanel
          BodyPadding
            BodyGrid
        HotbarPanel
          HotbarPadding
            HotbarRow
```

Slots are created dynamically in code rather than instanced from a separate scene.

## Current Input Model

Implemented controls:

- `E` toggles the inventory panel
- `1` through `0` select hotbar slots
- mouse wheel cycles hotbar slots
- left click performs full pickup / full place behavior
- right click performs `pickup_half` or `place_one`
- `Shift` + left click performs `quick_transfer`
- left-drag with a held stack distributes items evenly across eligible slots

Important correction:

- `Tab` is not currently bound as an inventory toggle in the project input map

## Current World-Interaction Contract

The inventory does not globally block gameplay input.

Current implementation:

- interactive inventory controls are added to a `world_input_blocking_ui` group
- `BlockInteraction` checks `gui_get_hovered_control()` and walks parents for that group
- if the mouse is over blocking inventory UI, world interaction is suppressed
- if the mouse is not over blocking inventory UI, world interaction continues normally

This means:

- clicks on real inventory widgets stay in the UI
- empty space outside the inventory remains usable for the world
- open inventory does not automatically pause or globally lock world interaction

## Current Authority Split

### Inventory

`Inventory` remains a pure data container:

- slot contents
- stack counts
- add / remove / set / serialize behavior

It does not know about:

- UI state
- selected hotbar slot
- networking
- cursor previews

### InventoryManager

`InventoryManager` is now the RPC bridge and local client sync surface.

It owns:

- full inventory sync to clients
- slot delta sync to clients
- held cursor-slot sync to clients
- RPC entrypoints for placement and inventory actions

### InventoryAuthorityService

`InventoryAuthorityService` owns the canonical host-side inventory rules and state.

That includes:

- authoritative player inventories
- authoritative held cursor-slot state
- server-side processing of inventory actions

### WorldPlacementService

`WorldPlacementService` owns host-side placement validation against:

- world occupancy
- structure occupancy
- item placement rules

## Current Interaction Features

Already implemented:

- full inventory sync on join
- per-slot delta sync
- host-authoritative cursor-held slot
- quick transfer
- full pickup / full place
- half pickup / place one
- drag distribution preview and commit
- held-slot preview that follows the mouse

Current visual limitation:

- opening / closing is a visibility toggle, not a polished animated reveal yet

## Remaining Follow-Ups

Still reasonable future work:

- add a proper reveal animation for opening / closing
- add tooltips
- add chest / secondary inventory support
- add crafting-panel integration
- decide later whether to migrate parts of the interaction to native `Control` drag-and-drop hooks

## Decision Summary

The project currently follows one shared-inventory model:

- exactly one player inventory
- hotbar as a permanent sub-view of that inventory
- inventory expanding above the hotbar
- UI only blocking world input where the cursor is actually over blocking controls
- inventory mutations staying host-authoritative

That model is already implemented and should remain the baseline for future chest and crafting extensions.
