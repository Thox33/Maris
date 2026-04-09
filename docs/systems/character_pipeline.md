# Character Pipeline

See also:

- [`../index.md`](../index.md)
- [`../architecture/actor_model.md`](../architecture/actor_model.md)
- [`../architecture/overview.md`](../architecture/overview.md)
- [`base_character_art_direction.md`](base_character_art_direction.md)
- [`../plans/animation_and_character_plan.md`](../plans/animation_and_character_plan.md)

Status: 2026-04-06

## Goal

This document defines the desired V1 character pipeline for the player character.

It covers:

- how character data is represented
- how actor state feeds the visuals
- how the humanoid visual is layered
- how facing and animation are selected

This is a system document, not a phased plan. It describes the intended structure the codebase should implement.

## Scope

This document applies to the humanoid player character pipeline.

It does not define:

- fish or enemy-specific visuals
- full combat behavior
- equipment paperdoll depth
- non-humanoid actor visual layouts

Those actor types should reuse the actor model, but they can provide their own visual implementations.

## Core Model

The player character uses the actor architecture defined in [`../architecture/actor_model.md`](../architecture/actor_model.md).

The relevant chain is:

- `PlayerActor`
- `ActorVisual`
- `HumanoidVisual`

In practice, that means:

- gameplay state lives on the actor side
- the visual side reads that state and presents it
- appearance data configures the humanoid visual

## Ownership Split

### PlayerActor

Owns:

- local input
- movement physics
- network authority and remote smoothing
- character identity such as display name
- character appearance data as gameplay-owned configuration

Does not own:

- sprite-layer structure
- animation frame selection details
- palette application logic beyond supplying appearance values

### HumanoidVisual

Owns:

- sprite layering
- direction presentation
- animation selection
- mirroring for left-facing side view
- visual application of appearance data

Does not own:

- movement physics
- networking
- inventory logic
- block interaction
- save persistence

## V1 Visual Spec

### Frame Size

The V1 humanoid character uses a `16x24` frame size.

Reasons:

- the current `16x16` player sprite is too constrained for the desired chibi silhouette
- a taller frame allows a larger head and clearer body read
- the world tile size can remain `16x16` without forcing the character sprite to be exactly one tile tall

### Direction Set

The V1 rendered direction is `side` only.

Left-facing presentation is done by mirroring `side` horizontally (`scale.x = -1`).

Up and down views are not part of V1. This matches the approach used by Terraria and Forager and keeps art production scope manageable for solo development.

### Body Shape

The V1 humanoid body rules are:

- one body type only
- chibi proportions
- slightly oversized head
- short torso
- readable arms and legs
- strong silhouette against underwater backgrounds

## V1 Appearance Model

The humanoid appearance model stores small, stable IDs rather than raw colors or free-form values.

V1 appearance fields:

- `skin_tone_id`
- `hair_style_id`
- `hair_color_id`
- `top_color_id`
- `bottom_color_id`

Important rules:

- these values are part of the character's appearance data
- they are actor-owned configuration, not visual-only transient state
- they should be serializable as stable string IDs
- they should not store engine-specific `Color` values directly in saves

## Color Strategy

The V1 color strategy uses silhouette sprites with runtime modulation.

The character has three visual layers:

| Layer | Type | Recolored? |
|-------|------|------------|
| `Body` | full-body silhouette (torso, arms, legs as one image) | yes — via `modulate` |
| `Hair` | hair silhouette | yes — via `modulate` |
| `Face` | detailed pixel art PNG placed on top of body | no |

Rules:

- `Body` and `Hair` sprites are white silhouettes on transparent backgrounds
- color is applied at runtime via `AnimatedSprite2D.modulate`
- each appearance field (`body_color_id`, `hair_color_id`) stores a stable string ID that maps to a predefined `Color`
- no color is baked into `Body` or `Hair` art — all color variants are free at runtime
- `Face` carries eyes, expression detail, and shading — it is not modulated

This makes ComfyUI art production straightforward: generate the full body as a clean silhouette, generate hair as a clean silhouette, generate the face as a detailed image. Color customization requires no additional art files.

## Node Structure

The desired V1 player visual structure is:

