# Session Architecture Refactor Plan

See also:

- [`../index.md`](../index.md)
- [`README.md`](README.md)
- [`roadmap.md`](roadmap.md)
- [`../architecture/overview.md`](../architecture/overview.md)
- [`../architecture/actor_model.md`](../architecture/actor_model.md)

Status: 2026-04-05

## Goal

Capture the current architectural concerns in one implementation-oriented place and define the next refactor path.

The highest-priority refactor is to split `main.gd` into smaller session services before more gameplay systems are added.

## Why This Needs To Happen Now

The project already has a good foundation:

- host-centered world mutation for chunks, structures, saves, and inventory
- stable ID registries for tiles and items
- useful separation between data objects and runtime managers
- a documented architecture instead of implicit tribal knowledge

The problem is not that the architecture is bad.

The problem is that several central scripts are already accumulating too many responsibilities at once. If this continues, every new feature will become slower to add, harder to test, and riskier to change.

## Current Concerns

### 1. Authority model is not fully aligned with the docs

The architecture docs currently describe host-authoritative player state, including player positions.

In practice, the current player movement path is closer to client-authoritative movement with remote replication and smoothing:

- the player node gives authority to the owning peer
- movement input is processed locally on that peer
- position and velocity are broadcast outward

This may be acceptable for trusted co-op, but it is not the same model.

Required outcome:

- document the current movement model honestly as trusted co-op
- keep world mutation systems explicitly host-authoritative
- move breaking from client-timed completion to host-authoritative item-use damage and cooldown

We should not keep an ambiguous middle state.

### 2. `Main` is taking on too many roles

`scenes/main/main.gd` currently mixes:

- session bootstrap
- world selection and seed loading
- join flow
- account/display identity wiring
- character creation flow
- player spawning
- inventory restore flow
- autosave orchestration
- disconnect save handling
- item drop spawning from world events
- quit/session shutdown handling

This is the clearest architectural pressure point in the project.

### 3. `InventoryManager` is too broad

`scenes/main/inventory_manager.gd` is not only an inventory manager.

It currently owns:

- authoritative inventory state
- held cursor-stack state
- sync RPCs
- placement request handling
- validation against world and structure occupancy
- inventory interaction rules

That is already a full subsystem compressed into one file.

### 4. Runtime systems still depend on hard-coded scene paths

Several systems reach into the scene tree using absolute paths such as:

- `Main/World`
- `Main/InventoryManager`
- `Main/World/DepthSorted/Players`

This makes systems less reusable, less testable, and more fragile if scene composition changes.

### 5. Simulation and rendering are still tightly coupled

The world managers still directly own a lot of visual application work:

- chunk application writes directly into tilemap layers
- structure runtime owns both occupancy state and spawned visuals
- some world setup code mutates asset/runtime render state during initialization

This is acceptable for the current host-as-player setup, but it is not yet a clean base for a stronger dedicated server path or broader world simulation growth.

### 6. Content registries are solid, but still code-bound

`TileProperties`, `ItemProperties`, and `StructureCatalog` are good as central sources of truth, but they are still hard-coded in script.

That is fine while content is small.

It will become expensive once the project adds:

- more biomes
- more structures
- more placeables
- crafting recipes
- loot tables
- AI-related content metadata

### 7. Asset repair logic is happening at runtime

`world_generator.gd` currently diagnoses and fixes tile physics setup during initialization.

That is pragmatic, but architecturally this belongs closer to asset preparation or editor-time validation than to runtime world startup.

### 8. The project needs tests for pure rules before feature count increases

The project already has several rule-heavy areas that can be tested without full scene boot:

- inventory operations
- save normalization
- chunk serialization
- structure footprint and occupancy validation
- item and tile registry consistency

Without that safety net, refactoring the growing managers will stay expensive.

## Refactor Priority Order

1. Split `Main` into session services.
2. Reduce direct scene-path coupling by passing explicit references/context.
3. Narrow `InventoryManager` to inventory concerns and move placement/session concerns outward.
4. Decide and document the intended authority model, then implement host-authoritative item use for breaking.
5. Add tests for pure domain logic.
6. Move content definitions toward data resources when content breadth justifies it.

## Phase 1: Split `Main` Into Session Services

### Target outcome

`main.gd` should become a thin scene coordinator, not the owner of most session behavior.

It should mainly:

- fetch child service nodes
- connect top-level signals
- forward startup/shutdown into dedicated services

### Proposed service split

#### `SessionBootstrapService`

Owns:

- selected world name fallback
- save world activation
- seed load/create flow
- world initialization order
- dedicated-server bootstrap differences

Should not own:

- player join logic
- character UI logic
- save-all orchestration

