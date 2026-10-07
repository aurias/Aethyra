# Aethyra progression framework v0.1

These decisions come from the design Q&A of 6–7 October 2026. This document
replaces any progression rules carried over from the old engine; the Godot game
starts from scratch.

The decisions are firm. The numbers are provisional and live in data files
(`game/data/progression`, `game/data/hue`), so they can be tuned without code.

## 1. Shape of the game

- **The game is open-ended.**
  - There is no fixed finish.
  - Groups choose their own endgame: cozy settlement, factory automation,
    dungeon crawling, conquering every core, or hybrid mastery.
- **Combat is the central loop.**
  - Exploration and crafting feed it.
  - Each also opens areas, workflows and items that only it can reach.
- **Progression grows two ways at once.**
  - Vertical: a character gets stronger.
  - Horizontal: options widen inside each step of vertical growth.
- **It is designed for friends' co-op**: 2–8 players in a hosted world, with an
  economy that is mostly NPCs.

## 2. The world: biomes, depth and concentration

- **Every biome runs from a safe edge to a dangerous core.** The bands are
  edge, frontier, deep and core. Depth is a property of a zone, not of the whole
  biome.
- **Every zone has hue concentration.** It drives:
  - regeneration;
  - how far mastery can be trained there (the soft cap);
  - the tier of materials and creatures;
  - whether death protection holds.
- **Exploration is required to complete a kit.** A hue's skills are spread over
  several zones of that hue (teachers, demonstrations, relics), so travel is
  needed.
- **Mid-depth zones may be hybrid zones**, home to two hue cultures. They are
  how players first meet synergy. A player's relationship with both communities
  unlocks:
  - reputation with each culture, where helping one may cost standing with the
    other;
  - joint projects that need both hues and change the zone when finished;
  - hybrid NPC teachers;
  - trade goods that one culture makes and only the other can process.
- **Altars are dungeons.**
  - The biome protects something at its heart: a structure, artifact, skill or
    material.
  - Altars, cores and concentration hotspots are where feats are performed and
    item rarity is rolled.
- **Starter zones touch compatible hues**, in the order Tide > Verdant > Gale >
  Ember > Terra, with Aura between Tide and Terra.
  - The first biome is Gale (the Windswept Meadow).
  - The next is Ember.

## 3. Hue relations and dissonance

- **A character may learn any number of hues.** Each hue keeps its own mastery,
  energy and skills.
- **Pair relations** are stored explicitly in `data/hue/relations.txt`:

| Relation | Pairs | Default dissonance |
|---|---|---|
| Harmony | Tide–Verdant, Verdant–Gale, Gale–Ember, Ember–Terra, Terra–Aura, Aura–Tide | 0% |
| Clash | Tide–Ember, Gale–Terra, Verdant–Decay, Aura–Void | 20% |
| Neutral | every other pair | 8% |

- **Dissonance is the soft limit on breadth.**
  - Holding hue B weakens hue A by their pair's dissonance.
  - The weakening is scaled by how developed B is compared with A.
  - It reduces A's capacity, regeneration and safe current.
  - The total is capped (`dissonance_max_pct`).
- **Hybrid techniques** are learned from hybrid NPCs and hybrid-zone projects.
  Each reduces one pair's dissonance, so discovering hybrids is long-term
  progression.

## 4. Character growth: there is no character level

**Per-hue mastery (1–50) is the vertical spine.**
- **Milestones** (`data/progression/milestones.txt`) grant that hue's skill
  points and talent picks.
- **Talents** are passive specialisations within a hue. At each talent milestone
  you choose one of a few, which is the horizontal growth.

**Soft caps.**
- **The zone sets a training limit.** Its concentration band sets how far
  mastery can be trained there: edge 10, frontier 20, deep 30, core 40, altar
  50.
- **The character sets a personal cap per hue.** It starts at 15.
- **Practice slows above the lower of the two.** Ordinary practice keeps working
  above it, but each level past it halves the gain.
- **Personal caps rise only through feats.** A feat is a boosted action at high
  concentration with the right mix of skills, gear and workflow. There are two
  kinds:
  - **Authored feats** (`data/progression/feats.txt`): hidden, hinted through
    lore, large cap increases.
  - **Systemic novelty:** the first time a character performs a combination it
    has never done before (skill, modifier, gear tags, concentration band) at
    high concentration raises its cap by a little. Repeats give nothing.

