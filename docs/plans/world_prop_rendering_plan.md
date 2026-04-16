# World Prop Rendering Plan

See also:

- [`../index.md`](../index.md)
- [`roadmap.md`](roadmap.md)
- [`../architecture/overview.md`](../architecture/overview.md)

Status: 2026-04-16

## Purpose

Define a clean rendering and collision direction for world objects such as coral,
trees, bushes, kelp, and similar environment props that:

- must depth-sort against actors by their feet
- may only collide near their base
- may visually extend above the collision area
- may sway in the wind/current

This plan exists because the current world rendering path mixes several
approaches:

- flat or cheap visuals in `TileMapLayer`
- node-based block occluders and tall structures
- coral rendered as a sway-decor tile in a dedicated depth-sorted `DecorLayer`

That split was practical in the short term, but it now creates different
occlusion behavior for content that should feel visually similar.

## Problem Summary

Current behavior is inconsistent:

- sand and stone top tiles already use node-based world visuals and therefore
  sort against the player using an explicit foot position
- tall structures such as the furnace also use node-based visuals with a clear
  root position and therefore sort correctly
- coral is the exception: it is rendered through `DecorLayer` as a
  `TileMapLayer` decor tile with sway shader material

As a result, coral does not behave like a prop with a real foot pivot. It
behaves like a depth-sorted tile. This is good for cheap bulk rendering, but it
is the wrong abstraction for objects that should act like trees or vegetation
props.

## Recommended Direction

Introduce a unified **world prop** rendering path for any world object that has
all or most of the following traits:

- explicit foot pivot for depth sorting
- partial collision only near the base
- visual height extending well above the base
- optional sway animation

Coral should move to this system first. Trees should be designed directly on top
of the same system instead of creating another separate path later.

## Render Categories

The world should use three rendering categories:

### 1. TileMap Terrain

Use `TileMapLayer` for:

- ground tiles
- liquid tiles
- flat top-layer visuals
- any cheap decor where precise actor occlusion is not important

This remains the efficient bulk-rendering path.

### 2. World Props

Use node-based props for:

- coral
- trees
- bushes with collision at the base
- kelp, reeds, mushrooms, large flowers, and similar future content

A world prop is the correct abstraction when the object should visually behave
like an entity anchored at the feet, not like a tile cell.

### 3. Large Structures

Use node-based multi-part visuals for:

- furnace-like placeables
- tall stone formations
- future large crafted stations or monuments

Large structures may share infrastructure with world props, but they remain a
distinct content category because they often have multi-part visuals, different
interaction rules, or larger collision footprints.

## Target World Prop Model

Each world prop instance should be represented by a dedicated scene rooted at
its foot position.

Recommended shape:

- `Node2D` root at the foot pivot
- `Sprite2D` or small sprite subtree for the visible art
- `StaticBody2D`
- one or more `CollisionShape2D` nodes only around the trunk/base/foot area
- optional markers for drops, interaction points, or future effects

Important invariant:

- the prop root position is the depth-sort pivot
- the sprite is offset upward from that pivot
- collision is defined independently from visual height

This matches how actors and tall structures already need to behave.

## Sway Strategy

The current coral sway shader should not remain conceptually tied to
`DecorLayer`. It should become a reusable prop shader.

Recommended direction:

- rename or treat the current vegetation shader as a general foliage sway shader
- apply it directly to prop sprites instead of only to a `TileMapLayer`
- expose parameters that make it usable for both coral and trees

Recommended shader parameters:

- sway amplitude
- sway speed
- phase offset or world-space seed
- rigid base height in pixels
- optional noise or secondary motion amount

This allows:

- coral to sway starting close to the base
- trees to keep the trunk mostly rigid while the upper canopy moves
- future vegetation to share one visual system with per-prop tuning

## Why Not Keep Solving This in DecorLayer

`DecorLayer` is still valid for cheap bulk decor, but it is the wrong long-term
home for coral if coral is also the prototype for trees.

Reasons:

- `TileMapLayer` sorting is cell-based, not a true free foot-pivot model
- per-tile Y-sort tuning can improve behavior, but it does not give the same
  control as a prop root positioned at the feet
- trees will need partial collision near the trunk and open space in the crown
- trees and coral both benefit from sharing the same node-based sway-capable
  prop pipeline

In short:

