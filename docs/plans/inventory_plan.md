# Inventory Plan

See also:

- [`../index.md`](../index.md)
- [`../architecture/overview.md`](../architecture/overview.md)

Stand: 2026-04-03

## Ziel

Das Inventar soll sich visuell von der permanent sichtbaren Hotbar nach oben ausklappen.
Die Hotbar bleibt also immer sichtbar, und das restliche Inventar erscheint beim Oeffnen darueber.

Das Verhalten soll eher in Richtung Core Keeper gehen als in Richtung Minecraft:

- Hotbar immer unten sichtbar
- Inventar erweitert die Hotbar nach oben
- kein separater "Inventar-Modus", der die ganze Spielwelt blockiert
- Maus bleibt immer sichtbar
- Weltinteraktion soll auch bei offenem Inventar weiter funktionieren

Crafting ist noch nicht Teil dieser Phase. Das Inventar soll aber spaeter so erweiterbar sein, dass ein Terraria-artiges Rezeptpanel daneben oder daran andocken kann.

## Ausgangslage im Projekt

Die Datenbasis ist bereits passend aufgebaut:

- ein gemeinsames `Inventory` mit `40` Slots
- die ersten `10` Slots sind die Hotbar
- Hotbar und Hauptinventar sind also bereits nur zwei Ansichten derselben Daten
- `InventoryManager` ist host-authoritative und synchronisiert die Slotdaten an den Client

Das ist eine gute Grundlage fuer das geplante UI, weil keine getrennten Datenstrukturen fuer Hotbar und Inventar noetig sind.

## Zielbild der UI

Geschlossen:

```text
[ 0 ][ 1 ][ 2 ][ 3 ][ 4 ][ 5 ][ 6 ][ 7 ][ 8 ][ 9 ]
```

Geoeffnet:

```text
[30][31][32][33][34][35][36][37][38][39]
[20][21][22][23][24][25][26][27][28][29]
[10][11][12][13][14][15][16][17][18][19]
[ 0 ][ 1 ][ 2 ][ 3 ][ 4 ][ 5 ][ 6 ][ 7 ][ 8 ][ 9 ]
```

Wichtig:

- Die Hotbar bleibt an derselben Position.
- Das Inventar klappt nur nach oben auf und wieder nach unten zu.
- Es gibt keine zweite, getrennte Hotbar-Logik.

## Bedienmodell

### Allgemein

- Die Maus bleibt immer sichtbar.
- Das Inventar darf die Welt nicht global sperren.
- Linksklick auf Bloecke soll weiterhin funktionieren, auch wenn das Inventar offen ist.
- Wenn direkt auf ein Inventar-Element geklickt wird, darf die Welt dahinter nicht mitreagieren.

### Konsequenz fuer Input

Das UI darf nur dort Eingaben abfangen, wo es tatsaechlich sichtbar und anklickbar ist.
Unsichtbare oder vollflaechige Overlay-Controls duerfen nicht versehentlich die Welt blockieren.

Praktisch bedeutet das:

- Klick neben das Inventar: Event geht an die Welt
- Klick auf Slot oder Inventarflaeche: Event bleibt im UI
- Hotbar bleibt immer bedienbar
- Welt bleibt auch bei offenem Inventar aktiv

### Zusaetzlicher Input-Vertrag mit der Welt

Fuer dieses Projekt ist wichtig:

- `mouse_filter = STOP` auf UI-Controls ist notwendig, aber nicht allein ausreichend
- die aktuelle Weltinteraktion liest Mausaktionen nicht nur ueber GUI-Events, sondern auch ueber Gameplay-Input
- deshalb braucht es zusaetzlich einen klaren Vertrag zwischen Inventar-UI und Weltinteraktion

Das bedeutet fuer die spaetere Umsetzung:

- das Inventar meldet explizit, wenn eine Mausaktion auf einem echten Inventar-Element begonnen hat
- `BlockInteraction` respektiert diesen Zustand und fuehrt fuer diesen Klick keine Weltaktion aus
- freie Bereiche ausserhalb des Inventars bleiben weiterhin voll fuer die Welt klickbar

Damit ist klar:

- Mouse-Filter loesen die Hit-Detection im UI
- die Gameplay-Schicht entscheidet zusaetzlich, ob Weltinteraktion fuer genau diesen Klick unterdrueckt wird

## Empfohlene Godot-Struktur

Die komplette Darstellung sollte als HUD in einer `CanvasLayer` liegen.

Fuer die Layer-Konvention des Projekts gilt dabei:

- `110` fuer die permanent sichtbare Hotbar als HUD
- `120` fuer aufklappende Fenster- oder Inventarbereiche

