# Decision ledger

Working policies chosen during implementation. "Provisional" means a
reversible test default, not established lore; see
[the framework](design/Aethyra-Gameplay-and-Implementation-Framework-v0.2.md) §13.

| Date | Decision | Evidence/status | Replace when |
|---|---|---|---|
| 2026-10-05 | Design docs live in `docs/design`; the user's labels S-AE..S-AH win; my world answers are S-AI | User upload, 5 Oct | — |
| 2026-10-05 | Baseline = commit `c51f1ba` (source of the confirmed demo + docs); rollback build = the 5 Oct `Aethyra-windows` artifact | Pass 0 | A newer confirmed release |
| 2026-10-05 | Death/PvP/combat keep tmwa behaviour as a labelled compatibility policy | Framework §7, §13 | Dedicated combat/death pass |
| 2026-10-05 | Hue state is part of the character record (`CharData::hue`), saved in the same `athena.txt` line as inventory, so one file write covers both | Pass 1, tested | A transactional store replaces flat files |
| 2026-10-05 | A vessel stack is one lot: charge per unit, condition, flags on the inventory item; stacks merge only when lots are identical; draws spread over every unit | Pass 1, tested | Per-instance items are needed |
| 2026-10-05 | Supply routing: personal reserve first (up to the character's channel), then up to three selected stacks in order; a stack delivers its safe current whatever its size | Framework §5.2 proposal; tested | Equipment/conduits change routing |
| 2026-10-05 | Overload needs explicit player consent per attempt (Shift); success and per-stack destruction are rolled separately; failure still spends the energy; surviving stacks lose condition | S-AA/S-AB; provisional formulas in `balance.conf` | Playtest of risk feel |
| 2026-10-05 | Personal channel is a hard limit (characters do not overload themselves) | Provisional | Self-overload is designed |
| 2026-10-05 | Activation allowance: per-hue from mastery plus a character-wide ceiling of 3; instantaneous actions hold it for their execution time | Framework §3.3 proposal | Sustained actions (Pass 3) |
| 2026-10-05 | Awards: proficiency, mastery progress (and optional experience) per meaningful outcome; −15% per repeat of the same skill within 60 s, floor 25%; empty casts award nothing | Framework §3.2; provisional | First sustained playtest |
| 2026-10-05 | Skill points: one per character level, granted once per level (also retroactively to migrated characters) | Recovered CP-S | — |
| 2026-10-05 | Homeland mastery cap 10; raising it is for cores (S-AI) | Provisional | Core content exists |
| 2026-10-05 | Vessels arrive precharged; nothing recharges them; GM refill only | Framework §13; provisional | Harvest-to-use pacing assessed |
| 2026-10-05 | Tempered Reed is a GM-only test fixture (no recipe) so no crafted vessel creates energy from empty inputs | Pass 1 | Process crafting (Pass 4) |
| 2026-10-05 | Legacy saves migrate at login; SP becomes Gale energy (clamped); old reeds become full lots; files backed up to `*.pre-hue1`; no reverse migration | Pass 1, tested | — |
| 2026-10-05 | Protocol: clients send 100 + Aethyra protocol (2); tmwa treats them as dialect 1; older clients refused | Pass 1 | Next protocol change |
| 2026-10-05 | Origins are neutral; character creation still defaults to origin 1 (Gale Meadow) | Framework §3.1 | Second homeland |
| 2026-10-06 | Gameplay elevation is authored in the client map (property) and exported for the server; walkable cells on different levels may only meet at stairs (checked at export) | Framework §7; tested | Overlapping floors |
| 2026-10-06 | One leap rule (reach in cliff cells, level change, landing) for featherfall, jump and forced falls, mirrored in the client preview | Framework §7; tested | — |
| 2026-10-06 | Fall from a ledge: nonlethal, +2 s stagger, 0% damage (configurable) | S-AE leaves harm undecided; framework proposal | Fall rules designed |
| 2026-10-06 | No attacks, Gust or Spark across levels (a stair joins both) | Framework §7 | Ranged/vertical combat design |
| 2026-10-06 | Plants do not block landings; beings do | Playtest of the lookout | — |
| 2026-10-06 | Traversal is taught by Wren (an explicit teaching grant), not by origin | Framework §9.3 (teaching ≠ observation) | Homeland onboarding designed |
| 2026-10-06 | Ember access and Spark are developer (GM) grants until altars exist | Framework Pass 3 ("developer-only second-hue grant") | Pass 5 altar |
| 2026-10-06 | Live combinations come from a registry; the modifier pays its share from its own hue, holds its own activation and cooldown; any part failing to plan refuses the whole action; any part fizzling fizzles the whole | Framework §4.2; provisional | Pass 3 assemblies |
| 2026-10-06 | monster_hp_rate set to 100 (the server default 0 gave monsters 1 HP) | Bug found in Pass 2 | — |
| 2026-10-06 | Hosting a world refreshes its game content (conf, db, npc, data) from the running build's template, keeping save/ and the world's internal password; the server refuses to start without hue definitions | Bug: old worlds crashed the new server at login (SDLNet_TCP_Recv on the client) | Worlds with custom content |
| 2026-10-06 | Replace the 2009 client and tmwAthena with a Godot 4.7 game in `game/`; the C++ build stays as the reference and fallback | User: "Godot 4 is fine"; crash reports on the legacy client | — |
| 2026-10-06 | Listen server: the host's game runs the authoritative World; friends send requests over ENet (UDP 24680) and get events; every rule stays on the host | Parity report; `tests/net_test.sh` | Dedicated servers are needed |
| 2026-10-06 | No accounts: a character is a name in a host's world, bound to the joining installation's token; JSON saves on the host | Parity report | Moving characters between PCs matters |
| 2026-10-06 | Hue data files keep the server's formats and are copied into `game/data/hue`; `game/core` ports `hue.cpp`/`terrain.cpp` step for step, reason codes included | 108 headless checks | — |
| 2026-10-06 | Whispers of Avalon (Leonard Pabin) under CC-BY 3.0; pieces cut by script from the published sheets; south cliff faces are two cells tall to fit the art | `art/whispers-of-avalon/CREDITS.md` | Commissioned art |
| 2026-10-06 | Characters and creatures are drawn procedurally until sprites exist | The tileset has no characters | Character art arrives |
| 2026-10-06 | Monster drops go straight to the killer's pack (no ground items yet) | Simplification for parity | Trading and ground items |
| 2026-10-06 | Level 1 HP 60; hopper hits 2–5, sight 6; player hit 3–6 + level every 0.9 s; 5 s grace after waking | Provisional, from the first Godot playtest shots | Combat pass |
