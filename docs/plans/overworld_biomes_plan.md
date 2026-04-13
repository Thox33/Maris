# Overworld Biomes Plan

See also:

- [`../index.md`](../index.md)
- [`overworld_migration_plan.md`](overworld_migration_plan.md)
- [`roadmap.md`](roadmap.md)

Status: 2026-04-12

## Purpose

Define the target world shape, biome layout, and progression logic for the overworld.
This document is intentionally about world identity and generation direction, not about
the lower-level migration steps already tracked in [`overworld_migration_plan.md`](overworld_migration_plan.md).

## Recommended Direction

Use a **large but finite** world that is still streamed and stored in chunks.

Recommended structure:

- a protected central starter region
- strong directional biome identity by compass direction
- softer transition bands instead of hard biome borders
- an explicit outer world boundary that explains why the world ends

This keeps exploration readable and supports progression much better than a truly infinite
noise field. It also avoids the feeling of a random sandbox with no authored world shape.

## World Shape

Preferred option: **roughly circular world**

Why:

- it makes the center feel natural as a shared starting area
- cardinal progression reads clearly from the spawn outward
- travel distance to each major region stays easier to balance
- the outer edge can become a real world feature instead of an arbitrary map cutoff

The circle does not need to be perfectly geometric. A slightly irregular or noise-distorted
outline will feel less artificial than a mathematically clean disk.

## Biome Layout

### Center: Starter Heartland

The center should be broad, safe, and visually welcoming.

Target content:

- meadow / grassland
- forest pockets
- ponds and small lakes
- light stone patches
- low enemy pressure

Design goal:

- new players can gather wood, stone, food, and basic crafting materials here
- the area should feel stable and readable, not hostile

### North: Heat Axis

The north getting hotter is a good direction and gives strong progression contrast.

Recommended structure:

- inner north: dry grassland into desert
- mid north: harsher desert / badlands
- far north: volcanic biome with magma lakes, geysers, ash fields, and small volcanoes

Suggestion:

- do not jump directly from pleasant center to full desert
- use a dry transition zone first so the progression feels earned

### South: Cold Axis

The south getting colder is also a strong contrast and maps cleanly against the north.

Recommended structure:

- inner south: conifer / taiga biome
- mid south: snow biome
- far south: frozen wasteland / glacier biome

Suggestion:

- include icy lakes, wind-carved stone, and sparse dead vegetation in the far south
- this gives the zone more identity than "snow, but more"

### West: Wild Growth Axis

The west as a lush natural direction works well.

Recommended structure:

- inner west: dense forest or overgrown woodland
- mid west: jungle
- far west: swamp / marsh

Suggestion:

- let the jungle and swamp partially overlap in the outer west instead of switching sharply
- this is a good area for dense vegetation, slower movement, and high material variety

### East: Stone Axis

"Rocky and less alive" is a good base idea, but it needs one more distinctive hook.

Recommended structure:

- inner east: rocky scrubland
- mid east: highland / mesa / badlands variant
- far east: shattered stone fields or harsh mountain foothills

Suggestion:

- avoid making east only "less content"
- it should be intentionally austere, with cliffs, boulders, mineral nodes, ruins, or wind-shaped rock formations

## Important Refinement

Do **not** implement the world as four hard pie slices with one biome per direction.

Instead:

- use each direction as a dominant biome theme
- add transition belts between the center and outer extremes
- allow small sub-biomes and feature pockets inside each major zone

Example:

- north can still contain oasis pockets
- south can contain frozen lakes and exposed stone ridges
- west can contain clearings inside the jungle mass
- east can contain sparse dead forests or canyon strips

This will feel much more natural and replayable.

## Missing Pieces Worth Adding

The current direction is already strong. The main thing missing is not a new cardinal biome,
but better biome support systems:

- transition biomes
- landmark features
- resource identity per region
- clear edge treatment for the finite world

Useful feature ideas:

- ruins in the rocky east
- oasis or fossil fields in the north
- frozen lakes and ice cracks in the south
- giant trees or overgrown ruins in the west

These are usually more valuable than adding a fifth major biome too early.

## Boundary Design

If the world is finite, the edge should be visible in-world.

Good options:

- mountain wall / cliffs
- ocean or toxic sea
- giant chasm ring
- magical storm / corrupted outer rim

Recommendation:

