# Task: Unify Break Visual Rendering Across All Breakable World Content

## Goal

Refactor the current break-visual implementation into one central system that behaves the same for all breakable world content, instead of having separate rendering paths for props versus normal tiles.

This task is explicitly about **centralization**:
- one central break-state flow
- one central break-frame source
- one central rendering contract
- one consistent occlusion rule
- no content-type-specific special handling for trees, coral, stone, sand, or future breakable world content

## Required Outcome

The final behavior must be:

1. All breakable world content uses the same central break-stage and break-frame logic.
2. The break animation is rendered on the actual visual that represents the thing being broken.
3. If that visual is partially or fully occluded by other world content or actors, the break animation is occluded in exactly the same way.
4. The implementation must not branch into separate long-term architectures like "props use sprite cracks, tiles use overlay cracks".
5. The existing world-prop pipeline must not regress.

## Architectural Direction

The intended direction is a **single break-visual infrastructure** with a shared visual contract.

That means:
- `UseAuthorityService` remains the authoritative source for damaged-target state and break progression.
- `BreakVisualService` remains the central orchestrator for break visuals.
- Break frames remain centrally owned and generated in one place only.
- Rendering of the crack state should happen through a common visual application path that works for every breakable world visual.

Do **not** solve this by adding more per-content exceptions.

## Concrete Technical Targets

1. Introduce one central break-visual application contract for world visuals.
   Every breakable rendered world object should expose the same small API for applying and clearing break state.
   Example shape:
   - `apply_break_visual(stage, crack_texture)`
   - `clear_break_visual()`

2. Move normal breakable tiles onto the same visual contract instead of keeping the old detached overlay path.
   The result must be that sand, stone, coral, trees, and future breakable content all receive break visuals through the same central mechanism.

3. Keep break-frame generation centralized.
   There must be one authoritative break-frame source.
   Do not maintain different crack-frame looks for different content types unless that is explicitly part of a future content feature.

4. Make occlusion come from the actual render object.
   Break visuals must be drawn on the same visual node/material/sprite path as the broken object itself, so occlusion and y-sort naturally match.
   Detached free-floating overlay rendering should not remain the default architecture.

5. Preserve authoritative gameplay flow.
   The canonical path must stay:
   input -> request/RPC -> authority service -> manager mutation -> visual update
   No client-side optimistic mutation shortcuts.

6. Preserve and audit all current breakable categories.
   The final implementation must behave consistently for:
   - normal terrain/top tiles such as sand and stone
   - world props such as coral and trees
   - existing breakable structures if they participate in the same visual contract, or otherwise document the remaining boundary explicitly

## Constraints

- No `.ai/*` repo changes except task/run artifacts needed for this run.
- No new special architecture just for trees or props.
- No partial "stone/sand later" outcome.
- No visual regression where only some breakable content uses sprite-bound cracks and the rest still uses detached overlays.

## Review Focus

Reviewer should prioritize:
- whether the implementation is truly centralized instead of split by content type
- whether all breakable world content now follows the same break-visual path
- whether break occlusion follows the actual render object for all supported breakable content
- whether the shared crack-frame source remains centralized
- whether any old overlay-only path still survives as a hidden fallback for some content types
