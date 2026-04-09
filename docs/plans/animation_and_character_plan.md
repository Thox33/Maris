# Character + Animation Plan

See also:

- [`../index.md`](../index.md)
- [`../architecture/actor_model.md`](../architecture/actor_model.md)
- [`../architecture/overview.md`](../architecture/overview.md)
- [`../systems/base_character_art_direction.md`](../systems/base_character_art_direction.md)
- [`../systems/character_pipeline.md`](../systems/character_pipeline.md)

Status: 2026-04-06

## Progress Snapshot

The project has completed the technical groundwork and locked the visual direction.

Completed so far:

- documentation is now split into `architecture`, `systems`, `plans`, and `decisions`
- the reusable actor baseline is documented in [`../architecture/actor_model.md`](../architecture/actor_model.md)
- the humanoid player pipeline is documented in [`../systems/character_pipeline.md`](../systems/character_pipeline.md)
- the current player runtime exposes actor-facing state: `facing`, `locomotion_state`, side-view mirroring
- the player scene uses `VisualRoot -> HumanoidVisual` with layered parts
- character appearance uses structured IDs

Important current status:

- the current `HumanoidVisual` uses `Polygon2D` placeholder parts — it is a structural scaffold only
- it needs to be rebuilt with `AnimatedSprite2D` per body part once V1 sprites are ready
- placeholder PNG sprites will be generated first to validate the animation system before real art is produced

Current focus:

- rebuild `HumanoidVisual` to accept PNG-based `AnimatedSprite2D` parts
- validate the animation pipeline with generated placeholder sprites
- then produce real V1 art via ComfyUI

## Goal

Before we invest seriously in animation work, we need a clearer visual direction for the player character.
The current character is functional, but it is not yet strong enough as a foundation for future idle, walk, use, or combat animations.

So the next steps should be:

1. define the character design direction first
2. build a clean sprite and layer structure second
3. implement the first small character and world FX animations after that

## Character Design Direction

### Core idea

A Terraria-inspired direction makes sense as a reference, but for this project it should be much more reduced for now:

- one body type only
- slightly larger head
- compact chibi look
- clear, readable silhouette
- a small set of configurable visual options

This is a good middle ground:

- more charm and identity than the current character
- much cheaper than a deep modular character system
- still expandable later

### Why this direction fits

- The game benefits from highly readable characters at small sprite size and gameplay scale.
- A larger head helps with expression, hairstyles, helmets, and later facial detail.
- A compact body is easier to animate cleanly than a more realistic proportion style.
- A single body type keeps production and sync complexity much lower.

### What not to do yet

Do not plan these for now:

- multiple body shapes
- a deep paperdoll system with many equipment layers
- too many cosmetic slots
- expensive 8-direction sprite sets

For the first solid version, this is enough:

- one base body
- configurable head, hair, skin, and outfit colors
- 3 facing directions for rendering
- mirrored side view for left

## Target Shape For Character V1

### Visual traits

- chibi proportions
- slightly oversized head
- short torso
- clear arms and legs, but not too thin
- strong readability against underwater backgrounds

### V1 customization

- skin color
- hairstyle
- hair color
- upper clothing color
- lower clothing color

Optional later:

- eye color
- accessory slot
- helmet / headgear
- back slot

### Direction model

V1 uses a single rendered direction:

- `side` (right-facing)
- mirrored `side` for left-facing

Up and down views are not part of V1. This is the same approach used by Terraria and Forager. For an underwater sandbox at chibi scale it is fully sufficient and dramatically reduces art production scope.

## Technical Character Structure

The technical layer target is documented in [`../systems/character_pipeline.md`](../systems/character_pipeline.md).

For V1, the important points are:

- keep gameplay and visuals separate
- the humanoid visual uses three layers: `Body`, `Hair`, and `Face`
- `Body` and `Hair` are silhouette sprites — color is applied via `modulate`, not baked into art
- `Face` is a separate detailed PNG placed on top of the body — it carries expression detail and is not recolored
- prepare later customization and held items without turning V1 into a full paperdoll system

## Animation Strategy

### Core principle

In multiplayer, animations should be derived locally from gameplay state whenever possible.
The server should not synchronize individual animation frames. It should only synchronize the gameplay-relevant state, such as:

- position
- movement direction
- active action
- hit / damage events

Clients decide locally which animation should play based on that state.

### Three animation classes

#### 1. Character animation

Examples:

- idle
- swim / move
- use
- hurt

#### 2. World FX

Examples:

- small fire
- furnace glow
- smoke
- sparks

These effects should be built as separate scenes, not as pure tile animation.

