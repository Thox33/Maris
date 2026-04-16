Follow-up task:

The previous builder pass changed the held-item visual so the local owner shows the cursor-held stack in hand.

Reviewer result:
- high severity: multiplayer representation desync
- low severity: possible one-frame stale/flicker state on fallback

Fix goal:
- preserve the intended feature: when a player carries an item with the mouse cursor, that item should be the in-world hand representation
- ensure owner and remote peers see the same in-world held item state
- eliminate or avoid the stale fallback timing issue if possible within a minimal change

Important constraints:
- do not keep the solution owner-local only
- use a replicated source of truth for the held hand representation
- keep inventory semantics and drag/drop behavior unchanged
- keep the change focused; update docs only if behavior/contracts/docs actually need it

Current reviewer finding summary:
- The local override in `scenes/actors/humanoid_visual.gd` reads `InventoryManager.local_held_slot`, but remote peers still only receive the replicated `held_item_id` from `scenes/player/player.gd`.
- This means the owner can visually hold/place one item while remotes still see another.

Suggested direction:
- move the source of truth back out of local-only visual state
- either replicate the cursor-held visual item through the existing player held-item sync path, or add a dedicated replicated actor-state value that both local and remote visuals consume
- after the fix, rerun reviewer expectations against multiplayer behavior

Relevant files:
- `scenes/actors/humanoid_visual.gd`
- `scenes/player/player.gd`
- `scenes/main/inventory_manager.gd`
- `scenes/ui/hotbar_ui.gd`
- optionally docs if behavior/contracts need documenting