- keep the boundary consistent with the biome tone
- avoid invisible walls or a sudden hard stop at chunk limits

## Generation Model Recommendation

Use a layered generator, not a single density function.

Recommended passes:

1. define world mask and distance from center
2. define directional biome weights (north heat, south cold, west growth, east stone)
3. assign the dominant biome from those weights plus local noise
4. generate ground within the chosen biome
5. place liquids and special terrain features
6. place top-layer vegetation, obstacles, and structures
7. reserve and polish the starter region around spawn

This supports the finite-world concept cleanly and leaves room for later biome expansion.

## Initial Scope Recommendation

To keep implementation manageable, start with:

- center heartland
- north desert into volcanic
- south taiga into snow / ice
- west forest into jungle / swamp
- east rocky highlands

Do not try to solve every sub-biome immediately.
First make the macro map readable, then add local variation.

## Locked Macro Decisions

The current agreed baseline:

- the world is **finite**
- the world is **centered on `(0, 0)`**
- the world shape is a **circle**
- all four cardinal directions should have **roughly equal travel distance**
- the center contains a **safe circular starter region**
- the starter region should be about **20 chunks in diameter**
- each direction should use **three outer biome layers**
- transition bands should be present, but stay fairly compact at about **1-2 chunks**
- the first version of the world should be **fully procedural**
- later points of interest can be added in a post-generation pass
- the world edge should be a **hard circular boundary**
- the outer game should later contain **stronger creatures and progression pressure**

## Suggested World Size

Recommended first fixed size:

- **128 chunks diameter**
- `16 x 16` tiles per chunk
- total world diameter: **2048 tiles**

Suggested radial layout:

- starter heartland: **10 chunk radius**
- transition 1: **2 chunk radius**
- macro layer 1: **14 chunk radius**
- transition 2: **2 chunk radius**
- macro layer 2: **14 chunk radius**
- transition 3: **2 chunk radius**
- macro layer 3: **14 chunk radius**
- outer boundary ring: **6 chunk radius**

Total: **64 chunk radius** = **128 chunk diameter**

This is large enough to support real travel and region identity, but still small enough to
feel like one authored world rather than an endless terrain sheet.

## Boss Model

The recommended boss model is:

- the overworld contains visible boss-entry structures
- interacting with a structure teleports the party into a dedicated boss arena
- major progression bosses use this structure-to-arena flow
- minor elites and mini-bosses should still exist directly in the overworld

This gives the game a clean milestone loop without making the overworld feel empty.

## Biome Matrix

This matrix is the current macro target. It is intentionally compact and should later feed
more detailed combat, loot, and quest-tree documents.

| Zone | Theme | Neutral mobs | Hostile mobs | Mob drops | Minerals / crystals | Plants / organic | Essence | Boss structure / boss concept |
|---|---|---|---|---|---|---|---|---|
| Center | Heartland meadows, woods, ponds | deer, boar, rabbit, chicken | slime, wolf, bandit scout | hide, meat, feather | stone, clay | wood, fiber, berries, starter herbs | minor verdant motes | no major boss in safe zone |
| West 1 | Overgrown woodland | stag, boar, monkey | thornling, vine crawler, wolf pack | hide, thorn core | amber, soft stone | hardwood, vines, resin, healing herbs | verdant essence | grove idol / root beast |
| West 2 | Jungle interior | parrot, ape, giant turtle | jungle stalker, spitter plant, panther | predator hide, venom sac | jade, bright quartz | giant fruit, jungle fiber, spores | wild essence | temple gate / jungle matriarch |
| West 3 | Marsh and deep swamp | frog, heron, swamp turtle | leech swarm, bog fiend, mosquito cloud | slime gland, chitin, toxic sac | bog amber, murk crystal | reeds, swamp bloom, fungal caps | toxic essence | bog shrine / swamp hydra |
| East 1 | Rocky scrubland | goat, lizard, hawk | shard beetle, scavenger, stone crawler | tough hide, shell fragments | iron ore, coal, quartz | dry brush, thorn shrub | dust essence | quarry seal / stone sentinel |
| East 2 | Highlands and mesa ruins | ram, vulture, mountain goat | crystal scorpion, cliff lurker, ruin warden | venom sac, relic scrap | silver ore, salt crystal, clear crystal | sparse brush, dry roots | resonant essence | ruin gate / crystal golem |
| East 3 | Shattered stone fields | carrion bird, ram | geo drake, ruin sentinel, rift crawler | plate shards, relic core | rare ore, seismic crystal, ancient stone | almost none | seismic essence | titan vault / ruin colossus |
| South 1 | Taiga fringe | elk, hare, fox | frost wolf, ice slime, owlbeast | fur, meat, feather | packed ice, pale crystal | pine wood, frost herbs | chill essence | frost cairn / white stag spirit |
| South 2 | Snowfields | musk ox, arctic fox | frost spider, ice wraith, snow stalker | thick fur, frost fang | blue crystal, hard ice | snow moss, winter bloom | glacial essence | mirror monolith / frost warden |
| South 3 | Glacier waste | mammoth, snow hare | blizzard specter, glacier golem, ice serpent | ancient fur, frozen core | glacier crystal, pale ore | almost none, ice reed | zero essence | polar vault / glacier titan |
| North 1 | Dry steppe and desert edge | dune lizard, beetle, carrion bird | scorpion, dune crawler, fire ant | carapace, venom sac | flint, sulfur, sun crystal | cactus, dry herb | ember essence | sun shrine / dune wyrm |
| North 2 | Badlands and volcanic edge | ash beetle, lava crab | magma hound, ash crawler, cinder brute | charred hide, ember gland | obsidian, basalt, sulfur crystal | emberroot, ash reed | flame essence | forge gate / magma colossus |
| North 3 | Caldera and firelands | fire drake, ash bird | lava serpent, cinder elemental, phoenix spawn | scorched scale, magma core | infernal ore, fire gem, obsidian | ash moss, ember bloom | infernal essence | caldera core / volcanic heart |

