# Player Reveal Effect — Plan

Wenn der lokale Spieler hinter einer Struktur steht, soll ein kreisförmiger Bereich auf dem
verdeckenden Objekt transparent werden, sodass der Spieler immer sichtbar bleibt.

---

## Analyse: Was verdeckt den Spieler?

### Render-Reihenfolge (aus `world_generator.tscn` + `main.tscn`)

```
WorldGenerator
├── TerrainLayer        (unsichtbar, modulate alpha=0)
├── BaseVisualLayer     (tile-Visuals, im Baum vor DepthSorted → immer hinter Player)
├── PlantLayer          (Pflanzen/Korallen, ebenfalls hinter Player)
└── DepthSorted  (y_sort_enabled=true)
    ├── Players/
    │   └── <Player>
    └── <TallStructureVisual>  ← per structure_manager.add_child() direkt hier
```

**TileMapLayer** (BaseVisualLayer, PlantLayer) rendern aufgrund der Baumreihenfolge immer
**hinter** dem Player → kein Reveal-Shader nötig.

**TallStructureVisual** hingegen liegt direkt in `DepthSorted` neben dem Player-Node.
Y-Sort entscheidet: hat eine Struktur eine größere Y-Position als der Spieler (weiter unten),
rendert sie über ihm. Da Strukturen aber optisch nach oben ragen, decken sie den Spieler
visuell ab — das ist der Hauptfall.

---

## Technischer Ansatz

### Global Shader Uniforms (Godot 4)

Statt den Uniform-Wert auf jedem ShaderMaterial einzeln pro Frame zu setzen, wird
`RenderingServer.global_shader_parameter_set()` genutzt. Der Wert wird einmal
zentral geschrieben und steht automatisch in allen Shadern zur Verfügung, die
`global uniform` deklarieren.

### Koordinatensystem

Der Shader vergleicht Pixel-Positionen in **Screen-Space** (`FRAGCOORD.xy`).
Die Player-Position wird per `get_viewport().get_canvas_transform() * player.global_position`
in Screen-Pixel umgerechnet — berücksichtigt automatisch Camera-Zoom (aktuell 3×)
und Camera-Offset.

### Reveal-Verhalten

Immer aktiv (kein Occlusion-Detection). Der Reveal-Kreis ist permanent um den
lokalen Spieler herum sichtbar auf allen Structure-Sprites — unabhängig davon,
ob tatsächlich Verdeckung stattfindet. Das ist der Standardansatz im Genre
(z.B. Stardew Valley, Moonlighter) und wirkt natürlich.

---

## Dateien & Änderungen

### 1. NEU: `assets/shaders/player_reveal.gdshader`

```glsl
shader_type canvas_item;

global uniform vec2 player_screen_pos;
uniform float reveal_radius : hint_range(0.0, 300.0) = 60.0;
uniform float edge_softness : hint_range(0.0, 100.0) = 20.0;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    float dist = length(FRAGCOORD.xy - player_screen_pos);
    float reveal = smoothstep(reveal_radius, reveal_radius + edge_softness, dist);
    COLOR = tex;
    COLOR.a *= reveal;
}
```

- `player_screen_pos` — Global Uniform, einmal pro Frame von Service gesetzt
- `reveal_radius` — Radius in Screen-Pixeln (bei 3× Zoom: 60px ≈ 20 World-Units ≈ 1.25 Tiles)
- `edge_softness` — Weicher Übergang am Rand des Kreises
- `FRAGCOORD.xy` — Screen-Position des aktuellen Pixels (passt zu player_screen_pos)

### 2. NEU: `scripts/main/player_reveal_service.gd`

Service-Node in `main.tscn` (analog zu den anderen Services).

```gdscript
extends Node

func _ready() -> void:
    RenderingServer.global_shader_parameter_add(
        "player_screen_pos", RenderingServer.GLOBAL_VAR_TYPE_VEC2, Vector2.ZERO
    )

func _process(_delta: float) -> void:
    var player := _get_local_player()
    if player == null:
        return
    var screen_pos: Vector2 = get_viewport().get_canvas_transform() * player.global_position
    RenderingServer.global_shader_parameter_set("player_screen_pos", screen_pos)

func _get_local_player() -> Node:
    for p in get_tree().get_nodes_in_group("players"):
        if p.is_multiplayer_authority():
            return p
    return null
```

### 3. ÄNDERN: `scripts/world/tall_structure_visual.gd`

Shared `static var` — Material wird einmalig erzeugt und von allen Instances geteilt
(korrekt, da ausschließlich Global Uniforms verwendet werden).

```gdscript
const REVEAL_SHADER := preload("res://assets/shaders/player_reveal.gdshader")
static var _shared_reveal_material: ShaderMaterial = null

func _get_reveal_material() -> ShaderMaterial:
    if _shared_reveal_material == null:
        _shared_reveal_material = ShaderMaterial.new()
        _shared_reveal_material.shader = REVEAL_SHADER
    return _shared_reveal_material
```

In `_refresh_visual()`, nach `_parts_root.add_child(sprite)`:
```gdscript
sprite.material = _get_reveal_material()
```

### 4. ÄNDERN: `scenes/main/main.tscn`

```
[node name="PlayerRevealService" type="Node" parent="."]
script = ExtResource("...")
```

Direkt als Kind von Main, analog zu `BreakVisualService`, `WorldDropService` etc.

---

## Offene Fragen / Tuning

- **Reveal-Radius**: 60 Screen-Pixel bei 3× Zoom → ca. 20 World-Pixel → ca. 1.25 Tiles.
  Ggf. anpassen, je nachdem wie groß der Spieler-Charakter visuell ist.
- **Edge Softness**: 20px weicher Übergang — kann größer gemacht werden für einen
  sanfteren, weniger auffälligen Effekt.
- **Mehrere Spieler**: Aktuell wird nur der lokale Spieler (Authority) berücksichtigt.
  Falls Co-op-Kamera mit Split-Screen geplant ist, muss das erweitert werden —
  für jetzt ausreichend.
- **Tiles wirklich hinter Player?**: Nochmal prüfen, ob BaseVisualLayer/PlantLayer durch
  Z-Index-Overrides doch über dem Player landen könnten. Wenn ja, müsste der Shader
  auch auf diese TileMapLayer angewendet werden.