#### `SessionJoinService`

Owns:

- `_client_ready` entrypoint
- join validation
- account duplication checks
- join rejection flow
- initial seed send to clients

Should not own:

- world saving
- item drops
- UI rendering details

#### `SessionIdentityService`

Owns:

- `peer_id -> account_id`
- `peer_id -> display_name`
- player identity snapshot building
- identity broadcast updates

This keeps identity concerns out of generic networking and out of scene bootstrap.

#### `CharacterSetupService`

Owns:

- pending character setup state
- character setup UI wiring
- character creation submission
- creation-time record writes

This is currently mixed into session orchestration and should become its own boundary.

#### `PlayerSpawnService`

Owns:

- player spawn payload building
- player restoration from save
- chunk preloading before spawn
- inventory creation/restore handoff
- disconnect cleanup for spawned player runtime

Should be the main place where join completion becomes a spawned actor.

#### `SessionPersistenceService`

Owns:

- autosave wiring
- world save orchestration
- player save on disconnect
- save on session leave / app quit

This should become the only service that coordinates session-level persistence timing.

#### `WorldDropService`

Owns:

- listening to world break events
- mapping break results to drops
- item entity spawn requests

This keeps drop consequences out of the core session bootstrap path.

### Main scene after Phase 1

After Phase 1, `main.gd` should mostly act as a composition root for the above services.

That means:

- low branching
- minimal persistence logic
- minimal RPC logic
- no character creation workflow details
- no item-drop rules

## Phase 2: Reduce Scene-Path Coupling

Introduce an explicit session context or injected references for systems that currently look up:

- world
- players container
- inventory manager
- chunk manager
- structure manager

Preferred direction:

- pass references during `_ready()` or setup
- use scene-local wiring from the composition root
- keep autoloads for true global cross-session services only

## Phase 3: Narrow `InventoryManager`

Possible split:

- `InventoryAuthorityService`
- `InventoryRpcBridge`
- `InventoryInteractionRules`
- `WorldPlacementService`

Minimum rule:

`InventoryManager` should not remain the place that knows inventory data, held-slot data, placement validation, world occupancy, and all RPC endpoints together.

## Phase 4: Authority Model Decision

Decision status:

- accepted in [`../decisions/authority_model.md`](../decisions/authority_model.md)

Chosen near-term direction:

- keep movement in trusted co-op mode for now
- keep world mutation, inventory, placement, and saves host-authoritative
- move block and structure breaking to host-authoritative damage, cooldown, and completion

Alternative paths considered during the decision:

### Option A: Trusted co-op

- client-authoritative movement remains acceptable
- host stays authoritative for world mutation and saves
- docs must explicitly state this

### Option B: Stronger host authority

- clients send movement intent
- host simulates and replicates actor state
- more work, but stronger consistency

For the current project scope, Option A remains the pragmatic movement choice, while breaking should still be tightened on the host side through a unified item-use model.

Implementation note:

- the first service boundary should likely be named around item use rather than only breaking
- `UseAuthorityService` is a better long-term name than `BreakAuthorityService` if the same cooldown lane may later cover mining, tool use, and combat

## Refactor Rules

While doing this refactor, keep these rules:

- move responsibilities without changing save format unless necessary
- do not change multiplayer behavior and architecture in the same step unless the step is explicitly about authority
- prefer extracting orchestration first, then tightening interfaces
- keep RPC entrypoints close to the service that owns the rule behind them
- avoid replacing one god-object with several services that still all know everything

## Recommended First Implementation Slice

The first practical slice should be:

1. extract `SessionPersistenceService`
2. extract `WorldDropService`
3. extract `CharacterSetupService`
4. extract `SessionIdentityService`
5. extract `SessionJoinService` and `PlayerSpawnService`
6. reduce `main.gd` to composition and top-level wiring

Reason:

- this reduces `main.gd` quickly
- it has low save-format risk
- it keeps multiplayer behavior mostly stable
- it creates clean boundaries before touching inventory or movement authority

## Definition Of Done For Phase 1

Phase 1 is done when:

- `main.gd` is no longer one of the largest behavioral files in the project
- join, identity, persistence, and character setup each have their own owner
- item drop rules are not implemented in `main.gd`
- session shutdown and autosave have a single dedicated owner
- the responsibilities of each service are documented in one place

## Follow-Up Docs

Once Phase 1 lands, update:

- [`../architecture/overview.md`](../architecture/overview.md)
- [`../architecture/actor_model.md`](../architecture/actor_model.md) if actor/session boundaries change
- [`roadmap.md`](roadmap.md)

The authority decision is now explicit. Update the decision record if the project later changes movement authority.
