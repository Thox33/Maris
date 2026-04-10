# Character + Animation Plan

See also:

- [`../index.md`](../index.md)
- [`../architecture/actor_model.md`](../architecture/actor_model.md)
- [`../architecture/overview.md`](../architecture/overview.md)
- [`../systems/base_character_art_direction.md`](../systems/base_character_art_direction.md)
- [`../systems/character_pipeline.md`](../systems/character_pipeline.md)

Status: 2026-04-10

## Purpose

This plan tracks the remaining character and animation follow-up work after the first humanoid pipeline landed.

It is no longer a "build the entire character system from scratch" plan. The runtime pipeline already exists and this document now focuses on the remaining gaps and polish work.

## Current Baseline

Already implemented:

- actor-facing player state for locomotion, facing vocabulary, side-view mirroring, and held item state
- `VisualRoot -> HumanoidVisual` player scene structure
- PNG-driven body animation sheets for `idle` and `run`
- dynamic face presentation from eye and mouth sprite sheets
- held item anchor and item-specific grip / rotation rules
- persistent appearance IDs in the character record
- host / join / spawn flow that passes appearance data into the player actor

Current limitations:

- the humanoid renderer still uses side-view presentation only
- stored appearance fields are ahead of the visible art depth
- `Hair` exists structurally but is not yet an active visible layer in the default profile
- action states such as `use`, `hurt`, and `attack` do not yet override the base locomotion animations

## Remaining Work

### Phase 1: Finish the visible V1 appearance layer

Goal:
Make the stored appearance model show up more honestly in the runtime visuals.

Tasks:

- decide whether V1 should keep a body-only visible presentation or activate a dedicated hair layer now
- make visible use of `skin_tone_id`
- make visible use of `bottom_color_id`
- wire `hair_style_id` into real asset selection once more than one style exists
- remove any leftover temporary reference art that is no longer part of the active runtime path

Done when:

- the visible player presentation matches the saved appearance model more closely
- the docs no longer need to describe appearance fields as "stored but not yet rendered"

### Phase 2: Add the first action-state animation overrides

Goal:
Move beyond locomotion-only animation without rebuilding the actor model.

Candidates:

- `use`
- `hurt`
- `attack`

Rules:

- action animations should still be derived locally from gameplay state
- network sync should continue to send gameplay-facing state, not raw animation frame indices
- the locomotion baseline should remain the fallback when no action override is active

### Phase 3: Improve facial life and readability

Goal:
Keep the current lightweight face system but make it feel less static.

Candidates:

- blink timing
- simple mouth-state switching
- optional expression hooks for chat / hurt / use states

This should stay lightweight. V1 does not need a deep portrait-grade facial system.

### Phase 4: Expand world-adjacent animation polish

Goal:
Continue improving "alive world" perception around the player pipeline.

Current baseline already exists:

- vegetation sway shader
- underwater screen effect
- break particles
- floating item motion

Good follow-up candidates:

- stronger structure-specific FX
- additional ambient world motion
- more purposeful local highlight effects near interactions

## Implementation Order

Recommended order:

1. finish visible use of the current appearance fields
2. add one action-state override, preferably `use`
3. add lightweight facial polish such as blink support
4. expand world-adjacent animation polish only after the player baseline feels solid

## Non-Goals For This Plan

These are intentionally not part of the near-term character follow-up:

- multiple body types
- full paperdoll equipment layering
- eight-direction humanoid sprite sets
- network-synchronized animation frames
- a large bespoke facial rig

## Summary

The first character pipeline is already in place.

The remaining work is now about finishing the visible appearance layer, adding a small number of action-state animations, and continuing polish without expanding scope into a full modular character system too early.
