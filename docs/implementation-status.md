# Implementation status

Categories: **tested** (automated or manual run recorded), **unverified**
(implemented, not exercised), **provisional** (tuning/test policy),
**missing**, **blocked**.

## Pass 0 — baseline (5 Oct 2026)

- **Tested:** server Linux and Windows (Wine) builds; Linux client build;
  `worldtest.py baseline`; Host World from the real Linux client with a
  second player. Report: [pass-0-baseline.md](pass-0-baseline.md).
- **Unverified here:** Windows client (user-confirmed only).

## Pass 1 — character, skills and hue supply (5 Oct 2026)

Report: [pass-1-report.md](pass-1-report.md).

- **Tested:** hue records and saves; origin grants and legacy migration
  with backup; skill points per level; ranks and learning with reasons;
  proficiency and mastery awards with diminishing repeats; the shared
  resolver for Dash/Gust/Wind Scythe (energy, current, allowance,
  cooldown, path); vessel lots (precharge, merge rules, draw, strain,
  destruction of the selected stack only); overload confirmation and
  forced/seeded outcomes; flow perk, better vessel and mastery each
  changing the outcome; duplicate requests; GM-only fixtures; drop and
  pickup preserving lots; reconnect and restart. Linux and Windows
  (Wine) servers: 79/79 checks. Real Linux client: HUD, Hues and Skills
  windows, supply selection, overload warning and Shift risk.
- **Unverified:** Windows client at runtime (CI build only); trade and
  storage of vessel lots; two GUI clients at once.
- **Provisional:** all numbers in `server/world/db/hue` (balance v1);
  Tempered Reed; precharged vessels with no recharge.
- **Missing:** vessel recharge; proficiency effects beyond gating;
  homeland choice at character creation; replacing legacy stats in the
  Status window and character creation; sustained actions (Pass 3);
  safe arrival area; skipping the updater warning when hosting.
- **Blocked:** nothing.

## Pass 2 — Gale traversal and homeland loop, with Ember Spark (6 Oct 2026)

Report: [pass-2-report.md](pass-2-report.md).

- **Tested:** map elevation export and consistency check; terrain rules
  for walking, Dash, Gust, featherfall, jumps and falls; every leap
  refusal; ledge Gust with nonlethal falls; no attacks across levels;
  Wren's teaching; the lookout harvest; mid-traversal disconnect;
  restart; Spark damage, burning, range and level checks; Gust + Spark
  costs, effects, cooldown and refusals. Linux and Windows (Wine)
  servers: 119/119 checks. Real Linux client: previews, animations,
  Spark and the combination.
- **Unverified:** Windows client at runtime (CI build only); two GUI
  clients at once.
- **Provisional:** traversal reach/costs, fall stagger and 0% fall damage,
  burn, combination costs, Ember regeneration in the meadow.
- **Missing:** shadows and cliff art; overlapping floors; Ember altar,
  homeland and vessels; saved assemblies and sustained effects (Pass 3);
  a modifier selector beyond the Y key.
- **Blocked:** nothing.
