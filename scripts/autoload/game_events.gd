extends Node
## Central event bus — decouples game systems so they communicate through
## signals instead of direct node references.
## Autoloaded as "GameEvents".
##
## Convention: emitters document which system fires the signal.
## Listeners connect in _ready() and react without knowing the source.

# --- Lifecycle events ---

## Emitted BEFORE the multiplayer peer is closed (any disconnect path).
## Fired by: NetworkManager.leave_game()
@warning_ignore("unused_signal")
signal game_leaving

# --- World events (server-side) ---

## A block was broken. Emitted after the tile is erased and the modification
## is recorded, but before any item drop. Listeners can spawn drops, play
## sounds, spawn particles, update achievements, etc.
## Fired by: ChunkManager
@warning_ignore("unused_signal")
signal block_broken(coord: Vector2i, tile_id: int)

## A block was placed. Emitted after the tile is written.
## Fired by: ChunkManager
@warning_ignore("unused_signal")
signal block_placed(coord: Vector2i, tile_id: int)

# --- Player events (server-side) ---

## A player has fully joined: spawned, inventory created/restored.
## Fired by: Main
@warning_ignore("unused_signal")
signal player_joined(peer_id: int)

## A player is about to leave: state saved, cleanup about to start.
## Fired by: Main
@warning_ignore("unused_signal")
signal player_left(peer_id: int)

# --- Item events (server-side) ---

## A player picked up an item from the world.
## Fired by: ItemEntity
@warning_ignore("unused_signal")
signal item_picked_up(peer_id: int, item_id: int, count: int)