**Trained body stats** grow from what you actually do
(`data/progression/body.txt`):

| Activity | Trains |
|---|---|
| Exploring (cells never visited before) | Speed, Vigilance |
| Combat (damage dealt and taken) | Strength, Channelling, Vitality |
| Crafting and harvesting | Dexterity |

The list and the rates are provisional.

**Every number comes from one modifier system.**
- Each derived stat is a base value plus named modifiers from body stats,
  talents, gear, gems, dissonance, wards and site conditions.
- The UI can show where each number comes from.

## 5. Equipment

- **Slots:** head, body, hands, legs, feet, main hand, off hand, two rings and an
  amulet.
- **Items are modular instances.** Each has:
  - a base item;
  - a material tier (I–V);
  - a rarity (common, fine, rare, epic, legendary);
  - sockets for gems and conduits;
  - enchant effects.
- **Gems and conduits** are items that become modifiers on the gear they sit in.
- **Rarity can be raised at altars.** This is a risky roll that costs charged
  energy (see section 7).
- **Vessels are their own family.** Stackable vessel lots keep their
  charge/condition rules. Conduits are vessels worn in equipment.

## 6. Death and respawn

| Zone depth | On death |
|---|---|
| Edge | Wake in town; no penalty |
| Frontier | Wake at your camp anchor in that biome if you set one, otherwise in town |
| Deep, core and altar | Wake at an active respawn node if its protection is at least the site's concentration. A node is a reinforced camp with ward machinery, or one made by a skill. |

- **When concentration overpowers protection**, the site decides the penalty in
  data. It can be:
  - nothing;
  - dropping carried vessels where you fell;
  - a mastery setback in the site's hue;
  - a lingering condition.
- **Anchors and tethers** can be severed by high concentration.

## 7. Open items, to settle as content arrives

- How a rarity roll at an altar works: its costs and how it can fail.
- What exactly projects and reputation do in each culture.
- Aimed combat: skills aim at the cursor or your facing, take a shape (point,
  cone, line, circle) and enemies telegraph their attacks. Comes with the Ember
  pass.
- Concrete feat list, talent pools and gem families for Gale and Ember.

## 8. What is implemented (Godot, 7 Oct 2026)

| Piece | Code | Data |
|---|---|---|
| Zones, depth bands, concentration | `GameMap.zone_at`, `concentration` | `[things] zone` lines in each map; `progression/bands.txt` |
| Modifier system | `Progression.modifiers`, `stat`, `breakdown` | Sources: body, talents, gear, gems, enchants, dissonance, conditions |
| Dissonance | `Progression.dissonance` | `hue/relations.txt`, `balance.conf` |
| Body stats | `Progression.train`, `explore`; hooks in `World` (steps, damage, harvest, crafting dialogue) | `progression/body.txt` |
| Milestones and talents | `grant_milestones`, `talent_offers`, `pick_talent` | `progression/milestones.txt`, `talents.txt` |
| Per-hue skill points | `HueRules.learn` (rank `cost` in hue points) | `hue/skills.txt` |
| Soft caps | `Progression.mastery_gain`, `HueRules.add_mastery_xp` | `bands.txt`, `personal_cap_start` |
| Feats and novelty | `Progression.check_feats` after meaningful successes | `progression/feats.txt`, `novelty_*` |
| Equipment instances, sockets, rarity, altar raise | `World.equip`, `unequip`, `socket`, `altar_roll` | `world/equipment.txt`, `gems.txt`, `rarities.txt` |
| Death chain, anchors, caches, site penalties | `World._death_chain`, `_site_penalty`, camp kits | Band `respawn`, zone `penalty`, items 901/902 |

**Gale examples in the meadow:**
- **Zones:** the terrace is frontier, the lookout is deep, and the spur is a
  core hotspot.
- **Talents:** three Gale talents at mastery 5 and one at 10.
- **Feats:** Updraft Pyre (Gust + Spark on the spur) and Skyward Stride (a jump
  on the lookout in Windrunner Boots).
- **Gear:** Ama sews the Hopperhide Vest.
- **Camps:** camp kits.

Tested headless in `tests/run_tests.gd` (scenario `progression`).

**Not yet:**
- Reputation and joint projects.
- Hybrid NPC teachers (techniques exist; for now only `@technique` grants them).
- Aimed combat.
- Crafting processes beyond NPC trades.
- Moving between maps (anchors are per map, standing in for per biome).
