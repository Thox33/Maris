# Follow-up task: fix scoped reviewer findings for held-item-in-hand feature

The scoped reviewer completed successfully and returned `fail` with two concrete findings.

## Finding 1: drop direction regression

File:
- `scenes/player/player.gd:125`

Issue:
- The new neutral hover zone can set `_look_dir` to `Vector2.ZERO` when the mouse is close to the player body.
- `InventoryManager._spawn_drop_for_peer()` uses `get_look_direction()` for drop launch direction.
- When `get_look_direction()` becomes zero, the drop path falls back to `Vector2.DOWN`, which creates a gameplay regression: dropped items can launch downward instead of in the actual intended cursor/look direction.

Required fix:
- keep a stable non-zero gameplay/network look direction
- if a neutral visual-facing state is needed, separate that from the gameplay drop/look direction
- do not reintroduce unrelated visual overrides

## Finding 2: missing service authority guards

File:
- `scripts/main/inventory_authority_service.gd`

Issue:
- The server-side mutation methods `drop_from_slot()` and `drop_from_held()` do not guard themselves at method entry with a server-authority check.
- This violates the repo rule that host-authoritative service methods must gate at entry.

Required fix:
- add an explicit `multiplayer.is_server()` guard or equivalent server-only gate at the top of both methods
- keep the fix minimal and aligned with existing service conventions

## Constraints

- Preserve the intended held-item-in-hand behavior:
  - cursor-held stack shown in hand when non-empty
  - otherwise selected hotbar item
- Preserve multiplayer consistency between owner and remote peers
- Keep the change focused on the two findings above
- Update docs only if the documented behavior or contract actually changes
- Run the relevant Godot validation/check command after the change

## Deliverable

Report:
1. what changed
2. whether docs changed
3. what validation command you ran and whether it passed
