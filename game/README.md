# Aethyra (Godot)

The game, as a Godot 4.7 project. See
[docs/godot-parity-report.md](../docs/godot-parity-report.md) for what it covers,
how it is built and how to test it.

| Directory | Contents |
|---|---|
| `core/` | Authoritative rules: hue definitions, terrain, the hue resolver and the World. |
| `net/` | The `Net` autoload: hosting, joining and replication. |
| `ui/` | The client: map and being views, effects, HUD and windows, menu. |
| `data/` | Hue tuning, the map, items, monsters, dialogue. |
| `assets/avalon/` | Tileset pieces (cut by `tools/art/cut_avalon.py`). |
| `tests/` | Headless rules tests and the two-instance network test. |
