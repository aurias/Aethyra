# Godot parity pass (6 Oct 2026)

**Goal:** replace the 2009 client and tmwAthena server with a Godot 4 game that
reaches parity with the Pass 2 demo, using Leonard Pabin's Whispers of Avalon
grassland tileset. The C++ build stays in the repository as the reference and
fallback (`src/`, `server/`, `.github/workflows/windows-build.yml`).

**Download:** the `Aethyra-godot-windows` artifact of the
[Godot build workflow](https://github.com/aurias/Aethyra/actions/workflows/godot.yml)
(first green run: [37543293729](https://github.com/aurias/Aethyra/actions/runs/37543293729)).
Unzip it and run `Aethyra.exe`. `PLAY.txt` inside lists the controls.

## Architecture

| Part | Where | Notes |
|---|---|---|
| Rules | `game/core` | Plain GDScript with no scene dependencies, driven by an explicit clock, so tests run it headless and deterministically. |
| Hue definitions | `game/data/hue` | The same files and formats as `server/world/db/hue`; `HueDB` parses them. |
| Terrain | `game/core/game_map.gd` | A port of `terrain.cpp`. The host's rules and the client's landing preview run the same code on the same data. |
| Resolver | `game/core/hue_rules.gd` | A port of `hue.cpp`, step for step (validate, plan supply, roll, commit), keeping the reason codes. |
| World | `game/core/world.gd` | Movement (A* paths, steps), monsters, combat, death, items and lots, NPC dialogue, saves and host-only GM fixtures. |
| Network | `game/net/net.gd` | A listen server: the host runs the World and an ENet server on UDP 24680. Friends send requests and the host sends events. Joining checks a protocol number and the world password. |
| Client | `game/ui` | A mirror of host events, procedural being art, animations, the landing preview, the HUD and its windows, chat and dialogue. |
| Map | `tools/content/make_meadow.py` → `game/data/maps/gale-1.txt` | Same layout as the demo map (meadow, terrace, three-wide stairs, lookout, spur, pond, clearing). South faces are two cells tall to match the art. The script checks that levels meet only at stairs. |
| Art | `tools/art/cut_avalon.py` → `game/assets/avalon` | Pieces cut from `art/whispers-of-avalon/source`; credits are in `art/whispers-of-avalon/CREDITS.md`. |

**Identity.** There are no accounts. A character is a name inside a host's
world, bound to the joining installation's random token (`user://identity.json`).
Characters are saved as JSON in `user://worlds/<world>/characters/` on the host,
which on Windows is `%APPDATA%\Godot\app_userdata\Aethyra\…`. Saves happen when a
player leaves, when the host quits and every 30 s. Each save writes a temporary
file and renames it into place.

## Parity with the Pass 2 demo

| Feature | Legacy | Godot | Evidence |
|---|---|---|---|
| Host a world, friends join | Host World launches `aethyra-server` | Built in (ENet) | `tests/net_test.sh` |
| Character records, origin grant, skill points per level | ✓ | ✓ | rules tests: pass1 |
| Dash, Gust, Wind Scythe; energy, current, allowance, cooldowns | ✓ | ✓ | pass1 |
| Vessel lots, supply selection, overload consent, strain and destruction | ✓ | ✓ | pass1 |
| Forced and seeded rolls, duplicate requests | ✓ | ✓ | pass1 |
| Learning with every gate explained | ✓ | ✓ | pass1 |
| Steady Flow, better vessel or mastery changes the outcome | ✓ | ✓ | pass1 |
| Elevation, stairs, Featherfall, Upward Jump, every leap refusal | ✓ | ✓ | terrain, pass2 |
| Ledge Gust: nonlethal falls, no attacks across levels | ✓ | ✓ | pass2 |
| Landing preview, slide animations | ✓ | ✓ | screenshots under Xvfb |
| Spark, burning, Gust + Spark ignite, refusals | ✓ | ✓ | spark |
| Wren teaches; Ama explains and brews the Gale Tonic | ✓ | ✓ | pass2, world |
| Plants harvested, hoppers fight back, drops, respawns, experience and levels | ✓ | ✓ | world |
| Death and respawn | tmwa default | Wake in the clearing, healed, with 5 s of grace | world |
| Host-only developer fixtures (`@hue…`, `@item`, `@warp`, `@spawn`, `@level`) | GM accounts | Host only | pass1, net test |
| Restart keeps everything | ✓ | ✓ | saves, net test |

**Test totals.**
- `godot --headless -s res://tests/run_tests.gd`: 108/108 checks across data,
  terrain, pass1, pass2, spark, world and saves.
- `tests/net_test.sh`: 11/11 checks.
- Both run in CI on every push that touches `game/`.

## Differences and gaps (read before playtesting)

**Not in the Godot build yet (the legacy build had these):**
- Dropping items on the ground and picking them up. Monster drops go straight
  into the killer's pack.
- Trade, storage, equipment, shops, party, emotes, minimap.
- An options window (audio, keys).
- Sound and music.

**Different on purpose:**
- **Accounts:** names plus an install token replace login accounts.
  Moving a character to another PC is not supported yet.
- **Saves:** old `athena.txt` saves are not imported. The Godot worlds start
  fresh.
- **Balance:**
  - Level 1 HP rose from tmwa's derived value to 60.
  - Gust Hoppers hit for 2–5 instead of 3–6 and notice you from 6 cells.
  - The basic attack is 3–6 + level every 0.9 s; there are no stats or
    equipment yet.
  - These numbers are in `game/data/world/mobs.txt` and `core/world.gd`.
- **Characters and creatures:** drawn procedurally. The Avalon set has no
  character sprites, so this is placeholder art in the tileset's palette.
- **Keys:**
  - 1–6 are the hotbar.
  - Q primes Spark (the old Y).
  - F, G and T are freed up.

**Not verified:**
- **The Windows executable at runtime.** CI exports it, and the same build runs
  all tests on Linux. Under this container's Wine 9.0 even the stock Godot
  4.7.2 template crashes before reaching our code, so I could not smoke-test
  the `.exe` here. The first run on Windows is the check.
- **Hosting over the internet:** nothing opens the port automatically (no
  UPnP). The host must forward UDP 24680.

## How to work on it

```sh
cd game
godot --headless --import                      # first time, and after adding classes
godot --headless -s res://tests/run_tests.gd   # rules (add "-- pass2" to run one scenario)
tests/net_test.sh                              # two real instances over ENet
tools/lint.sh                                  # parse-check every script
godot --path . -- --host Meadow Me             # play (or open the project in the editor)
```

**Automation flags** (after `--`):
- `--host <world> <name>` or `--join <address> <name>`, with `--port`.
- `--do "<steps>"` runs a script. Steps are `wait`, `key`, `hold`, `say`,
  `talk`, `choose` and `click`.
- `--shot <png> <seconds>` saves a screenshot.
- `--log-events` prints the events received.
- `--quit-after <seconds>`.

**Changing content:**
- **Map:** edit `tools/content/make_meadow.py` and re-run it.
- **Art pieces:** edit `tools/art/cut_avalon.py`.
- **Hue numbers:** `game/data/hue`.
- **Items, monsters, dialogue:** `game/data/world`.
