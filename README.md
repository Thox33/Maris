# Underwater Sandbox

2D multiplayer co-op sandbox game built with Godot 4 and GDScript. The project focuses on an underwater-only world with procedural terrain, free swimming movement, block interaction, and host-authoritative multiplayer from the start.

## Current Status

- Multiplayer lobby flow with host/join
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
docs/     Architecture notes and roadmap
scenes/   Godot scenes for main flow, UI, player, world, items
scripts/  Autoloads, gameplay logic, inventory, world systems, utilities
```

## Running The Project

1. Open the folder in Godot 4.6.
2. Start the project with `scenes/ui/lobby_ui.tscn`.
3. Host a session locally or join via IP.

## Documentation

- `docs/architecture.md`: multiplayer model, scene flow, chunk system, tile system
- `docs/roadmap.md`: backlog and next technical/gameplay milestones
- `GAME_PROJECT_BRIEF.md`: project scope and guiding principles

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

## Near-Term Priorities

- World persistence
- Biomes and more tile variety
- Sound and music