## Intended Clear Order

This is the current intended progression route. It should later become the backbone of a
quest-tree document that explains the intended path without hard-locking free exploration.

### Progression Rules

- progression should stay **soft-gated**, not fully locked
- players may enter dangerous regions early, but should be underprepared
- resources and boss rewards should make later layers practical rather than merely possible
- north and south should partially unlock each other
- west and east should provide the baseline crafting economy that supports all later regions

### Recommended Clear Route

1. **Center**
   Build the first base, gather food, wood, stone, fiber, and basic healing materials.

2. **West 1 + East 1**
   Establish the first real crafting tier.
   West 1 provides organic crafting and healing.
   East 1 provides metal, coal, and basic mineral progression.

3. **First major boss: East 1**
   Defeat the `Stone Sentinel` from the `Quarry Seal`.
   Intended role: unlock the first true milestone core for crafting, boss-entry activation, or structure progression.

4. **South 1**
   Gather fur, frost herbs, and chill essence.
   Intended role: prepare the first climate-oriented gear and utilities.

5. **North 1**
   Gather sulfur, ember essence, and early desert / heat materials.
   Intended role: unlock heat-side crafting and the first volcanic preparation.

6. **West 2 + East 2**
   Expand into stronger utility and upgrade regions.
   West 2 deepens alchemy, poison, and advanced plant utility.
   East 2 deepens crystal tech, better gear, and structure-tech materials.

7. **South 2 and North 2**
   Start the true climate-pressure game.
   South 2 should feel safer after north-side thermal upgrades.
   North 2 should feel safer after south-side stabilizing or cooling upgrades.

8. **Regional milestone bosses**
   Defeat the biome bosses tied to the second layers.
   These should unlock the deeper directional layers and stronger crafting branches.

9. **All layer 3 regions**
   Push into the harsh outer world: deep swamp, shattered stone, glacier waste, caldera.
   These are the late-world preparation and mastery zones.

10. **Outer-rim or final-tier boss content**
    Reserve this for later design, but the final major progression should happen after the player has proven mastery across multiple directions.

## Cross-Region Unlock Logic

The intended cross-links are:

- **West 1 + East 1** unlock the first serious gear tier
- **South 1** helps prepare **North 2**
- **North 1** helps prepare **South 2**
- **West 2** improves survival, healing, and utility for outer biomes
- **East 2** improves tool quality, boss structure access, and advanced crafting
- **Layer 3** regions should require combined preparation from multiple directions

## Quest Tree Implication

The future quest tree should:

- teach the intended route above
- explain why a region matters before the player enters it
- point to required materials and boss-entry structures
- keep optional detours visible
- avoid turning the whole world into a hard quest corridor

The quest tree should express **recommended progression**, not remove player freedom.
