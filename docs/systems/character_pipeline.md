# Character Pipeline

See also:

- [`../index.md`](../index.md)
- [`../architecture/actor_model.md`](../architecture/actor_model.md)
- [`../architecture/overview.md`](../architecture/overview.md)
- [`base_character_art_direction.md`](base_character_art_direction.md)
- [`../plans/animation_and_character_plan.md`](../plans/animation_and_character_plan.md)

Status: 2026-04-10

## Goal

This document describes the currently implemented humanoid player pipeline.

It covers:

- how character data is represented
- how actor state feeds the visuals
- how the current humanoid visual is layered
- how facing, mirroring, and locomotion are selected

This is a system document for the current codebase, not a speculative target doc.

## Scope

This document applies to the humanoid player character pipeline.

It does not define:

- fish or enemy-specific visuals
- combat-specific action animation logic
- deep equipment paperdoll layering
- non-humanoid actor visual layouts

Those actor types should reuse the actor model, but they can provide their own visual implementations.

## Core Model

The player character uses the actor architecture defined in [`../architecture/actor_model.md`](../architecture/actor_model.md).

The relevant runtime chain is:

- `Player` (`CharacterBody2D`)
- actor-facing state exposed by `player.gd`
- `VisualRoot`
- `HumanoidVisual`

In practice:

- gameplay state lives on the player actor side
- the visual side reads that state and presents it locally
- appearance data is owned by gameplay / persistence and applied to the visual

## Ownership Split

### Player Actor

Owns:

- local input
- movement physics
- network authority and remote smoothing
- character identity such as display name
- persistent character appearance data
- held-item state derived from the selected hotbar slot

Does not own:

- sprite-sheet loading
- animation frame selection details
- visual anchor placement for face / held item presentation

### HumanoidVisual

Owns:

- sprite-sheet loading
- animation playback
- left/right mirroring
- face presentation
- held-item anchor placement and rotation
- visual application of currently used appearance values

Does not own:

- movement physics
- networking
- inventory rules
- block interaction
- persistence

## Current Visual Spec

### Frame Size

The current humanoid body sheets use a `16x24` frame size.

This allows a taller, more readable chibi silhouette while keeping the world tile size at `16x16`.

### Direction Set

The humanoid renderer currently uses a side-view presentation only.

- right-facing uses the authored side-view sprites
- left-facing is presented by mirroring `scale.x`
- the actor state still exposes `up`, `side`, and `down` for shared actor vocabulary
- the humanoid player visual does not currently swap to separate up/down sprite sets

### Current Animation Set

The runtime humanoid visual currently plays two looping body animations:

- `idle`
- `run`

The actor locomotion vocabulary remains:

- `idle`
- `move`

`HumanoidVisual` maps actor locomotion `move` to the body animation named `run`.

## Appearance Model

Character appearance is stored as stable string IDs rather than raw `Color` values.

Current stored fields:

- `skin_tone_id`
- `hair_style_id`
- `hair_color_id`
- `top_color_id`
- `bottom_color_id`

These values are persistent character data and are passed into the player actor on spawn.

### Current visual usage

Not every stored field is fully rendered yet.

Current implementation:

- `top_color_id` is applied to the body sprite via `modulate`
- `hair_color_id` is prepared for hair tinting
- `skin_tone_id`, `hair_style_id`, and `bottom_color_id` are already saved and synchronized, but are not yet fully expressed as separate visual layers

This means the persistence model is ahead of the current art depth, which is intentional.

## Current Layering

The current player visual scene is:

