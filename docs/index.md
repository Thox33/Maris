# Documentation Index

This directory is the single entry point for the project's internal documentation.

The documentation is organized by document type, not by age or by whatever file happened to exist first. The goal is to keep the root [`README.md`](../README.md) short and practical, while deeper technical detail and planning live here.

## Structure

- [`architecture/`](architecture/)
  - stable project-wide technical models and rules
- [`systems/`](systems/)
  - focused documentation for concrete gameplay or UI systems
- [`plans/`](plans/)
  - implementation plans, rollout steps, and backlog docs
- [`decisions/`](decisions/)
  - architecture decisions and the reasoning behind them

## Current Entry Points

- [`architecture/overview.md`](architecture/overview.md)
- [`architecture/actor_model.md`](architecture/actor_model.md)
- [`decisions/authority_model.md`](decisions/authority_model.md)
- [`systems/base_character_art_direction.md`](systems/base_character_art_direction.md)
- [`systems/character_pipeline.md`](systems/character_pipeline.md)
- [`systems/inventory_and_hotbar.md`](systems/inventory_and_hotbar.md)
- [`plans/roadmap.md`](plans/roadmap.md)
- [`plans/animation_and_character_plan.md`](plans/animation_and_character_plan.md)

## Documentation Rules

- Write docs in English.
- Prefer one clear topic per document.
- Use relative Markdown links to related docs.
- Do not duplicate architecture explanations across multiple files when one source of truth is enough.
- Put stable technical truth into `architecture/`.
- Put feature-internal behavior into `systems/`.
- Put future work and phased rollouts into `plans/`.
- Put important reasoning and tradeoffs into `decisions/`.
- When a plan becomes implemented reality, migrate the lasting parts into `systems/` or `architecture/`, or delete the file if Git history is sufficient.
- Add a short `See also` section when a doc has obvious related references.
- Update links immediately when files move or are renamed.

## How To Extend Docs

Use this rule of thumb:

- Add to [`../README.md`](../README.md) only if a new contributor should see it immediately.
- Add to `architecture/` if the content defines a long-lived technical model.
- Add to `systems/` if the content explains how one concrete feature works.
- Add to `plans/` if the content describes work to be done.
- Add to `decisions/` if the main value is why a choice was made.

## Notes

- This structure is the current desired state, not a future intention.
- If a section grows too large, split it further inside its category instead of pushing more unrelated content into a single file.