Fuer eine erste pragmatische Version darf das Inventar noch in einer gemeinsamen HUD-Struktur gebaut werden.
Spaetestens wenn weitere Fenster wie Crafting oder Chests dazukommen, sollte die Trennung zwischen permanentem HUD und geoeffnetem Inventarbereich klar gezogen werden.

Vorgeschlagene Hierarchie:

```text
Player
└── InventoryHud (CanvasLayer)
    └── Root (Control, fullscreen, mouse_filter = IGNORE)
        └── BottomDock (MarginContainer)
            └── Stack (VBoxContainer)
                ├── InventoryReveal (Control, clip_contents = true)
                │   └── InventoryBody (PanelContainer)
                │       └── BodyPadding (MarginContainer)
                │           └── BodyGrid (GridContainer, columns = 10)
                └── HotbarPanel (PanelContainer)
                    └── HotbarPadding (MarginContainer)
                        └── HotbarRow (GridContainer oder HBoxContainer)
```

Dazu eine wiederverwendbare Slot-Szene:

```text
InventorySlot
├── Icon
├── CountLabel
├── HotkeyLabel
└── SelectionFrame
```

## Warum diese Struktur

### Ein gemeinsames Slot-Widget

Hotbar und Hauptinventar sollten denselben Slot-Typ verwenden.
So bleiben Darstellung, Hover, Klicks, Stapelanzeige und spaeter Drag-and-Drop konsistent.

### Inventar nur als zusaetzliche Darstellung

Das eigentliche Inventar bleibt das bereits vorhandene Datenmodell.
Die UI zeigt nur:

- `0..9` als Hotbar
- `10..39` als zusaetzliche Reihen im geoeffneten Zustand

### Ausgewaehlter Hotbar-Slot ist kein Inventardatum

Wichtig fuer die Architektur:

- der aktuell ausgewaehlte Hotbar-Slot ist Benutzer- bzw. Gameplay-Zustand
- er ist nicht Teil der `Inventory`-Slotdaten
- das Inventar speichert also Inhalte, nicht die aktuelle Auswahl

Damit bleiben sauber getrennt:

- `Inventory`: Welche Items liegen in welchen Slots
- Player/Gameplay: Welcher Hotbar-Slot ist aktuell aktiv
- UI: Wie diese Information dargestellt und bedient wird

### Aufklappen ueber Hoehe statt ueber komplettes Umschalten

Der Bereich oberhalb der Hotbar sollte in einem Wrapper mit `clip_contents = true` liegen.
Beim Oeffnen wird nur die sichtbare Hoehe dieses Bereichs erweitert.
So entsteht der Eindruck, dass das Inventar aus der Hotbar nach oben herauswaechst.

## Input- und Mouse-Filter-Regeln

Das ist der wichtigste Punkt fuer das gewuenschte Verhalten.

### Root

Der fullscreen `Root` sollte `mouse_filter = IGNORE` haben.
Dadurch blockiert er nie pauschal die Welt.

### Interaktive Inventarbereiche

Diese Controls sollten Mausereignisse aktiv abfangen:

- `InventoryBody`
- `HotbarPanel`
- `InventorySlot`

Hier sollte `mouse_filter = STOP` verwendet werden.

### Reine Anzeigeelemente

Diese Controls sollten Mausereignisse nicht selbst behandeln:

- `Icon`
- `CountLabel`
- `HotkeyLabel`
- rein dekorative Rahmen oder Hintergruende

Hier sollte `mouse_filter = IGNORE` verwendet werden.

### Ergebnis

- Die GUI verarbeitet Klicks zuerst, aber nur auf echten UI-Treffern.
- Freie Bereiche bleiben fuer die Welt offen.
- Dadurch koennen Bloecke trotz offenem Inventar normal angeklickt werden.

## UI-Zustaende

Es reichen vier einfache Zustaende:

- `closed`
- `opening`
- `open`
- `closing`

Regeln:

- `closed`: nur Hotbar sichtbar
- `open`: Hotbar plus drei Inventarreihen sichtbar
- `opening` und `closing`: Zwischenzustand fuer Tween/Animation
- waehrend eines laufenden Toggles keine zweite Toggle-Aktion starten

## Animation

Empfohlen ist eine einfache Tween-Animation.

Nicht empfohlen:

- starre AnimationPlayer-Loesung fuer viele Layoutwerte
- vollstaendiges Ein- und Ausblenden des ganzen HUDs

Empfohlen:

- `InventoryReveal` behaelt seine Breite
- nur die Hoehe wird animiert
- optional zusaetzlich leichtes Fade oder kleiner Offset
- Hotbar bleibt visuell stabil stehen

Damit bleibt das Verhalten robust, auch wenn sich spaeter Slotgroessen oder Padding aendern.

## Bedienung fuer die erste Inventarversion

