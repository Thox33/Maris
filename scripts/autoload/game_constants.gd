extends Node
## Global game constants and configuration.
## Autoloaded as "GameConstants" — accessible from anywhere via GameConstants.TILE_SIZE etc.

# --- World ---
## Size of a single tile in pixels.
const TILE_SIZE: int = 16
## Size of a chunk in tiles (16x16).
const CHUNK_SIZE: int = 16
## How often (seconds) to check player positions for chunk loading.
const CHUNK_UPDATE_INTERVAL: float = 0.2
## Radius in chunks around each player to keep loaded (3 → 7x7 grid = 49 chunks).
const CHUNK_LOAD_RADIUS: int = 3
## Radius beyond which chunks get unloaded (hysteresis prevents flicker).
const CHUNK_UNLOAD_RADIUS: int = 5
## Max chunks to load or unload per frame (spreads work to avoid spikes).
const CHUNKS_PER_FRAME: int = 1

## Depth scaling factor for terrain density calculation.
const WORLD_SCALE: int = 256

# --- Player / Movement ---
## Maximum movement speed in pixels per second.
const MOVE_SPEED: float = 120.0
## How quickly the player accelerates when pressing a direction.
const MOVE_ACCELERATION: float = 400.0
## How quickly the player decelerates when no input.
const MOVE_FRICTION: float = 200.0

# --- Networking ---
const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4
## How often (seconds) the authority sends position updates to peers.
const POSITION_SYNC_INTERVAL: float = 0.01
## Render remote players slightly in the past so interpolation has two snapshots.
const REMOTE_PLAYER_INTERPOLATION_BACK_TIME: float = 0.1
## Small fallback extrapolation when only one recent player snapshot is available.
const REMOTE_PLAYER_MAX_EXTRAPOLATION: float = 0.1
## How quickly remote players converge to the interpolated network position.
const REMOTE_PLAYER_SMOOTHING: float = 18.0
## How quickly client-side item visuals converge to replicated positions.
const ITEM_POSITION_SMOOTHING: float = 16.0

# --- Block interaction ---
## Maximum distance (in pixels) at which a player can break/place blocks.
const BLOCK_INTERACT_RANGE: float = 80.0
## Base damage applied by one mining hit before tool modifiers.
const BREAK_BASE_DAMAGE: float = 0.25
## Base cooldown between mining hits before tool modifiers.
const PRIMARY_USE_COOLDOWN: float = 0.25
## How often a held primary-use target is refreshed to the host.
const PRIMARY_USE_KEEPALIVE_INTERVAL: float = 0.2
## How long the host keeps an active primary-use state without a fresh keepalive.
const PRIMARY_USE_TIMEOUT: float = 0.7
## How long a damaged target remains resumable without further hits.
const DAMAGED_TARGET_TIMEOUT: float = 5.0
## Number of crack stages used for replicated damage visuals.
const BREAK_STAGE_COUNT: int = 8

# --- Inventory ---
## Total number of slots in a player inventory.
const INVENTORY_SIZE: int = 40
## Number of hotbar slots (first N slots of the inventory).
const HOTBAR_SIZE: int = 10

# --- Item drops ---
## Radius (pixels) at which a player picks up a dropped item.
const ITEM_PICKUP_RADIUS: float = 24.0
## Seconds after spawning before an item can be picked up.
const ITEM_PICKUP_DELAY: float = 0.5
## Seconds until a dropped item despawns.
const ITEM_DESPAWN_TIME: float = 300.0
## Vertical oscillation speed for floating items (pixels/sec).
const ITEM_FLOAT_SPEED: float = 8.0

# --- Chat ---
## Maximum character length of a single chat message.
const MAX_CHAT_LENGTH: int = 200

# --- Persistence ---
## Root directory for world saves inside user://.
const SAVE_DIR: String = "user://saves/"
## How often (seconds) the server auto-saves the world.
const AUTO_SAVE_INTERVAL: float = 120.0
## Horizontal drift speed for dropped items (pixels/sec).
const ITEM_DRIFT_SPEED: float = 15.0
## Movement speed for dropped items when they are being pulled to a player.
const ITEM_ATTRACT_SPEED: float = 180.0