#### 3. Ambient motion

Examples:

- subtle bobbing for item drops
- gentle sway for plants
- pulsing lights

These motions can often be handled with tweens, shaders, or small script-driven offsets.

## Implementation Order

## Phase 1: Lock down character design — COMPLETE

The visual direction for V1 is locked. See [`../systems/base_character_art_direction.md`](../systems/base_character_art_direction.md).

Decisions made:

- chibi proportions, oversized head, compact body
- side-view only with mirroring for left-facing
- `16x24` frame size
- silhouette-based sprites with modulate for color
- face as a separate PNG layer on the head
- one hairstyle for V1

## Phase 2: Prepare the character sprite pipeline

Goal:
Rebuild `HumanoidVisual` to accept PNG-based sprites and validate the animation system with placeholder art before real ComfyUI-generated assets are produced.

Tasks:

- rebuild `HumanoidVisual` to use one `AnimatedSprite2D` per body part
- define `SpriteFrames` for each part: two animations (`idle`, `walk`), two frames each
- add a `Face` node (`Sprite2D`) on the head for expression detail
- generate placeholder PNG sprites in Godot to verify layout, scaling, and animation
- color customization via `modulate` on each part's `AnimatedSprite2D`

Sprite production approach:

- `Body` is a full-body silhouette sprite (torso, arms, legs as one image) — modulate applies body color
- `Hair` is a silhouette sprite — modulate applies hair color
- `Face` is a detailed PNG placed on top of the body — not recolored
- placeholder sprites generated in Godot to verify layout and animation before real art
- final art will be produced via a ComfyUI pipeline (consistent style, whole-character output)
- the same ComfyUI pipeline will later produce world structures such as furnaces and monuments

Result:

- the animation system works before real art is needed
- clear target format for what ComfyUI needs to produce
- color customization works with minimal layers

## Phase 3: First character animations

Goal:
Make the player feel alive with minimal scope.

V1 animations (2 frames each, side-view only):

- `idle` — subtle up/down bob, suggests life without movement
- `walk` — alternating leg position, simple weight shift

Important rules:

- derive animation state from real velocity, not from raw input
- use a small deadzone to avoid flicker at near-zero movement
- `idle` plays when speed is below deadzone, `walk` plays above it
- add `use`, `hurt`, and `attack` later

Result:

- the character immediately feels alive
- simple enough that the entire animation set is 4 frames per body part

## Phase 4: First world FX

Goal:
Make the world feel more alive alongside the character.

Initial candidates:

- small fire
- furnace glow for the large furnace
- smoke or sparks as an optional extra layer

Technical approach:

- one dedicated FX scene per effect
- optionally use `AnimatedSprite2D`
- keep the setup compatible with later light and sound work

Result:

- the first local visual highlights in the world

## Phase 5: Ambient motion

Goal:
Add life to the world without immediately producing many full animation sets.

Possible candidates:

- item drops bob slightly
- plants sway subtly
- certain structures pulse or glow

Result:

- the world feels less static

## Technical Decisions — Locked

### Sprite resolution

- `16x24` frame size per body part
- one frame per cell in the spritesheet
- 4 frames per part: `idle_1`, `idle_2`, `walk_1`, `walk_2` arranged horizontally

### Color strategy

- `Body` and `Hair` are white silhouettes on transparent background
- color is applied at runtime via `AnimatedSprite2D.modulate`
- no color is baked into `Body` or `Hair` sprites
- `Face` is the exception: it carries real pixel detail and is not recolored

### Direction count

- side-view only, mirrored for left
- no up or down views in V1

### Animation tech

- `AnimatedSprite2D` per body part for character and fire FX
- `SpriteFrames` resource per part with `idle` (2 frames, loop) and `walk` (2 frames, loop)
- subtle world motion via tweens or shaders, not sprite animation

### Art production

- placeholder sprites generated in Godot to validate the system
- final sprites produced via ComfyUI (consistent style, per-part silhouette output)
- same ComfyUI pipeline used later for world structures such as furnaces and monuments

## Risks

- If we build animation before the character redesign, we will likely have to redo a lot of work later.
- If the character remains too visually weak, better animation will only help so much.
- If we build too many customization options too early, production slows down significantly.

## Recommendation

The right order is:

1. redefine the character visually for V1
2. prepare simple customization around that base
3. build `idle` and `move` for the character
4. then add small fire and the first world FX

## Summary

Yes, a simplified Terraria-inspired direction is a strong fit for this project:

- one body type
- larger head
- readable chibi proportions
- simple customization
- expandable later

That gives us a more appealing character faster and a much better foundation for all later animation work.
