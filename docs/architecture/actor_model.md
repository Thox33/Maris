# Actor Model

See also:

- [`../index.md`](../index.md)
- [`overview.md`](overview.md)
- [`../systems/character_pipeline.md`](../systems/character_pipeline.md)
- [`../plans/animation_and_character_plan.md`](../plans/animation_and_character_plan.md)

Status: 2026-04-06

## Goal

The player should not be the architectural baseline for living entities.

The shared baseline is `Actor`.

`PlayerActor` is one specialization of that model, alongside future actor types such as:

- `FishActor`
- `EnemyActor`
- `NpcActor`

This keeps movement, state handling, overhead UI, health, and animation state derivation reusable across multiple entity types without forcing all visuals to look the same.

## Terminology

- `Entity`
  - any object that exists in the world
- `Actor`
  - an entity with movement and gameplay state
- `ActorVisual`
  - the visual representation of an actor
- `PlayerActor`
  - an actor controlled by player input
- `CreatureActor`
  - an actor controlled by AI or scripted behavior
- `HumanoidVisual`
  - the first concrete `ActorVisual`, used for the player character

Important distinction:

- not every `CharacterBody2D` is an actor
- an item drop may use `CharacterBody2D` for physics, but it is not an `Actor`

## Responsibilities

### Actor

Shared runtime responsibilities:

- position and velocity state
- facing direction
- locomotion state
- health and optional mana
- generic status/action state
- overhead anchor and overhead data source

The actor layer should not own:

- sprite-layer specifics such as head, hair, tail, fins
- player-only input handling
- AI-specific decision making
- save-format details for one concrete actor type

### ActorVisual

Visual responsibilities:

- read actor state
- choose facing presentation
- choose animation
- manage sprite mirroring where applicable
- manage visual layers for one concrete visual style

The visual layer should not own:

- physics
- networking
- inventory logic
- world interaction logic

### PlayerActor

Player-specific responsibilities:

- local input
- camera ownership
- inventory and block interaction wiring
- multiplayer authority behavior and remote smoothing
- client-side interaction feedback that may sit in front of host-authoritative world mutation

Current authority note:

- movement currently remains owning-peer-authoritative for trusted co-op
- world interaction outcomes such as placement, inventory mutation, and target breaking should be treated separately from movement authority

### CreatureActor

Future creature-specific responsibilities:

- AI behavior
- steering and navigation
- aggro, flee, patrol, or scripted behavior

## Shared Actor State Vocabulary

All actor types should expose the same small core state language where it makes sense.

### Facing

The shared facing vocabulary is:

- `down`
- `side`
- `up`

`side` may be mirrored visually for left-facing presentation.

V1 implementation note: the humanoid player character only uses `side` in V1. `up` and `down` are reserved for future use or other actor types (e.g. fish, enemies).

### Locomotion

For V1, the shared locomotion set is:

- `idle`
- `move`

### Optional Action State

This can expand later, but the common vocabulary should aim toward:

- `none`
- `use`
- `attack`
- `hurt`
- `dead`

Not every actor type needs every action immediately, but the terms should remain consistent across the project.

## Shared Data Surface

The actor base should provide at least:

- `velocity: Vector2`
- `display_name: String`
- `facing`
- `locomotion_state`
- `health_current: float`
- `health_max: float`
- optional `mana_current: float`
- optional `mana_max: float`
- optional `active_action`

Animation should be derived locally from these actor-facing values whenever possible.

## Node Structure

The target structure for actor-based units is:

```text
Actor
|-- CollisionShape2D
|-- VisualRoot
|   `-- ActorVisual
|-- OverheadAnchor
`-- OverheadSource
```

The target structure for the player is:

```text
PlayerActor
|-- CollisionShape2D
|-- VisualRoot
|   `-- HumanoidVisual
|-- OverheadAnchor
|-- OverheadSource
|-- Camera2D
|-- BlockInteraction
|-- UnderwaterEffects
|-- HotbarUI
|-- DebugOverlay
`-- ChatUI
```

This keeps gameplay and visuals separated while still allowing concrete actor types to attach their own specialized components.

## Visual Reuse Rule

Actors share gameplay structure, not necessarily sprite structure.

That means:

- a humanoid player can use body, head, and hair layers
- a fish can use body, fin, and tail layers
- both can still share the same actor state concepts such as `idle`, `move`, `hurt`, and `facing`

This is the key rule that avoids a bad abstraction.

## Implication For Character Work

The current character and animation work should build on the actor model rather than on a player-only one.

That means:

- the player becomes a specialized actor
- the humanoid character visuals become one concrete actor visual implementation
- animation state should be derived from actor state, not hardwired directly into networking or physics code

## Decision

For this project, `Actor` is the reusable gameplay baseline for living and mobile units.

`PlayerActor` is a specialization of `Actor`, not the other way around.
