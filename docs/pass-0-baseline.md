# Pass 0 — Baseline reproduction and dependency map

5 October 2026. Scope: [handoff](design/Aethyra-Coding-Agent-Handoff-v0.2.md), Pass 0.

## Baseline revision

- Source: branch `claude/peaceful-einstein-4rxrvh`, commit `c51f1ba`
  (design docs only on top of `9e01299`, the source of the confirmed
  Windows demo package from CI).
- Known working release: the `Aethyra-windows` artifact the user ran on
  5 October (S-AF/S-AG). Keep it as the rollback build; Pass 1 saves are
  not readable by it (see the decision ledger).

## Build reproduction (this environment: Linux container, no Windows)

| Build | Command | Result |
|---|---|---|
| Server, Linux | `cmake -S server -B B && cmake --build B` | built clean |
| Server, Windows | `cmake -S server -B W -DCMAKE_TOOLCHAIN_FILE=server/cmake/mingw-w64-x86_64.cmake && cmake --build W --target aethyra-server` | built clean (`aethyra-server.exe`) |
| Client, Linux | `cmake -S . -B C && cmake --build C` | built clean |
| Client, Windows | `.github/workflows/windows-build.yml` (MSYS2 on windows-latest) | not rebuilt here; CI only |

## Playable gate

Automated with `server/tools/worldtest.py BUILD_DIR baseline`: a fresh world
copied from `server/world`, two protocol clients speaking the game client's
packets, every check printed as PASS/FAIL.

| Check | Linux server | Windows server under Wine |
|---|---|---|
| Two players see each other | tested | tested |
| Wind Scythe cuts herbs and windflowers; both clients see the plant go | tested | tested |
| Harvest yields 3 Meadow Herbs + 3 Windflower Petals | tested | tested |
| Wind Scythe spends Gale energy | tested | tested |
| Gust knocks a Gust Hopper back, no damage; second client sees it | tested | tested |
| Dash moves the player; second client sees it | tested | tested |
| Ama's exchange (3 herbs + 3 petals -> Gale Tonic) | tested | tested |
| Gale Tonic consumed on use | tested | tested |
| Reconnect keeps inventory and position | tested | tested |
| Stop-file shutdown, restart keeps inventory and position; friend rejoins | tested | tested |

Real client (Linux build, Xvfb): started with `--host-world friends`, it
created the world, launched `aethyra-server`, logged in, entered gale-1 and
used Wind Scythe and Dash while a protocol client joined and walked beside
it (screenshots taken). Killing the client stopped the server within 2 s
through the parent-process check; the character was saved.

Not verified here: the Windows client (no Windows machine; the user's
5 October confirmation is the evidence), a second real GUI client (the
second player was a protocol client), internet/VPN joining.

Findings during the run:

- Logging in to a hosted world shows the legacy updater warning "Unable to
  verify that your current data matches the data on the server" before Play.
  Harmless but confusing; recorded as missing polish.
- A wandering Gust Hopper bit the host during the visual run; the demo has
  no safe zone around the arrival point. Unchanged (combat/death policy is
  out of scope).

Representative save: the world left by the baseline run (accounts, two
characters, inventory, positions) is kept as a migration fixture; see Pass 1.

## Dependency map (legacy statistics, HP/SP, progression, inventory, skills)

Paths under `server/src` unless marked client (`src/`).

**Stats STR/AGI/VIT/INT/DEX/LUK** — `ATTR` (`mmo/enums.hpp`); computed in
`pc_calcstatus` (`map/pc.cpp`): STR → carry weight and attack; AGI → flee,
attack speed; VIT → max HP, defence, HP regeneration; INT → legacy max SP
(overridden), magic attack/defence; DEX → hit, attack speed; LUK → crit,
flee2, drop rate. Raised with points (`pc_statusup`, 0x00bb). Character
creation requires a 30-point sum (`char/char.cpp make_new_char`; client
`eathena/gui/charcreate.cpp`). Client status window shows them.

**HP/SP** — max HP from level and VIT (`pc_calcstatus`); SP is the demo's
Gale energy: `max_sp = hue_gale_max_energy(level)`, `nhealsp = 3`, refilled
at login (`pc_authok`). Natural regeneration timer `pc_natural_heal`
(1 s for SP via `battle.conf`). Spent by `pc_heal(sd, 0, -cost)`. Saved as
`hp,max_hp,sp,max_sp` in the character line; sent as 0x00b0 types 5–8.
Item scripts `heal hp, sp` (herb, petal, tonic) restore SP.

**Levels** — `base_level`/`job_level` (u8), exp from monster kills
(`mob_damage` → `pc_gainexp_reason`), base level-up grants status points,
job level-up grants a legacy skill point. Legacy skill tree (`SkillID`,
`skill_db.txt`, 0x010f/0x0112) holds only Emote/Trade/Party.

**Inventory** — generated `Item{nameid, amount, equip}`; non-equipment
merges by item id in `pc_additem`; copies by value through floor items,
storage (`storage.txt`), trade and the char↔map `CharData` transfer.
Text format: 12 comma fields per item, only id/amount/equip kept.

**Save format** — `athena.txt`, one tab-separated line per character
(`mmo_char_tostr` / `impl_extract(CharPair)` in `char/char.cpp`), no
version field; a line that fails to parse is skipped and lost on the next
save. `CharData`/`Item` are generated from `server/tools/protocol.py`.

**Hue skills** — client keys X/C/V → `LocalPlayer::useHueSkill` → 0x0216
→ `clif_parse_AethyraUseSkill` → `hue_use_skill` (`map/hue.cpp`): checks
death, a per-skill cooldown (`hue_ready`, not saved) and `status.sp`;
costs are literals in `skill_info`. No learned-skill, mastery, supply or
activation checks. Wind Scythe kills vegetation with `mob_damage`, so
harvests use the normal drop/exp path. Dash and knockback broadcast 0x0217.

**What Pass 1 changes**: the Gale reserve moves out of SP into explicit
hue state; skill costs and limits move into data; inventory items gain lot
state. HP, attack, defence, weight and the six stats stay on their legacy
formulas as a compatibility layer until a later pass replaces them.
