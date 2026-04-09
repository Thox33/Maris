# Underwater Sandbox

2D multiplayer co-op sandbox game built with Godot 4 and GDScript. The project focuses on an underwater-only world with procedural terrain, free swimming movement, block interaction, and host-authoritative multiplayer from the start.

## Current Status

- Multiplayer lobby flow with host/join and a simplified main menu
- World-bound character creation on first join
- Procedural chunk-based world generation
- Block breaking and placing
- Inventory, hotbar, and item pickup/drop loop
- Underwater fullscreen effect and coral sway shader

## Core Tech

- Godot 4.6
- GDScript
- ENet multiplayer via Godot `MultiplayerAPI`
- Host-as-server architecture for up to 4 players

## Project Structure

```text
assets/   Sprites, shaders, tilesets
docs/     Project documentation index, architecture, systems, plans, decisions
scenes/   Godot scenes for main flow, UI, player, world, items
scripts/  Autoloads, gameplay logic, inventory, world systems, utilities
```

## Running The Project

1. Open the folder in Godot 4.6.
2. Start the project with `scenes/ui/lobby_ui.tscn`.
3. Host a session locally or join via IP.

## Documentation

- Start with [`docs/index.md`](docs/index.md).
- Architecture docs live in [`docs/architecture/`](docs/architecture/).
- System-specific docs live in [`docs/systems/`](docs/systems/).
- Implementation plans and backlog live in [`docs/plans/`](docs/plans/).
- Architecture decisions live in [`docs/decisions/`](docs/decisions/).

The root `README` stays intentionally short. Detailed technical documentation belongs in `docs/`.

## Git Workflow

- `main`: production-ready history
- `develop`: integration branch for upcoming work
- `feature/*`: short-lived branches for individual features or fixes

Example branch names:

- `feature/world-persistence`
- `feature/biome-generation`
- `feature/audio-foundation`

Recommended flow:

1. Branch from `develop`.
2. Merge finished feature branches back into `develop`.
3. Merge `develop` into `main` when a stable milestone is ready.