- `DecorLayer` is good for cheap visual clutter
- it is not the right abstraction for gameplay-relevant vegetation props

## Migration Plan

### Phase 1: Introduce the Prop Category

- add a dedicated prop render kind separate from flat tiles and large structures
- define prop metadata needed by runtime rendering:
  - sprite atlas coord or texture reference
  - visual offset from foot pivot
  - collision rectangles near the base
  - sway settings or sway preset
- keep the existing decor tile path intact during this phase

Goal:

- no behavior change yet
- only create the data model and scene abstraction needed for later migration

### Phase 2: Build a Reusable World Prop Scene

- create a reusable prop scene for single-sprite anchored world props
- move sway support from `DecorLayer` assumptions to per-sprite shader usage
- support per-prop collision rectangles near the base only
- ensure depth sorting is based on the prop root position

Goal:

- one implementation path that already works for coral and future trees

### Phase 3: Migrate Coral Off DecorLayer

- convert coral variants from `SWAY_DECOR` into the new world prop category
- stop placing coral into `DecorLayer`
- spawn coral as prop instances from chunk data instead
- preserve the current visual sway feel using the shared prop shader

Goal:

- coral behaves like a true foot-anchored prop
- coral becomes the first real validation of the tree-ready pipeline

### Phase 4: Reevaluate Sand/Stone Top Visuals

- review whether simple node-based sand/stone occluders should remain as they are
  or be folded into a more unified node-based world-object path
- do not force full unification if it makes the simple cases worse
- prioritize correctness and maintainability over theoretical purity

Goal:

- avoid growing multiple overlapping node systems unnecessarily

### Phase 5: Add Trees on the Same Pipeline

- implement trees directly as world props
- use small trunk collision near the base
- use large upward visual offset for canopy
- tune sway so trunks stay relatively stable and crowns move more

Goal:

- trees arrive as a content addition, not as another architecture exception

## Resolved Decisions

### Chunk Storage Model

World props should use a dedicated chunk-level prop layer instead of continuing
to be modeled as `top_tile_id` values.

Recommended storage direction:

- keep `ground` as its own layer
- keep `top_tiles` for true tile-like top content
- add a sparse `props` collection for node-based vegetation and similar props

Reasons:

- a tile and a prop are different concepts and should not share one data model
- props need richer runtime behavior than top tiles:
  - explicit foot pivot
  - partial collision
  - sway settings
  - future per-instance state such as variant, seed, growth, or interaction data
- storing props as fake top tiles would continue mixing gameplay categories and
  make `TileProperties` increasingly overloaded

Performance note:

- the important cost is not whether props are stored in a separate sparse
  collection
- the important runtime cost is how many prop nodes, collisions, and shadered
  visuals are active at once
- therefore the separate prop layer is considered architecturally cleaner
  without introducing a meaningful storage-level performance problem

### Runtime Scene Split

World props and large structures should use separate runtime scenes, but share
common infrastructure where useful.

Recommended split:

- `WorldProp` scene for anchored vegetation-style props such as coral and trees
- separate structure scene or structure visual path for multi-part or larger
  placeables
- shared helpers/factories for:
  - root placement at foot pivot
  - collision rectangle setup
  - shader material setup
  - shared metadata loading or instance creation

Reasons:

- a single universal runtime scene would likely become a large branching
  catch-all object
- small props and large structures have overlapping needs, but not identical
  ones
- separate runtime scenes keep responsibilities narrower and easier to reason
  about
- shared infrastructure still avoids unnecessary duplication

In short:

- separate scene types
- shared supporting infrastructure

## Non-Goals

This plan does not require:

- removing `DecorLayer` entirely
- converting every existing tile into a node
- eliminating `TileMapLayer` as the main terrain renderer

The goal is not to make everything node-based. The goal is to use node-based
props only where the visual and gameplay rules actually require them.

## Expected Benefits

- consistent occlusion rules for coral, trees, and similar vegetation
- correct partial collision near the base only
- reusable sway behavior across underwater and overworld vegetation
- fewer rendering special-cases to remember
- cleaner foundation for future biomes with dense vegetation content

## Open Questions

- whether a future cheap-decor pass should remain tile-based for dense non-solid
  clutter such as pebbles, grass tufts, or tiny mushrooms

This is intentionally deferred. It is not required to build the first clean
prop pipeline for coral and trees.