```text
PlayerActor
|-- CollisionShape2D
|-- VisualRoot
|   `-- HumanoidVisual
|       |-- Body             (AnimatedSprite2D — full-body silhouette, body color modulate)
|       |-- Hair             (AnimatedSprite2D — hair silhouette, hair color modulate)
|       |-- Face             (Sprite2D — detailed face PNG, not recolored)
|       `-- HeldItemAnchor   (Node2D — anchor for a held item sprite)
|-- OverheadAnchor
|-- OverheadSource
|-- Camera2D
|-- BlockInteraction
|-- UnderwaterEffects
|-- HotbarUI
|-- DebugOverlay
`-- ChatUI
```

Important rules:

- `Body` is a full-body sprite — torso, arms, and legs are one image, not separate parts
- `Body` and `Hair` are white silhouettes — color comes from `modulate`, not from the art
- `Face` is placed on top of `Body` at the head position, using a fixed offset
- `VisualRoot` separates gameplay space from visual presentation
- `HeldItemAnchor` is positioned at the hand area — full equipment logic comes later
- later clothing layers (e.g. separate top/bottom color) can be added as additional `AnimatedSprite2D` nodes under `HumanoidVisual`

## V1 Asset Target

The first humanoid asset target is authored as one fixed base character, side-view only.

V1 rules:

- one body type, one hairstyle, one face
- no separate limb sprites — the body is one full image
- `Body` and `Hair` are white silhouettes on transparent backgrounds
- `Face` is a separate detailed PNG placed on top of the body

Spritesheet format:

- `Body` and `Hair`: 4 frames horizontal — `idle_1 | idle_2 | walk_1 | walk_2`
- frame size: `16x24` per frame
- `Face`: 1–2 frames (neutral, optional blink), used as static `Sprite2D` for V1

Asset naming target:

```text
assets/sprites/characters/humanoid_v1/
  body.png       (4-frame spritesheet, silhouette — whole body)
  hair_01.png    (4-frame spritesheet, silhouette — one hairstyle)
  face_01.png    (1–2 frames, detailed pixel art)
```

This is three files for a complete animated character. Color variants require no additional art. Later additions (e.g. separate clothing layers, alternate hairstyles) follow the same pattern.

## Actor-To-Visual Contract

The visual layer should be able to render correctly from a small shared contract.

The humanoid visual should read:

- `velocity`
- `facing`
- `locomotion_state`
- optional `active_action`
- appearance data
- whether the side view should be mirrored

This contract should stay small and generic enough that other actor visuals can use the same pattern.

## Facing Rules

V1 uses a single facing direction: `side`.

Rules:

- the character always uses the `side` sprite
- left-facing is presented by mirroring `side` horizontally (`scale.x = -1`)
- facing direction is derived from horizontal velocity sign, not from raw input
- when movement is near zero, keep the last known facing direction

## Locomotion Rules

The V1 locomotion states are:

- `idle`
- `move`

These are derived from real velocity with a deadzone.

Rules:

- if the speed is below the movement deadzone, use `idle`
- if the speed is above the movement deadzone, use `move`
- do not switch directly from raw input because that causes incorrect remote animation and visual flicker

The exact deadzone constant can be tuned in code, but the system rule is fixed: locomotion comes from physical motion.

## Animation Rules

The V1 animation set is two animations per sprite:

- `idle` — 2 frames, looping, subtle bob
- `walk` — 2 frames, looping, weight shift

Later actions can extend this with:

- `use`
- `attack`
- `hurt`
- `dead`

Selection order:

- high-priority action states override base locomotion when active
- otherwise play `idle` or `walk` based on `locomotion_state`

## Networking Rule

Animation frames are not synchronized over the network.

The network synchronizes gameplay-relevant state, and each client derives animation locally from actor state.

This is required for:

- clean remote interpolation
- low network overhead
- visual consistency with the actor model

## Persistence Rule

Character appearance is persistent character data.

That means:

- it belongs in the character record, not in transient visual-only state
- the save should contain appearance IDs
- spawn/setup code should pass that appearance data into the player actor on creation

## V1 Non-Goals

These are explicitly out of scope for the first humanoid pipeline:

- multiple body types
- separate per-limb sprites (arms, legs as individual nodes)
- deep paperdoll equipment layering
- up and down view directions
- free-form per-pixel recoloring
- creature visuals sharing the same layered sprite layout as the player

## Decision Summary

The V1 character pipeline is defined as:

- actor-owned gameplay state
- actor-owned persistent appearance IDs
- three visual layers: `Body` (full-body silhouette), `Hair` (silhouette), `Face` (detailed PNG)
- `16x24` frame size
- side-view only with mirrored side-left presentation
- color customization via `AnimatedSprite2D.modulate` on `Body` and `Hair`
- `idle` and `walk` animations, 2 frames each
- one `HeldItemAnchor` node at the hand position
- velocity-derived locomotion and facing
- art produced via ComfyUI pipeline (same pipeline used later for world structures)

This keeps the player character specific where it should be, while preserving reuse at the actor-model level and staying within solo-developer production scope.
