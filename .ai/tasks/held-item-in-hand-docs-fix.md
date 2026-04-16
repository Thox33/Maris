Follow-up task:

The held-item behavior fix is accepted by code review except for docs parity.

Remaining reviewer finding:
- `docs/systems/character_pipeline.md` is stale
- it still says `held_item_id` is derived from the selected hotbar slot
- current code now prioritizes `InventoryManager.local_held_slot` for hand representation and falls back to the selected hotbar slot when no cursor-held stack exists

Goal:
- update only the relevant documentation
- keep wording aligned with the actual current implementation
- do not change code in this pass unless strictly necessary for doc accuracy

Expected doc updates:
- player responsibilities section
- held-item presentation section
- any nearby wording that still implies "hotbar only"

No docs needed elsewhere unless the file clearly references this exact behavior:
- `README.md`
- `.ai/README.md`

Relevant files:
- `docs/systems/character_pipeline.md`
- `scenes/player/player.gd`
- `scenes/main/inventory_manager.gd`
- `scenes/ui/hotbar_ui.gd`
