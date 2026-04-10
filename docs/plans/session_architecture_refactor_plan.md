# Session Architecture Refactor Plan

See also:

- [`../index.md`](../index.md)
- [`roadmap.md`](roadmap.md)
- [`../architecture/overview.md`](../architecture/overview.md)
- [`../architecture/actor_model.md`](../architecture/actor_model.md)
- [`../decisions/authority_model.md`](../decisions/authority_model.md)

Status: phase 1 landed by 2026-04-10

## Purpose

This document now serves as a short implementation record plus a follow-up list.

It no longer describes `main.gd` as a monolithic pressure point. That was the reason for the refactor, not the current state.

## What Landed

The session scene is now split into dedicated service nodes and `main.gd` acts primarily as a composition root.

Implemented service boundaries:

- `SessionBootstrapService`
- `SessionJoinService`
- `SessionIdentityService`
- `CharacterSetupService`
- `PlayerSpawnService`
- `SessionPersistenceService`
- `WorldDropService`
- `UseAuthorityService`
- `BreakVisualService`
- `InventoryAuthorityService`
- `WorldPlacementService`

Current `main.gd` responsibilities are intentionally thin:

- fetch scene references
- wire service dependencies together
- connect a small number of top-level signals
- forward bootstrap / shutdown into the correct services

## Current Ownership Split

### SessionBootstrapService

Owns:

- selected world activation
- load/create seed flow
- world initialization order
- dedicated-server bootstrap differences

### SessionJoinService

Owns:

- `_client_ready` entrypoint
- join validation
- duplicate-account rejection
- seed handoff to clients

### SessionIdentityService

Owns:

- `peer_id -> account_id`
- `peer_id -> display_name`
- broadcast identity snapshots

### CharacterSetupService

Owns:

- pending character setup state
- character setup UI wiring
- character creation submission

### PlayerSpawnService

Owns:

- spawn payload creation
- save-based spawn restoration
- chunk preload before spawn
- inventory restore handoff
- disconnect cleanup for player runtime

### SessionPersistenceService

Owns:

- autosave orchestration
- world save orchestration
- player save on disconnect
- save on session leave / app quit

### WorldDropService

Owns:

- listening to break events
- mapping break results to drops
- item entity spawn requests

### InventoryManager + child services

Current shape:

- `InventoryManager` is now the RPC bridge and local client sync surface
- `InventoryAuthorityService` owns server-authoritative inventory state and interaction rules
- `WorldPlacementService` owns world / structure occupancy validation for placement

This is already a meaningful narrowing compared to the pre-refactor state.

## What Still Remains

The first follow-up item from this plan has now been addressed as well:

- player-side world references now arrive through explicit setup instead of ad-hoc world lookups
- chunk and structure managers are now configured by the world composition root
- debug and break-visual wiring now receive explicit runtime dependencies instead of reaching into scene paths

### 1. Continue narrowing runtime managers where it pays off

The major god-object problem has been addressed, but there is still room to tighten interfaces:

- keep RPC entrypoints near the rules they own
- keep `InventoryManager` thin
- keep service setup explicit from the composition root

### 2. Add tests for pure rule-heavy logic

Still high-value candidates:

- inventory operations
- save normalization
- chunk serialization
- registry consistency
- structure occupancy validation

### 3. Revisit data-driven content when content breadth grows

`TileProperties`, `ItemProperties`, and `StructureCatalog` are still code-defined. That is acceptable for the current project size, but it should be revisited once content breadth starts increasing significantly.

## Outcome

Phase 1 of the session refactor is effectively complete:

- `main.gd` is no longer the primary owner of session behavior
- join, identity, persistence, and character setup each have a dedicated owner
- item drop rules no longer live in `main.gd`
- session shutdown and autosave have dedicated owners

This file remains in `plans/` because follow-up work still exists, but the original refactor motivation should be treated as completed history rather than current state.
