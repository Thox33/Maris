# World Prop Break Visual Occlusion

Implement the next cleanup step on top of the current uncommitted tree/world-prop
worktree state. Do not restart from scratch. Build on the existing world-prop tree
implementation that is already present in the repo.

Use the accepted direction in
[`docs/plans/world_prop_rendering_plan.md`](../../docs/plans/world_prop_rendering_plan.md)
as the rendering baseline: world props are node-based visuals anchored at the feet
and should occlude/sort like the actual prop sprite, not like a detached screen-space
overlay.

## Target behavior

Adjust breaking feedback for world props so the break/crack animation behaves like
part of the prop visual itself:

- the break animation must cover the full visible object area that belongs to the
  broken prop, not only a single tile-sized cell
- for tall props such as trees, the feedback should span all tiles visually occupied
  by that prop sprite
- the feedback must be drawn on the prop sprite / prop visual path itself so it is
  occluded exactly like the sprite
- if part of the tree is hidden behind another sprite or actor due to y-sorting /
  overlap, the break animation must be hidden in the same way
- the change must preserve the current authoritative break flow:
  - hit resolution
  - break identity / foot-cell mutation
  - drops
  - coral and tile behavior unless an equivalent world-prop improvement is needed

## Constraints

- Follow `CLAUDE.md` and `.ai/context/repo_rules.md`
- Keep the change set focused on break-visual rendering / occlusion behavior for the
  existing world-prop path
- No new special-case tree architecture
- Prefer improving the shared prop break-visual path so coral and trees stay on one
  model where practical
- No unrelated refactors

## Important verification points

- tree breaking remains targetable from canopy hits as already implemented
- break feedback clearly shows which prop is being broken
- feedback is attached to the prop visual path rather than a detached overlay that
  ignores occlusion
- tall props show feedback across their full visible sprite extent
- the existing coral world-prop path is not regressed
- tile and structure break visuals still behave coherently

## Expected outcome

Leave the repo in a state where world-prop breaking feedback is visually attached to
the prop being broken, spans the prop's occupied sprite extent, and follows the same
occlusion / y-sort behavior as the prop sprite itself.
