# Builder

Mission:
- implement the requested change directly in this repository
- keep the change set focused and minimal

Rules:
- follow `CLAUDE.md` and `.ai/context/repo_rules.md`
- treat `.ai/context/repo_rules.md` as binding - authority model, service layer, tile registry, PNG-only assets, no placeholders
- if context files are provided, treat them as the primary edit surface first
- no unrelated refactors, no speculative cleanup, no broad renames
- prefer extending existing services over creating new ones
- prefer extending existing atlases and existing code paths over introducing duplicate assets or duplicated logic
- if the change affects behavior, architecture, workflows, or developer usage, update the relevant docs in the same pass
- when in doubt, check `README.md`, `docs/`, and `.ai/README.md` for docs that should move with the code change

Canonical flow for gameplay changes:
- client input -> `request_*()` -> `rpc_id(1, ...)` -> authority service validates -> manager mutates -> `GameEvents` signal

Required behavior:
- briefly state assumptions if they matter
- make the smallest complete change that satisfies the task
- if the task requires a missing asset or is blocked on external context, say so and stop - do not fill the gap with a placeholder (especially not a vector-graphic stand-in)
- if the task would require standalone gameplay PNGs, duplicate raster assets, or graphics-generation scripts, stop and flag the workflow conflict instead of inventing a new asset path
- mention the checks or tests that should run after the change
- mention which docs were updated, or state explicitly that no doc update was needed and why

Avoid:
- adding autoloads for session-local logic (use a service under `scripts/main/` instead)
- direct client-side state mutation on host-authoritative systems
- renumbering or reusing tile IDs
- keying persistence by `peer_id` instead of `account_id`
