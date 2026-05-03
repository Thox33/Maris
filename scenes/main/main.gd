extends Node2D
## Main scene composition root.
## Session behavior is delegated to dedicated child services so this script stays
## focused on wiring scene nodes together and handling app-level shutdown.

const DEFAULT_WORLD_NAME: String = "default"

## Set by the lobby before loading this scene to choose which world to load.
## Falls back to DEFAULT_WORLD_NAME if empty.
static var selected_world_name: String = ""

## Set to true before loading this scene to run a playerless server.
static var dedicated_server: bool = false

@onready var world: Node2D = $World
@onready var _players: Node = $World/DepthSorted/Players
@onready var _items: Node = $Items
@onready var _player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _item_spawner: MultiplayerSpawner = $ItemSpawner
@onready var inventory_manager: Node = $InventoryManager
@onready var _inventory_authority_service: Node = $InventoryManager/InventoryAuthorityService
@onready var _world_placement_service: Node = $InventoryManager/WorldPlacementService

@onready var _character_setup_root: Control = $CharacterSetup/Root
@onready var _character_setup_title: Label = $CharacterSetup/Root/PanelContainer/VBoxContainer/TitleLabel
@onready var _character_setup_message: Label = $CharacterSetup/Root/PanelContainer/VBoxContainer/MessageLabel
@onready var _character_name_edit: LineEdit = $CharacterSetup/Root/PanelContainer/VBoxContainer/CharacterNameEdit
@onready var _character_color_option: OptionButton = $CharacterSetup/Root/PanelContainer/VBoxContainer/ColorOptionButton
@onready var _character_color_preview: ColorRect = $CharacterSetup/Root/PanelContainer/VBoxContainer/ColorPreview
@onready var _character_create_button: Button = $CharacterSetup/Root/PanelContainer/VBoxContainer/CreateButton

@onready var _session_bootstrap_service: Node = $SessionBootstrapService
@onready var _session_join_service: Node = $SessionJoinService
@onready var _session_identity_service: Node = $SessionIdentityService
@onready var _character_setup_service: Node = $CharacterSetupService
@onready var _player_spawn_service: Node = $PlayerSpawnService
@onready var _session_persistence_service: Node = $SessionPersistenceService
@onready var _world_drop_service: Node = $WorldDropService
@onready var _use_authority_service: Node = $UseAuthorityService
@onready var _break_visual_service: Node = $BreakVisualService

var _is_app_quitting: bool = false


func _ready() -> void:
	_player_spawner.spawn_function = Callable(_player_spawn_service, "create_player")
	_item_spawner.spawn_function = Callable(_world_drop_service, "create_item_entity")

	_world_placement_service.setup(_players, world.chunk_manager, world.world_object_manager)
	inventory_manager.setup(
		_inventory_authority_service, _world_placement_service, _players, _world_drop_service
	)
	_use_authority_service.setup(
		_players, world.chunk_manager, world.world_object_manager, inventory_manager
	)
	_break_visual_service.setup(world, world.depth_sorted)
	_use_authority_service.damaged_target_updated.connect(
		Callable(_break_visual_service, "apply_damaged_target")
	)
	_use_authority_service.damaged_target_cleared.connect(
		Callable(_break_visual_service, "clear_damaged_target")
	)

	_session_persistence_service.setup(
		world, _players, inventory_manager, _session_identity_service
	)
	_session_join_service.setup(
		world, _session_identity_service, _character_setup_service, _player_spawn_service
	)
	_character_setup_service.setup(
		_session_join_service,
		_player_spawn_service,
		_character_setup_root,
		_character_setup_title,
		_character_setup_message,
		_character_name_edit,
		_character_color_option,
		_character_color_preview,
		_character_create_button
	)
	_player_spawn_service.setup(
		world,
		_players,
		_items,
		_player_spawner,
		inventory_manager,
		_use_authority_service,
		_session_identity_service,
		_character_setup_service,
		_session_persistence_service
	)
	_world_drop_service.setup(_item_spawner, inventory_manager)
	var chunk_debug_overlay: Node = world.chunk_debug_overlay
	if chunk_debug_overlay != null and chunk_debug_overlay.has_method("setup_chunk_manager"):
		chunk_debug_overlay.setup_chunk_manager(world.chunk_manager)
	_session_bootstrap_service.setup(
		world,
		_session_persistence_service,
		_player_spawn_service,
		_session_join_service
	)

	NetworkManager.session_ended.connect(_on_session_ended)
	get_tree().auto_accept_quit = false
	ChatManager.set_session_context(_players, inventory_manager, world.chunk_manager)

	var world_name := selected_world_name if not selected_world_name.is_empty() else DEFAULT_WORLD_NAME
	_session_bootstrap_service.bootstrap_session(world_name, dedicated_server)


func _on_session_ended(reason: String) -> void:
	if reason == "app_quit":
		get_tree().quit()


func _exit_tree() -> void:
	get_tree().auto_accept_quit = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _is_app_quitting:
			return
		_is_app_quitting = true
		NetworkManager.leave_game("app_quit")
