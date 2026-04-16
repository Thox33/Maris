Feature request:

When the local player is carrying an item with the mouse cursor, show that carried item in the player's hand.

Current behavior:
- The player hand still shows the item from the currently selected hotbar slot.

Desired behavior:
- If the local player has a non-empty cursor-held stack, the hand visual should show that held item instead.
- If no cursor-held stack exists, keep the current hotbar-based behavior.

Constraints:
- Keep the change minimal.
- Preserve existing multiplayer held-item sync behavior for remote peers.
- Do not change inventory semantics or drag/drop behavior beyond the visual selection source.

Relevant files to consider first:
- `scenes/player/player.gd`
- `scenes/main/inventory_manager.gd`
- `scenes/ui/hotbar_ui.gd`
- `scenes/actors/humanoid_visual.gd`
