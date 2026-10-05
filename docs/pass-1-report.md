# Pass 1 — Character, skills and hue supply

5 October 2026. Scope: [handoff](design/Aethyra-Coding-Agent-Handoff-v0.2.md) Pass 1;
[framework](design/Aethyra-Gameplay-and-Implementation-Framework-v0.2.md) §3–6, §12.

## Revisions

| Commit | Content |
|---|---|
| `6af423b` | Server: hue records, vessel lots, shared resolver, migration, fixtures, tests |
| `fd7f6bd` | Client: protocol 2, Hues/Skills windows, HUD, vessel supply UI |
| (this commit) | Reports, status, ledger, README |

Runnable package: the `Aethyra-windows` artifact of the CI run for the
latest commit on `claude/peaceful-einstein-4rxrvh` (run 12 built `fd7f6bd`
green). Rollback: the 5 October demo artifact (see migration below).

## What changed for a player

- Gale energy is its own record: capacity, regeneration, the current a
  character channels alone, flow and activation allowance all come from
  Gale mastery (0–50, capped at 10 in the homeland for now).
- Dash, Gust and Wind Scythe have ranks (3/3/2) bought with skill points
  (one per character level), gated by level, mastery and proficiency.
  Proficiency grows from meaningful uses: an enemy actually displaced, a
  plant actually harvested, a Dash longer than two tiles. Repeats inside
  a minute count for less. Steady Flow is a permanent perk.
- Breeze Reeds are vessels: each stack holds 20 energy per reed and
  delivers at most 4 current however many reeds it has. Select up to
  three stacks as supply. Actions draw on the character first, then on
  the selected stacks in order.
- When only overloading a stack could deliver the current, the server
  refuses and says how hard the stack would be pushed. Using the skill
  again with Shift accepts the risk: the action may fizzle (energy still
  spent) and the stack may wear down or disintegrate entirely. Other
  stacks are never touched.
- Hues and Skills windows, the HUD line and inventory panel explain
  every value and refusal with the server's reason codes.

## Evidence

Automated (`server/tools/worldtest.py`, real servers, protocol clients;
79 checks, all passing on the Linux server and on the Windows server
under Wine):

- **baseline** (24): the Pass 0 gate through the new resolver — two
  players, all three skills, harvest, Ama's exchange, tonic, reconnect,
  host restart.
- **pass1** (45): records and starting grants; safe use from the
  personal reserve; insufficient energy rejected with nothing spent; a
  duplicated request resolved once; proficiency/mastery progress from a
  displaced enemy and none from empty air; every learning prerequisite
  refused with its reason, then learned; current-limited Gust despite 80
  energy; unselected vessels never drawn; reeds supplying the missing
  current safely and staying reusable (charge accounting checked);
  rank 3 overload refused before spending; doubling the stack adds no
  safe current; forced success-with-strain, failure, success-with-
  destruction and failure-with-destruction, destroying exactly the
  selected stack; the same seed repeating the same outcome; the test-
  grade reed, mastery 20 and Steady Flow each making the action safe;
  Dash rank 3 travelling further than rank 1; a non-GM unable to use
  the fixtures; dropped reeds keeping charge and condition when a second
  player picks them up; skills, inventory, lots and mastery surviving
  reconnect and host restart; the second client seeing vessel-backed
  knockback.
- **migration** (10): a Pass 0 save (`fixtures/demo-save-v0`) loads with
  inventory and position intact; SP 68 becomes Gale energy 60 (capacity);
  introductory skills and the level-2 skill point granted; old reeds
  become full vessels; Wind Scythe works; `athena.txt`/`storage.txt` are
  backed up to `*.pre-hue1`; the saved file is in the new format and
  reloads.

Manual (Linux client build, Xvfb, real GUI): login with protocol 2;
Gust from the keyboard; HUD Gale bar and allowance line; Character and
Hues window; Skills window upgrade to ranks 2 and 3; current-limit
message; Supply selection with S1 marker and inventory panel;
vessel-backed Gust message; overload warning; Shift+C with a stack
disintegrating and the loss explained. Windows CI built the client and
package.

Not verified: the Windows client running (no Windows machine; CI only),
two GUI clients together, trading and storage of vessel stacks (same
`Item` copy path as the tested drop/pickup, but not exercised),
internet/VPN play.

## Migration and rollback

Old saves migrate on first load; the char server first copies
`athena.txt` and `storage.txt` to `*.pre-hue1`. The first demo's server
cannot read new saves (it would skip every character). To roll back,
restore the `*.pre-hue1` files and use the 5 October build. Clients and
servers must match: older clients are refused at login ("client too
old").

## Provisional choices (all in `server/world/db/hue`, balance v1)

Mastery rows (capacity 60–320, channel 6–30, allowance 1–4, flow 0–80%);
skill costs and ranks; Breeze Reed 20 energy/4 current; Tempered Reed
(test grade) 40/9, obtainable only with GM `@item 706`; overload chance
formulas and wear; award sizes and the 15%-per-repeat decay; homeland
mastery cap 10; vessels arrive precharged and nothing recharges them
yet (GM `@huecharge`). See the [decision ledger](decision-ledger.md).

## Limitations and next

- Legacy statistics (STR…LUK, attack, defence, weight) still drive
  combat, HP and carrying, and still appear in the Status window and
  character creation, as compatibility adapters.
- Proficiency only gates upgrades; it has no other effect yet.
- Every action is instantaneous; sustained actions, live combinations
  and saved assemblies are Pass 3.
- The arrival point has no protection from wandering Gust Hoppers; the
  hosted login shows the legacy updater warning.
- Next active pass per the roadmap: Pass 2, Gale traversal (elevation,
  featherfall, upward jump, ledge Gust).
