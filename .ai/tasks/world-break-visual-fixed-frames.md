# Task: Replace Procedural Break Crack Generation With Fixed Central Frame Assets

## Goal

Replace the current procedural runtime crack-texture generation with a fixed,
central crack-frame asset source that is reused consistently for all breakable
world visuals.

This is a direct follow-up to the current break-visual unification work. Keep
the centralized visual pipeline, but change the crack-frame source and rendering
look so the result is visually controlled and matches the same fixed frames
every time.

## Problem To Solve

The current implementation:
- generates the crack texture procedurally at runtime in `BreakVisualService`
- applies it through shader darkening / crack-mask blending
- produces a look that is too dark / muddy on placed world visuals

The desired behavior is:
- fixed crack frames as real asset-backed images
- the same stage images every time
- no unintended general darkening of the underlying placed sprite
- still rendered on the actual world visual so occlusion and y-sort match

## Required Outcome

1. Remove the procedural crack-frame generation as the primary source.
2. Use fixed crack frames from asset-backed image data instead.
3. Keep the crack-frame source centralized in `BreakVisualService`.
4. Keep one shared break-stage application contract for all breakable world visuals.
5. Preserve the current centralized break-visual architecture from the previous run.
6. The result must not make breakable world sprites look generally darker when
   they are merely placed and not currently being damaged.

## Important Direction

Use the existing crack-animation look if it already exists in the repo as a real
asset source.

If no checked-in crack-frame asset exists yet, convert the current established
central crack look into a fixed repo asset as part of this task and then switch
runtime usage to that asset-backed source. Do not keep procedural generation as
the main runtime path.

## Constraints

- Keep `BreakVisualService` as the central owner of break-frame sourcing.
- Do not reintroduce content-type-specific break pipelines.
- Do not fall back to detached overlay logic for some content types and shader
  logic for others.
- Do not keep the current unwanted overall darkening behavior.
- Follow `CLAUDE.md` and `.ai/context/repo_rules.md`.

## Review Focus

Reviewer should prioritize:
- whether runtime crack generation was actually replaced by fixed frame assets
- whether the frame source is still centralized
- whether placed breakable visuals remain visually unchanged until a break stage
  is active
- whether props, tiles, and structures still use the same shared break-visual
  contract
- whether occlusion/y-sort still follows the actual target visual
