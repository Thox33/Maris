# Project Brief: 2D Multiplayer Coop Underwater Sandbox Game (Codename: TBD)

## Context

I'm an experienced software developer (Python, Docker, networking, infrastructure) starting my first game development project. I want to build a 2D multiplayer coop sandbox game inspired by Terraria - but set **entirely underwater**. Procedurally generated underwater worlds, block mining/placing, exploration, and cooperative play. The entire world is submerged - no sky, no air. Players swim freely in all directions through an underwater landscape of coral, rock, sand, and sea life.

I'm using **Godot 4.x** with **GDScript**. I have no prior Godot experience but I'm a fast learner. I want to use AI heavily for asset creation (sprites, textures, animations) since art is not my strength.

The project should be set up **professionally from the start** - clean architecture, version control ready, multiplayer-first design. No budget initially, so everything should use free/open-source tools.

## Tech Stack

- **Engine:** Godot 4.x (GDScript, no C#)
- **Version Control:** Git + GitHub
- **Art Pipeline:** AI-generated base assets + Aseprite for refinement
- **Architecture:** Host-as-server model (one player hosts, acts as both server and client) using Godot's built-in MultiplayerAPI

## Key Architecture Principles

1. **Multiplayer-first:** All game logic must be designed with networking in mind from the start. Don't build singleplayer and "add multiplayer later."
2. **Scene composition:** Use Godot's scene/node system properly - small, reusable scenes composed into larger ones.
3. **Signals over direct references:** Use Godot's signal system for decoupled communication between nodes.
4. **Separation of concerns:** Game logic, networking, rendering, and UI should be cleanly separated.
5. **Keep it simple:** Start with the absolute minimum viable prototype. No feature creep.

## Game Design: Underwater World

- **Movement:** Free swimming in all directions (no gravity-based walking/jumping). Swim physics with gentle acceleration/deceleration and optional drift/current effects.
- **World:** Entirely underwater. Terrain is made of sand, stone, coral, seaweed, etc. No surface, no air pockets (for now).
- **Visual feel:** Blue/green/turquoise color palette. Later phases can add particles (bubbles, floating debris, light rays) for atmosphere.

## MVP Scope (Phase 1)

The first milestone is deliberately tiny:

- [x] A player character that can swim freely in all directions (swim physics)
- [x] A small procedurally generated underwater tile world (sand, stone, coral, open water)
- [x] Block breaking and placing (left click = break, right click = place)
- [x] A second player can connect and see/interact with the same world
- [x] Basic camera following the player
- [x] Simple underwater background (blue tint + wave distortion shader)

**Explicitly NOT in Phase 1:** Crafting, inventory, enemies, NPCs, biomes, advanced lighting, saving/loading, sound, water currents.

**Done beyond Phase 1 scope (architectural groundwork):**
- Lobby/game scene split with proper scene transitions
- Coral sway shader (active on dedicated CoralLayer)
- Stable tile ID registry (`TileProperties` with string names + permanent int IDs)
- `MultiplayerSpawner` for automatic player node replication
- Inventory + hotbar + item pickup/drop loop

## Project Structure

Set up the Godot project with this folder structure:

```
project_root/
|- project.godot              # Godot project file
|- .gitignore                 # Godot-specific gitignore
|- GAME_PROJECT_BRIEF.md      # This file (shared context)
|- assets/
|  |- sprites/               # Character sprites, tiles, items
|  |- tilesets/              # TileSet resources
|  \- fonts/                 # UI fonts
|- scenes/
|  |- main/                  # Main scene, game entry point
|  |- player/                # Player scene + scripts
|  |- world/                 # World generation, tile management
|  |- ui/                    # HUD, menus
|  \- networking/            # Multiplayer scenes/scripts
|- scripts/
|  |- autoload/              # Singleton scripts (game state, network manager)
|  |- resources/             # Custom Resource scripts
|  \- utils/                 # Helper functions, constants
\- docs/
   \- architecture.md        # Architecture decisions and notes
```

## Current Step

**Phase 1 largely complete. Next priorities:**

- [ ] World persistence (save/load ChunkData to disk)
- [ ] Sound + music
- [ ] Biomes / more tile variety

## Notes for Claude Code

- All code and comments in **English**
- GDScript style: follow Godot's official style guide (snake_case, type hints where useful)
- Explain Godot-specific concepts briefly when introducing them - I'm learning as I go
- When creating `.tscn` files as text, add comments explaining the node structure
- Flag any decisions that have multiplayer implications early
- Keep all scripts short and focused - one responsibility per script
- After completing each step, update this brief with what was done and what's next
