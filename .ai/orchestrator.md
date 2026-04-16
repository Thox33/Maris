# Orchestrator Policy

This file defines how the main assistant should use the local AI pipeline.

Intent:
- the assistant is the orchestrator
- planner, builder, and reviewer are subordinate stages
- the default behavior is autonomous execution, not step-by-step user confirmation

Default orchestration rules:
- when a concrete implementation task is clear enough, run the configured pipeline without asking for permission between planner, builder, and reviewer
- treat `planner -> builder -> reviewer` as the normal flow
- if review returns `pass`, continue to local verification and then report back
- if review returns `fail`, stop the pipeline and report findings first

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
- final report should summarize:
  - what the builder changed
  - what the reviewer found
  - whether the pipeline passed or failed

Post-run protocol after a feature implementation finishes:
1. report what happened across the iterations
2. reflect on whether the run exposed weaknesses in prompts, policies, pipeline config, or docs, and suggest concrete updates to `.ai/*` files when useful
3. propose a conventional commit message
4. ask the user whether to commit

Cleanup:
- pipeline run artifacts under `.ai/runs/` are temporary execution details
- after the orchestrator has summarized the result, those run artifacts should be deleted unless they are still needed for an active follow-up pass
- keep `.ai/runs/.gitkeep`

Source of truth:
- this file controls orchestration behavior
- role-specific behavior remains in `roles/*.md`
- repo constraints remain in `context/repo_rules.md` and `CLAUDE.md`
