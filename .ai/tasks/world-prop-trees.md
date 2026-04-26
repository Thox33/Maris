# World Prop Trees

Implement the next clean step on the existing world-prop pipeline: trees.

Use the accepted direction in
[`docs/plans/world_prop_rendering_plan.md`](../../docs/plans/world_prop_rendering_plan.md)
as the product and architecture baseline. Trees must be added on top of the
current coral-backed `WorldProp` path, not as a parallel special case.

## Target behavior

Implement trees so they run through the same node-based `WorldProp` runtime path
as coral, with tree-appropriate data and visuals:

- root / depth-sort pivot at the feet
- small collision only at the trunk / base
- large visual height extending upward above the collision footprint
- sway through the shared `vegetation_sway.gdshader` with parameters tuned for
  trees (stable trunk, moving canopy)
- no tree-specific rendering architecture outside the existing world-prop system
- no regression or degradation of the existing coral world-prop behavior

## Scope expectations

Deliver the smallest complete implementation slice that makes trees a real user-
visible part of the current world-prop feature set.

That likely includes:

- extending world-prop definitions / rendering so tall tree visuals can be
  anchored at the feet without introducing a new runtime scene type
- adding one or more concrete tree prop definitions and the required sprite
  assets if they are genuinely missing
- spawning trees through the existing prop generation path where appropriate for
  overworld terrain
- ensuring tree instances use the existing prop placement / save / load /
  replication / breaking / drop infrastructure where that path already applies
- updating docs if the runtime contract or asset/layout expectations changed

## Constraints

- Follow `CLAUDE.md` and `.ai/context/repo_rules.md`
- Keep the change set focused on adding trees to the world-prop pipeline
- No new special-case tree architecture
- No unrelated refactors
- No placeholder assets or TODO-based half-solutions
- If the task is blocked on genuinely missing assets or impossible existing data,
  state that clearly instead of inventing a fake workaround

## Important verification points

- world-prop rendering still uses the prop root as the y-sort pivot
- tall tree visuals are offset upward from the feet rather than colliding across
  their whole canopy
- collision remains limited to the trunk/base area
- tree sway uses the shared vegetation shader with tree-appropriate rigid-base /
  amplitude tuning
- the existing coral prop path still renders and behaves correctly
- generated / loaded chunks can recreate tree props through the same prop layer
- breaking / drops for trees remain coherent with the current authoritative prop
  flow

## Expected outcome

Leave the repo in a state where trees are a clean extension of the existing
world-prop pipeline, consistent with the accepted plan and ready for scoped
review.