Geplante Aktionen:

- `E` oder `Tab`: Inventar oeffnen oder schliessen
- `1-0`: Hotbar-Slot auswaehlen
- Mausrad: Hotbar-Slot wechseln
- Linksklick auf Slot: aufnehmen, ablegen, tauschen oder zusammenfuehren
- Rechtsklick auf Slot: splitten oder einzelne Items ablegen
- `Shift` + Klick: Schnelltransfer zwischen Hotbar und Hauptinventar

Wichtig:

- Offenes Inventar bedeutet nicht, dass Gameplay pausiert wird.
- Es ist nur eine erweiterte Sicht auf dieselben Slots.

## Verantwortung der Systeme

### Inventory

Bleibt reine Datenklasse:

- Slotinhalte
- Stapelgroessen
- Slotzugriff
- spaeter auch Move/Split/Swap-Helfer
- kein Wissen ueber aktuell ausgewaehlten Slot
- kein Wissen ueber Maus, Cursor oder UI-Zustaende

### InventoryManager

Bleibt Netzwerk- und Autoritaetsschicht:

- host-authoritative Aenderungen
- Full Sync beim Join
- Delta Sync bei Slot-Aenderungen
- Inventar-Intents vom Client validieren
- serverseitige `move`, `swap`, `merge`, `split`, `quick_transfer`-Operationen anbieten
- Client sendet keine direkten Slot-Mutationen, sondern nur erlaubte Aktionen

### InventoryHud

Bleibt reine Darstellungs- und Interaktionsschicht:

- Slots erzeugen
- Slotdaten anzeigen
- Toggle-Zustand verwalten
- Klicks an die Inventarlogik weiterreichen
- UI-Treffer eindeutig erkennen und an die Gameplay-Schicht rueckmelden
- Cursor-Stack bzw. gehaltenen Slot nur als Interaktionszustand fuehren, nicht als persistentes Inventardatum

## Vorschlag fuer spaetere Erweiterungen

Noch nicht jetzt umsetzen, aber beim Design mitdenken:

- Tooltip fuer Itemnamen
- Drag-and-Drop mit nativen `Control`-Hooks
- Chests als zweite `Inventory`-Instanz im selben UI-Konzept
- spaeteres Crafting-Panel eher nach Terraria-Art als Rezeptliste statt Minecraft-3x3

## Empfohlene Umsetzungsreihenfolge

### Phase 1

- bestehende Hotbar-UI zu einer gemeinsamen `InventoryHud` umbauen
- Slot-Widget vereinheitlichen
- BodyGrid fuer Slots `10..39` ergaenzen
- Oeffnen/Schliessen visuell umsetzen
- noch keine neue Inventarmutation einfuehren

### Phase 2

- Input-Vertrag zwischen UI und `BlockInteraction` festziehen
- sicherstellen, dass UI-Treffer keine Weltaktionen ausloesen
- sicherstellen, dass freie Bereiche trotz offenem Inventar weiter an die Welt gehen
- Cursor-Stack und Interaktionsregeln fachlich definieren

### Phase 3

- primitive Inventar-Aktionen fachlich festlegen
- z. B. `pickup_full`, `place_full`, `place_one`, `swap`, `merge`, `quick_transfer`
- serverseitige Operationen in `Inventory` und `InventoryManager` vorbereiten
- noch keine rein lokale Dauer-Loesung bauen, die spaeter wieder ersetzt werden muss

### Phase 4

- host-authoritative Inventar-Aktionen fuer Move/Swap/Split einbauen
- Client-Intents statt direkter lokaler Manipulation
- Multiplayer-Sync fuer UI-Interaktionen sauber abschliessen

### Phase 5

- Quick-transfer
- Tooltips
- Drag-and-Drop
- spaeter Crafting-Erweiterung

## Designentscheidung

Die wichtigste Entscheidung fuer dieses System lautet:

Es gibt genau ein Spielerinventar mit einer Hotbar als Unterbereich.

Nicht:

- getrennte Inventar- und Hotbar-Daten
- globalen Inventarmodus
- globales Blockieren der Welt bei offenem Inventar

Sondern:

- ein gemeinsames Inventar
- Hotbar permanent sichtbar
- Inventar klappt darueber auf
- UI blockiert nur dort, wo wirklich UI angeklickt wird
- Weltinteraktion respektiert diese UI-Treffer explizit
- Inventar-Aenderungen bleiben host-authoritative

## Ergebnis

Dieses Modell passt gut zur bestehenden Architektur des Projekts und ermoeglicht:

- Core-Keeper-artige Darstellung
- staendiges Weiterinteragieren mit der Welt
- spaetere Erweiterung um Chests und Crafting
- klare Trennung von Daten, Netzwerk und UI