```text
Player
|-- CollisionShape2D
|-- VisualRoot
|   `-- HumanoidVisual
|       |-- Body           (AnimatedSprite2D)
|       |-- Hair           (AnimatedSprite2D, currently hidden)
|       |-- Face           (Sprite2D, currently hidden)
|       `-- HeldItemAnchor (Node2D)
|-- OverheadAnchor
|-- OverheadSource
|-- Camera2D
|-- BlockInteraction
|-- UnderwaterEffects
|-- HotbarUI
|-- DebugOverlay
`-- ChatUI
```

Important runtime note:

- the scene still contains `Hair` and `Face` nodes
- the current implementation hides those nodes and builds the visible face dynamically under a runtime `FaceAnchor`
- that runtime face uses separate eye and mouth sprite sheets, not a single static face PNG

## Current Asset Set

The default humanoid profile currently loads:

```text
assets/sprites/characters/humanoid_v1/
  body_idle_side.png
  body_run_side.png
  faces/
    eyes_directions.png
    mouth_expressions.png
```

Current runtime behavior:

- body animation sheets are loaded into `SpriteFrames`
- the eye sheet contains directional eye frames
- the mouth sheet currently provides a simple static mouth region
- `Hair` exists as a reserved layer but is not yet backed by an active runtime sheet in the default profile

## Actor-To-Visual Contract

`HumanoidVisual` renders from a small actor-facing contract:

- `locomotion_state`
- `side_view_mirrored`
- `held_item_id`
- appearance data
- look direction for the face

The player actor also exposes:

- `velocity`
- `facing`
- `active_action`

Those values are part of the broader actor vocabulary even when the current humanoid visual does not yet consume every one of them for sprite selection.

## Facing Rules

The player actor derives facing from real velocity, not raw input.

Current actor behavior:

- strong horizontal motion selects `side`
- strong vertical motion can select `up` or `down`
- when using side view, `side_view_mirrored` stores whether the sprite should be flipped for left-facing presentation

Current humanoid visual behavior:

- body animation selection only uses locomotion and side mirroring
- no separate up/down humanoid sprite set is currently rendered

## Locomotion Rules

Locomotion is derived from real velocity with a deadzone.

Rules:

- below deadzone: `idle`
- above deadzone: `move`
- remote animation should be driven from replicated motion, not raw input

This keeps local and remote presentation consistent.

## Face And Look Direction

The current face layer is driven by look direction:

- the local authority updates look direction from mouse position relative to the player
- that direction is replicated to remote peers alongside movement snapshots
- `HumanoidVisual` maps that direction to an eye-frame index

The face is intentionally lightweight:

- eye direction is dynamic
- the mouth is currently simple and mostly static
- the static `Face` scene node is not the active presentation path

## Held Item Presentation

Held-item visuals are part of the humanoid pipeline already.

Current behavior:

- the actor resolves `held_item_id` from the selected hotbar slot
- `HumanoidVisual` creates a held-item sprite under `HeldItemAnchor`
- anchor position and rotation are driven by `HumanoidVisualProfile`
- item-specific hold scale and grip point come from `ItemProperties`

This is a visual-only layer. Inventory authority remains outside the player visual.

## Networking Rule

Animation frames are not synchronized over the network.

The network synchronizes gameplay-facing state, and each peer derives animation locally from actor state and look direction.

This keeps:

- network overhead low
- remote interpolation clean
- the actor model consistent

## Persistence Rule

Character appearance is persistent character data.

That means:

- it belongs in the character record, not in transient visual-only state
- the save contains appearance IDs
- spawn/setup code passes appearance data into the player actor on creation

## Current Gaps

The current pipeline is functional but intentionally incomplete.

Known follow-ups:

- make use of `skin_tone_id` in a visible layer
- make use of `bottom_color_id` in a visible layer
- activate hair-style-specific rendering instead of a hidden placeholder node
- add action-state animation overrides later if gameplay requires them

## Decision Summary

The current humanoid pipeline is:

- actor-owned gameplay state
- actor-owned persistent appearance IDs
- `16x24` side-view body animation sheets
- local animation selection from locomotion state
- mirrored left-facing side view
- dynamic face presentation from eye / mouth sheets
- one `HeldItemAnchor` node for held-item visuals
- no network-synchronized animation frames

This keeps the player character specific where it should be while preserving reuse at the actor-model level.
