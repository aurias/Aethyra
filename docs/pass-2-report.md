# Pass 2 — Gale traversal and the homeland loop (+ Ember Spark)

6 October 2026. Scope: [framework](design/Aethyra-Gameplay-and-Implementation-Framework-v0.2.md)
§7 and Pass 2, plus (by request) an Ember combat skill, Spark, that
combines with Gust - an early slice of Pass 3's live combinations.

## Revisions

| Commit | Content |
|---|---|
| `2134761` | Server: elevation, terrain rules, featherfall, jump, ledge Gust, Spark, combinations, content, monster HP fix, tests |
| `32d4437` | Client: landing preview, slide animations, keys, protocol 3 |
| (this commit) | Reports, status, ledger, READMEs |

Package: CI run 15 (`Aethyra-windows` artifact of `32d4437`) built green.

## What a player finds

- The meadow (level 0) rises to a terrace (level 1) by stairs. East on
  the terrace a lookout and its spur (level 2) can only be reached by
  jumping; Skyreeds grow there and give Breeze Reeds - an aerial
  harvest other cultures cannot easily reach.
- Wren the Ridge-runner, at the top of the stairs, teaches Featherfall
  (F) and Upward Jump (G) and explains them; Ama still runs her tonic
  exchange. The arrival clearing is free of hoppers.
- Facing a cliff edge shows where you would land (green) or why you
  cannot (red: too high, too wide, corner in the way, someone there).
  The server applies the same rule and explains any refusal.
- Featherfall drifts down one level (two at rank 2); Upward Jump climbs
  one level over a one-cell cliff (two cells at rank 2, which reaches
  the terrace from the meadow without stairs).
- Gust at a ledge blows enemies down to the level below. They land
  unhurt (fall harm is undecided; configurable) but stagger, cannot
  attack up the cliff and must walk around.
- Spark (T, Ember) hits the selected monster for fire damage with a
  chance to burn. Press Y to add Spark to the next Gust: everything the
  gust moves also takes the fire and may burn. Each hue pays its own
  share. Ember is a developer grant until altars exist (see below).

## Evidence

Automated (`server/tools/worldtest.py`, real servers and protocol
clients): 119 checks - baseline 25, pass1 44, migration 10, pass2 25,
spark 15 - all passing on the Linux server and on the Windows server
under Wine.

pass2 covers Wren's teaching, stairs up and down by ordinary walking,
featherfall (and the second client seeing it), wrong-way, too-wide and
not-at-an-edge refusals, the jump onto the lookout, the Skyreed harvest,
the two-level drop needing rank 2, diagonal obstruction at a solid
corner, an occupied landing, Gust pushing a hopper off the ledge
unharmed (seen by both clients), the fallen hopper unable to bite up
the cliff, Gust not reaching the other level nor pushing up a cliff, a
disconnect in mid-featherfall leaving the player at the landing, and
the skills surviving a host restart.

spark covers: not learned; learned without Ember access; the developer
grant; 8 fire damage to the selected hopper paid in Ember; burning
ticks; out-of-range and across-the-cliff refusals; Gust + Spark pushing
and burning (Gale 15 and Ember 9 drawn separately; damage seen by the
second client); the combination putting Spark on cooldown; an
incompatible pair (Dash + Spark); the modifier's hue too low (nothing
spent, Spark named); a player without Spark unable to add it.

Manual (Linux client, Xvfb): landing previews at the terrace and
lookout edges; the featherfall drift and the jump arc with wind
effects; Spark and Gust + Spark with the fire damage number and the
combined energy message; HUD Ember line.

Found and fixed: `battle.conf` never set `monster_hp_rate`, whose
server default (0) left every monster with 1 HP in the demo. Monsters
now have their database HP (Gust Hoppers 70).

Not verified: the Windows client at runtime (CI build only); two real
GUI clients together; trading/storing vessels (unchanged since Pass 1).

## Fix after release: hosting an older world

A world hosted from an earlier build kept that build's configuration,
because Host World copied the template only when a world was created.
The Pass 2 server then crashed at the first login (no hue definitions),
which the client reported as an `SDLNet_TCP_Recv` error. Hosting now
refreshes a world's game content (conf/, db/, npc/, data/) from the
running build on every launch, keeping its saves and internal password;
the server also refuses to start, with a message in the world's log,
if hue definitions are missing. Tested with the real Linux client
hosting a Pass 0 world folder with saves: the world starts, both
characters log in and migrate.

## Saves and compatibility

The save format is unchanged from Pass 1: Pass 1 worlds open directly.
Characters learn the new skills from Wren. Protocol 3 replaces 2;
older clients are refused at login.

## Provisional choices

All in `server/world/db/hue` (skills, balance, combos, regions) and the
map: skill costs and reach; fall stagger 2 s and 0% fall damage; burn 3
ticks of 2; Gust + Spark at 100% damage for 75% of Spark's energy;
Ember regenerates at half rate in the meadow; plants do not block
landings; Ember only through a GM grant. See the [decision ledger](decision-ledger.md).

## Limitations and next

- Only one elevation map; terraces do not overlap (no bridges/tunnels).
- No shadow under jumping beings; placeholder cliff art.
- Spark and the live combination are a slice of Pass 3: there are no
  saved assemblies, sustained effects or modifier selector UI beyond Y.
- Ember has no altar, homeland, vessel or region of its own yet.
- Monsters other than Gust Hoppers do not exist; combat numbers are
  provisional.
