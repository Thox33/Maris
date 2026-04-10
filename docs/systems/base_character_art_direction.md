# Base Character Art Direction

See also:

- [`../index.md`](../index.md)
- [`character_pipeline.md`](character_pipeline.md)
- [`../plans/animation_and_character_plan.md`](../plans/animation_and_character_plan.md)

Status: 2026-04-06

## Goal

This document locks the visual direction for the first humanoid base character.

It exists to stop vague iteration loops such as:

- "make it nicer"
- "make it more chibi"
- "make it fit the style"

Instead, V1 character work should be judged against a small fixed set of visual rules.

## Role In The Pipeline

This document defines:

- how the V1 humanoid should feel visually
- which silhouette traits are required
- what visual mistakes should be rejected immediately
- what "good enough for PNG production" means

This document does not define animation timing, networking, or save data.

## V1 Character Intent

The V1 humanoid should read as:

- compact
- sturdy
- chibi
- readable at small size
- slightly boxy rather than round and gummy
- calm and grounded rather than hyper-dynamic

The visual mood should fit the underwater game:

- simple
- strong silhouette
- easy to read on bright coral and darker water backgrounds
- slightly charming, but not overly cute or toy-like

## Core Shape Language

The first humanoid should use these shape rules:

- the head is the dominant shape
- the head should feel broad and slightly square, with softened corners
- the torso should be clearly smaller than the head
- the limbs should be short and simple
- the whole body should feel built from a few solid masses, not from many thin details

Practical read:

- head mass should feel close to half of the whole character
- torso should feel compressed, not heroic
- limbs should support the silhouette, not define it

## Required Proportions

These are V1 target proportions, not optional suggestions:

- frame size: `16x24`
- one body type only
- head visually as large as the rest of the body mass
- torso shorter than a realistic human torso
- arms shorter and slimmer than the torso
- legs short, compact, and easy to animate

At gameplay scale, the player should read first as "head plus compact body", not as "tiny human with a slightly larger head".

## Face Direction

The V1 character uses side-view only. Up and down views are not part of V1.

The face is a separate PNG layer placed on top of the body sprite at the head position.

Rules:

- the body sprite includes the head shape as part of the silhouette
- the face PNG carries eyes and expression detail — it is layered on top, not embedded in the body art
- eyes should stay minimal — a few pixels read clearly at chibi scale
- the face must clearly read as looking in the same direction as the body
- the head silhouette and face PNG must feel physically connected with no floating gap

## Torso Direction

The torso should read as a small, stable center mass.

Rules:

- keep the torso compact
- avoid broad shoulders
- avoid hourglass or realistic ribcage anatomy
- avoid a large chest block that competes with the head

For V1, the torso exists mainly to:

- anchor the head
- connect the limbs
- carry clothing color

## Limb Direction

Arms and legs are supporting shapes, not the main design feature.

Rules:

- keep them short
- keep them readable
- avoid very thin stick limbs
- avoid long realistic forearms and shins
- attachment points must feel stable and close to the torso

The limbs should be simple enough that later `idle`, `move`, and `use` animation can be added without fighting the design.

## Styling Rules

V1 should lean toward:

- clean masses
- low detail
- simple readable shading
- slightly angular chibi forms

V1 should avoid:

- blobby marshmallow shapes
- overly rounded baby proportions
- realistic anatomy
- thin elegant proportions
- busy clothing detail
- tiny disconnected body parts

## Readability Rules

The character must survive three checks:

1. It must read clearly when standing still at gameplay zoom.
2. It must remain legible against bright coral and dark water.
3. It must still look coherent when mirrored in side view.

If a design only looks good zoomed in, it is not ready.

## Rejection Rules

Reject a V1 base character immediately if any of these are true:

- the head and torso feel disconnected
- the side view looks like head and body face different directions
- the torso is visually too large
- the limbs read as long human limbs instead of chibi support shapes
- the silhouette becomes muddy against the world
- the design depends on tiny facial detail to work

## Acceptance Criteria

The V1 humanoid is ready for PNG production only when:

- the side-view silhouette is stable in the idle and move poses
- the head-to-body ratio feels intentionally chibi
- the side view reads cleanly without confusion
- the torso and head join cleanly
- the limb attachment points no longer feel arbitrary
- the character still works when mirrored for left-facing presentation
- the character still works without animation

## Production Guidance

When generating or drawing PNG layers for the base character:

- start from silhouette first, not color detail
- lock the side-view silhouette before any animation frames
- keep one hairstyle only for V1
- prefer one strong base character over early customization breadth

If a new visual idea conflicts with this document, update this document first or reject the idea.
