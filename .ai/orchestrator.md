# Orchestrator Policy

This file defines how the main assistant should use the local AI pipeline.

Intent:
- the assistant is the orchestrator
- planner, builder, and reviewer are subordinate stages
- the default behavior is autonomous execution, not step-by-step user confirmation

Canonical entrypoints:
- the canonical multi-stage entrypoint is `.ai/pipeline.ps1`
- the canonical default pipeline config is `.ai/pipelines/default.json`
- do not invent or guess alternate pipeline docs or entrypoints such as `.ai/pipeline.md`
- do not create ad hoc pipeline configs, helper workflow files, or alternate orchestration entrypoints for a normal feature run

Default orchestration rules:
- when a concrete implementation task is clear enough, run the configured pipeline without asking for permission between planner, builder, and reviewer
- treat `planner -> builder -> reviewer` as the normal flow
- if review returns `pass`, continue to local verification and then report back
- if review returns `fail`, stop the pipeline and report findings first

Before starting implementation:
- first send a short user-facing update that says:
  - what you understood the task to be
  - how you plan to proceed
- for concrete implementation work, the plan should explicitly mention that you are about to use the local pipeline

Pipeline-first rule:
- for concrete implementation tasks, the first substantive execution step must be starting `.ai/pipeline.ps1`
- if the task only exists in chat and is not yet materialized as a repo artifact, first write or update a task file under `.ai/tasks/`, then run `.ai/pipeline.ps1`
- do not directly edit gameplay code, docs, or other repo files yourself while the pipeline is available to handle the task
- do not replace the pipeline with ad hoc repo exploration followed by manual edits
- do not silently fall back to direct implementation because the task seems obvious; use the pipeline anyway
- use the existing pipeline config unless the user explicitly asked to change pipeline behavior
- do not create files such as temporary reviewer-only pipeline configs just to continue a normal run

Allowed reasons to bypass the normal pipeline:
- the user is asking for analysis, review, brainstorming, or explanation only
- the task is specifically to repair the pipeline itself or update `.ai/*` orchestration files
- the pipeline is technically blocked or failing, and the immediate work is to diagnose or repair that pipeline failure

Rules for changing `.ai/*` files during a normal feature run:
- do not create or edit `.ai/pipelines/*`, `.ai/orchestrator.md`, `.ai/README.md`, provider wrappers, or role files as part of normal feature delivery
- if the run exposes a weakness in the orchestration setup, finish the feature run first if possible
- then report the weakness in the post-run retrospective and suggest the `.ai/*` change explicitly
- only modify `.ai/*` immediately when the current task is specifically about pipeline/orchestrator behavior, or when the pipeline is blocked and the `.ai/*` change is necessary to proceed

When asked to "implement the plan we just discussed":
- do not rely on chat memory alone as the execution artifact
- locate the relevant repo plan file if it already exists, or materialize the plan into `.ai/tasks/<name>.md`
- then run the normal pipeline from that task artifact

Ask the user only when:
- the requested change is ambiguous enough that multiple materially different product behaviors are possible
- the pipeline needs a destructive action not explicitly requested
- external approval is required and no approved execution rule exists
- the reviewer finds a high-severity disagreement about the intended behavior
- required assets, credentials, or external dependencies are missing

Do not ask the user just to advance stages:
- do not ask whether planner should run
- do not ask whether builder should run
- do not ask whether reviewer should run
- do not ask whether a second-model review should happen if the configured pipeline already says it should

Builder/reviewer loop:
- run one builder pass
- run one reviewer pass
- if reviewer fails, do not silently ship the builder result
- a follow-up builder fix pass is allowed, but only if the reviewer findings are concrete and the intended behavior is still unambiguous
- after a fix pass, run reviewer again before reporting success

Reporting style:
- keep intermediary updates short
- before pipeline execution, briefly state your understanding and intended pipeline path
- final report should summarize:
  - what the builder changed
  - what the reviewer found
  - whether the pipeline passed or failed

Post-run protocol after a feature implementation finishes:
1. report what happened across the iterations
2. reflect on whether the run exposed weaknesses in prompts, policies, pipeline config, or docs, and suggest concrete updates to `.ai/*` files when useful
3. tell the user what they should manually test to confirm the change behaves correctly in the running game/app
4. delete temporary `.ai/runs/` artifacts unless they are still needed for an active follow-up pass
5. propose a conventional commit message based on the cleaned feature diff
6. ask the user whether to commit
7. do not silently slip `.ai/*` orchestration changes into the feature diff without first calling them out in this retrospective

Cleanup:
- pipeline run artifacts under `.ai/runs/` are temporary execution details
- after the orchestrator has summarized the result, those run artifacts should be deleted unless they are still needed for an active follow-up pass
- keep `.ai/runs/.gitkeep`
- cleanup should happen before proposing or creating a commit, so the commit decision is based on the real feature diff

Source of truth:
- this file controls orchestration behavior
- role-specific behavior remains in `roles/*.md`
- repo constraints remain in `context/repo_rules.md` and `CLAUDE.md`
