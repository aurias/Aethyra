# Aethyra — Recovered Gameplay and World Mechanics

Recovery v0.1 with subsequent user decisions · Updated 4 October 2026, 22:09 PDT

This is a reconstruction and decision record for review and implementation planning. It consolidates the supplied root-conversation excerpts, later user corrections, current direction, and recoverable historical context. It is not a verbatim export of the complete CPL or a claim that every historical message was recovered. Explicit new user decisions are integrated under sources S-U through S-Z and S-AA through S-AD; proposed implementation details remain distinguished from those decisions. The repository and asset inspections below are separate evidence about existing software and artwork.

### Latest decisions integrated

- An altar taps a regional hue core and unlocks the ability to manipulate its hue. The surrounding environment increasingly obscures and protects it.
- Origin hue/region can make progress in another hue harder. Regional altars of the same hue can teach overlapping or different abilities; recipe unlocks are a possibility awaiting the crafting design.
- Skills emphasize manipulation of other skills, items, and conditions. Combinations and workflows create hybrid behavior. Gale affecting Ember can boost, smother, make a smokescreen, or control temperature/pressure, depending on conditions still to be defined.
- Midgame wilderness camps use modular machinery to cope with environmental hostility and automate/advance learned crafting skills. Multiple hue power sources can feed a workflow.
- Acquired land supports a later scaling, cozy economic phase. Puzzle Pirates is a reference for land, shops, and government; its particular tax, deed, and election rules are not automatically adopted.
- NPCs share the breadth of player-accessible skills. Their goods are not inherently inferior, and their machinery/skill combinations serve as passive tutorials.

(S-U)

Further clarification at 13:17 PDT:

- Players can activate multiple skills together. Each hue has its own maximum energy and passive regeneration, affected by mastery, gear, status, and environment.
- Some energy-demanding skills are only possible near a hue core. The exact source/cost rule is not yet specified.
- Exploration example: passive Ember heat tolerance plus an active Gale cooling whirlwind enables deeper travel in an extreme Ember region.
- Combat example: Gust alone causes knockback without damage; Gust + Spark adds fire damage and a chance of burn while retaining knockback.
- Crafting requires maintaining conditions such as pressure, temperature, hue energy, and cooling for specified times. This timed processing is the basis of the economy.
- Craft specializations include Verdant wood framing, Tide precision-cut metal/cooling systems, Ember refined materials/power systems, and Terra raw materials. Decay, Aura, and Void are reserved for rare high-level crafting with powerful and chaotic effects.
- Camps are established and dismantled as temporary rest points. A timed claim expires into abandonment; passing players or NPCs can then take the equipment.
- The world is primarily populated by NPCs who demonstrate cultural hue use, mastery, and combinations. Hybrid NPCs are rarer and can reveal possibilities for endgame play.

(S-V)

Further clarification at 13:32 PDT:

- Players can combine skills on the fly and later refine prepared “spell assemblies” (working term).
- Hue mastery limits the number of skill activations. Higher skill tiers will likely consume more activation slots; exact costs and slot allocation remain open.
- Gale normally has decent passive regeneration because air is widely available, with underwater and underground exceptions. In the Ember expedition example, Tide is harder to regenerate and requires more difficult resource logistics.
- Gale cooling has an effect ceiling even when its energy supply is sustainable. An Ember heat-redirection skill can stack with it for further protection; heat redirection and the earlier heat-tolerance buff are distinct examples.
- Aura crafting alters Terra crystals into hue-energy storage vessels. Vessels can be carried or embedded into equipment to increase energy limits and efficiency. Access, charging, and hue compatibility remain to be specified.
- Missed crafting conditions can pause or fail a process, or damage the crafter/equipment, depending on the material, recipe, and yield.

(S-W)

Further clarification at 21:35 PDT:

- Skill customization and balance require iteration. Linking activation slots to mastery remains the intended direction, rather than a finalized formula. Early characters may not combine passives and actives; increasing mastery permits maintaining multiple skills.
- Mastery is hue-specific and may receive bonuses/reductions associated with starting hue, race, or origin. Their exact targets, values, and the available races remain undefined.
- Advanced crafting produces machinery for endgame automation, supported by the economy and player hue mastery. Modules harvest energy, vessels buffer it like capacitors, and machinery inputs are connected through pipes and assembled in camps, workshops, or owned areas.
- Some production stages may require hired NPCs with relevant skills. This is a possible staffing requirement, not a rule that every machine needs an operator.
- Natural items in each starting biome already hold limited hue reserves. Examples may come from plants, animals, minerals, or other local natural sources. Refining them becomes possible as mastery advances; stronger storage materials occur deeper near cores/altars.
- Aura crystal vessels can store any hue and are necessary for the automation/machinery stage. This does not establish simultaneous mixed-hue storage, energy conversion, or unrestricted access to unfamiliar hue skills.

(S-X)

Further clarification at 21:44 PDT:

- Hue will likely use calculations analogous to voltage, amperage, and wattage. This is an intended modeling direction; exact equations and fantasy units are not yet established.
- Starter vessels have low capacity and can be used together. Too much energy causes them to disintegrate. The precise overload variable, thresholds, timing, warnings, and released-energy effects remain open.
- Increasing demands create a need for better vessels and energy conduits to upgrade equipment and machinery.
- The first test environment is Gale: a windswept grassland.
- The user supplied https://github.com/Aethyra as the historical project location.

(S-Y)

Art direction at 21:46 PDT:

- Import Len's Whispers of Avalon grassland tileset as the starting visual foundation and inspiration for the rest of the art.
- The user identifies Len as a contemporary TMW fork artist and says they contributed sprites to that project. This personal contribution history is user-reported; the source page identifies the tileset author as Leonard Pabin.
- Source: https://opengameart.org/content/whispers-of-avalon-grassland-tileset

(S-Z)

Vessel limits at 21:55 PDT:

- Items have a maximum hue-current rating and a storage capacity.
- Small low-level skills can permit vessel reuse; a stronger skill/spell can instantly disintegrate an entire stack of low-level vessels.
- Immediate stack destruction is possible, so a warning period is not universal. Exact current sharing between stacked vessels and the spell's outcome when vessels disintegrate remain open.

(S-AA)

Calculated casting outcomes at 21:59 PDT:

- High-level, hue-intensive casting from several stacks of low-level material is not ordinarily viable merely because enough material is present.
- Exceptional mastery, items/skills that improve hue flow, or a successful calculated chance roll can make such an attempt possible. The exact relationship among these routes remains to be balanced; they are not established as three mandatory simultaneous requirements.
- Cast resolution involves several calculations and chance. Neither guaranteed successful sacrificial casting nor guaranteed failure whenever weak vessels are used is the general rule.
- Exact probabilities, the relationship between spell success and vessel survival, and whether routine safe casts roll at all remain open. Existing hue/skill unlock requirements are not revoked.

(S-AB)

Starter-area teaching at 22:05 PDT:

- Every starting area introduces exploration/environmental coping, combat/enemy interaction, and crafting/channeling hue into items, consumables, and equipment.
- Gale's proposed first exploration mechanic is featherfall or boosted jumping. Gust is a candidate first combat skill: knockback encourages evasion and positioning rather than head-on engagement.
- Gale crafting could introduce material manipulation serving speed, stealth, and evasion.
- Starting areas share a learning cadence while offering distinct experiences grounded in each hue culture. Exact quest order and final starter skill rosters remain undecided.

(S-AC)

Gale elevation traversal at 22:09 PDT:

- Featherfall allows players to descend map layers without stairs. A separate skill allows them to jump back up.
- These abilities provide Gale users with distinct pathways and are intended to make basic Gale mastery desirable to players of other origins.
- Both descent and ascent abilities now have defined roles. Their exact acquisition order, inclusion at character creation, costs, reach, and controls remain open.

(S-AD)

## Evidence and precedence

- **Established:** present in a user-supplied CPL entry, explicit user clarification, or current instruction visible in this conversation.
- **Defined example:** an example in those sources. It demonstrates a rule; its numbers, names, or recipe are not automatically universal requirements.
- **Context-recovered:** recovered through historical conversation summaries; complete original wording or approval is unavailable. Keep provisional where attribution or later revision is uncertain.
- **Unrecovered:** a referenced detail could not be retrieved reliably. This does not mean it was never discussed.
- **Implementation implication:** a consequence proposed for software planning, separate from game canon.

Explicit later corrections take precedence over earlier generalizations. Current direction takes precedence over earlier pacing suggestions. Bare “Approved” messages do not establish the contents of missing assistant proposals. Assistant-generated confidence ratings, stories, charts, and examples do not by themselves establish mechanics.

The recovered principal CPL sections are CP-H (Hue System), CP-R (Resources), CP-B (Base Building and Crafting), CP-P (Player Progression and Economy), CP-C (Combat), CP-E (Events), and CP-S (Skill Trees). Their subsection numbering evolved; the grouping below preserves the principal IDs without claiming to reconstruct the final historical numbering.

## 1. Current game direction and scope

**Established — current conversation, 4 October 2026.**

- The opening should be soft, cozy, and welcoming. Players should feel at home at the beginning and nostalgic when returning to their homeland.
- The selected first test setting is a Gale windswept grassland. Specific settlement layout, starter materials, and tasks remain to be designed. (S-Y)
- Len's Whispers of Avalon grassland tileset is the selected art foundation and reference for further assets. (S-Z)
- Players grow outward into the world as cultural explorers visiting lands associated with different hues.
- Part of the journey is the interaction of the player's hue knowledge with the knowledge of other cultures.
- Gale offers distinct routes between map elevations: featherfall for descent without stairs and a separate upward-jump skill. Basic Gale mastery is intended to be desirable across player origins; it is not established as mandatory for every destination. (S-AD)
- Midgame emphasizes exploration, combat, resource extraction, and hue altar visits.
- Midgame camps already use machinery and automation. Later land/workshop ownership supports scaling production, a cozy economy, high-level exploration, and world manipulation. The user compares this later phase to Stardew Valley. (S-U)
- The intended initial scale is a small persistent server comparable to a Minecraft Realm, with a simulated economy in which “NPCs are also players.” NPCs have access to the same breadth of skills and can produce goods competitive with player work. Their machinery and skill use also teach the player through observation. Exact autonomy and simulation depth remain unresolved. (S-U)
- Complexity should be introduced gradually, with intuitive onboarding, creativity, flexibility, and optional advanced mechanics. The user explicitly endorsed this approach in the root conversation. (S-D)
- Every homeland introduces all three foundations: exploration/environmental coping, combat/enemy interaction, and hue-channeling crafting. Their cadence is similar, but each hue culture provides a distinct experience. This resolves the earlier either/or question about whether the opening teaches exploration or crafting. (S-AC)
- This is a game. Real-world craft and material behavior may inform the design, but recovered examples must not be replaced with unsolicited realism requirements.

**Pacing reconciliation:** the original resource rules explicitly provide starting-hue harvesting abilities. The phase descriptions do not revoke early gathering, basic crafting, or simple combat. S-U places exploration/crafting machinery in midgame camps; S-X emphasizes advanced crafting and endgame automation, with connected machinery usable in camps, workshops, or owned areas. A progression from field equipment to advanced production networks is a proposed reconciliation. Exact access thresholds, the boundary between early equipment and Aura-dependent machinery, village-station access, and land acquisition remain open. (S-U, S-X)

**Project lineage:** the original Aethyra was the user's first project, a TMW fork in 2008–2009 curated by Tametomo. The newer concept reuses its name as an homage. The user recalls creating spritesheets and work on multichannel sprite recoloring. The user supplied the Aethyra GitHub organization; an initial source inspection identified Aethyra/Client and a later direct descendant at Tametomo/Aethyra. Reusing a specific revision has not been decided, and a full historical comparison against TMW has not been performed. See section 11.1. (S-N, S-Y)

## 2. CP-H — Hues, world structure, and interactions

### 2.1 Hue identities

Eight hues are explicitly listed in CP-S. Five have explicit starting-harvesting examples in CP-R. The table separates those examples from contextual affinities; it does not establish which of all eight are selectable at character creation. (S-R, S-S, R-H, R-W)

| Hue | Recovered elemental association | Explicit early harvesting/crafting example | Other firmly supported applications |
|---|---|---|---|
| Ember | Fire and heat | Harvest metal; naturally smelt ore | Refined materials and power systems; heat sources, operating-temperature changes, and heat-resistant components |
| Tide | Water; ice appears in contextual biome descriptions | Collect water; assist underwater navigation | Precision-cut metal and cooling systems; cooling stability; the defined Tide chamber example improves some low-temperature processing |
| Terra | Earth, stone, minerals | Extract stone and crystals; stone shaping in CP-S | Raw-material provision; density/hardness themes; opposing Gale can be combined for sandblasting |
| Verdant | Plants, growth, living materials | Harvest wood, fibers, and hide | Wood framing; some resources possess regrowth/self-repair that can extend component life under overload |
| Gale | Wind and airflow | Collect airflow crystals | Lightweight woods, fabrics, and refined natural materials; weight reduction, airflow, intensifying compatible effects |
| Decay | Decay/corrosion — context-recovered | No dependable starting action recovered | Exact approved material effects and production mechanics remain unrecovered |
| Aura | Light/radiance — context-recovered, consistent with the user's light-art requests | No dependable starting action recovered | Some resources have self-repair; Aura plus Gale may make camouflage cloth |
| Void | Absence of natural hue; darkness/shadow in contextual descriptions | No dependable starting action recovered | Can emerge following hue depletion; dangerous altered biomes; nullification appears in recovered CP-H context |

The latest production-role assignments are explicit user decisions. Decay, Aura, and Void are reserved for rare, high-level crafting and produce the most powerful and chaotic effects. This does not independently resolve their eligibility at character creation or their non-crafting skill use. Gale's lightweight-material focus remains supported by the earlier direct corrections. (S-G, S-V)

The conceptual affinity of a hue is not a universal bonus applied to every material of that hue. The user repeatedly rejected that style of extrapolation. Resource type, quality, affinity bonuses, and particular special attributes determine the component's outcome. (S-M, S-G)

### 2.2 Hue as usable energy

- Hue can be collected, siphoned, stored, imbued into materials/objects, and channeled. (S-R, S-B, S-S)
- Hue energy moves through conduits linking crystals, storage vessels/reservoirs, and crafting structures. Earlier descriptions use pipes/fluid flow and capacitor-like storage; the latest user decision explicitly proposes voltage/amperage/wattage-like calculations. Pipe-based presentation and an electrical-style mathematical model can coexist, but equations are not finalized. (S-B, S-X, S-Y)
- Active hue-powered components require appropriate hue supplies. The material affinity and the energy supply of a component are related concepts but need distinct representation; passive versus supplied effects are not fully formalized. (S-T)
- Capacity and conductivity are distinct material attributes: storage versus transfer. (S-R)
- Mastery improves hue-related capabilities and efficiency, including collection, storage, channeling, crafting, and combat. (S-S, R-H)
- Players have hue-specific maximum energy and passive regeneration. The user uses “mana” as a working label. Mastery, gear, status, and environment determine these limits/rates. (S-V)
- Gale normally has decent passive regeneration due to ambient air, with underwater and underground exceptions. No numerical rates or absolute absence of regeneration in those exceptions is specified. Tide has more difficult regeneration/resource logistics in the Ember-expedition example; this is not a universal comparison in every environment. (S-W)
- Natural items found in each starting biome serve as vessels in which hue collects, with limited reserves. They may be dropped/harvested from plants, animals, minerals, or other local natural sources. Players can refine them as mastery progresses; stronger storage materials occur deeper near cores/altars. Exact capacities, portability effects on charging, replenishment, and consumption rules remain open. (S-X)
- Low-capacity starter vessels can be used together. Items have a maximum hue-current rating distinct from capacity. Small low-level skills can leave vessels reusable; one stronger skill/spell can instantly disintegrate an entire stack of low-level vessels. Improved vessels and conduits are required as equipment and machinery demands scale. More total stored energy is not established as automatically increasing safe current. Exact stack load-sharing, the affected-stack selection, and the spell's outcome during destruction remain open. (S-Y, S-AA)
- A guaranteed warning/grace period before vessel destruction is not established; instantaneous destruction is explicitly possible. Gradual overload damage, behavior at full capacity, and recovery/charging rules remain unspecified. Reuse of the vessel does not imply that the cast consumes no stored energy. (S-AA)
- Executing a high-level, hue-intensive skill with several stacks of low-level material requires exceptional mastery, flow-improving items/skills, or a successful calculated chance roll. Material quantity alone is not the intended route to reliable high-level casting. The result depends on several calculations and chance rather than a universal success/failure rule for weak vessels. The precise contributions of mastery and modifiers, probability formula, hard limits, and correlation between cast success and vessel destruction remain undecided. This does not independently grant access to unlearned hues/skills. (S-AB)
- Aura crafting alters Terra crystals into vessels for hue energy. These can be carried and embedded into equipment, increasing energy limits and efficiency. Later clarification calls them Aura crystal vessels: they can store any hue, serve as capacitor-like buffers, and are necessary for the automation/machinery stage. Any-hue compatibility does not establish simultaneous mixtures, energy conversion, or skills the user has not unlocked. Charging, the meaning of efficiency, and prerequisites for using purchased vessels remain open. (S-W, S-X)
- Multiple skills may be activated together. The exploration example combines a passive Ember effect with an active Gale effect. (S-V)
- Mastery-linked activation slots remain the intended direction, subject to customization and balance iteration. Higher skill tiers may cost more slots. Early passive/active combinations may be unavailable; higher mastery permits maintaining multiple skills. Mastery is hue-specific, but a global versus per-hue slot allowance and duration of occupancy are not yet settled. Storage is not established to increase activation slots. (S-W, S-X)
- Some high-energy skills can only be activated near a hue core. Whether this is represented by increased capacity/regeneration, direct access to core energy, a specific activation requirement, or a combination remains unspecified. (S-V)
- Exact energy units, skill costs, ongoing drains, numerical regeneration rates, flow equations, pressure behavior, and vessel mixing rules remain unresolved.

### 2.3 Biomes and concentration

- Biomes are influenced by dominant hues. Their resources, enemies, environmental hazards, and crafting economies reflect those influences. (S-R, S-C, S-P)
- Resources of many basic types appear across biomes, acquiring different hue-associated properties. Regional specialization does not establish an absolute rule that a basic resource exists only in one hue's biome. (S-R)
- Higher-concentration areas, typically toward a biome's center/core, provide stronger or higher-tier resources and more dangerous enemies/environmental challenges. Safer edges versus dangerous cores are also present in recovered CP-H context. (S-R, S-C, R-H)
- Preparation, equipment, hue knowledge, and mastery support deeper exploration. (S-C, S-S)
- Biomes can react to the player and to resource/hue exploitation. Environmental defenses and camouflage are part of exploration and combat. (S-C, S-E)
- A hue altar is a structure that taps into a regional hue core's energy. The environment becomes increasingly protective toward the core and attempts to obscure and defend the altar location. Reaching it is intended to be a perilous exploration journey. (S-U)
- Skills, crafted items, equipment, consumables, and deployables can help cope with the environment's challenges. This gives preparation, skill combinations, and field machinery direct roles in exploration. (S-U)

**Context-recovered landscape descriptions:** Ember volcanic/molten terrain; Tide oceans, glaciers, and underwater caves; Terra mountains, caves, and rocky plains; Verdant forests and overgrown ruins; Gale windy plateaus, cliffs, and floating islands; Decay swamps, wastelands, and decaying forests; Aura luminous plains/mountains and celestial platforms; Void dark caverns and altered shadow terrain. These are recovered descriptions, not verified terrain-generation or mandatory-content rules. (R-W)

### 2.4 Complementary and opposing hues

- Complementary hues can boost desired attributes/bonuses. (S-R, S-T)
- Opposing hues can cancel unwanted attributes/bonuses. Their controlled use is an intended crafting technique. (S-T)
- Players balance combinations to avoid damaging or runaway behavior. Improper combinations can be unstable or destructive. (S-R, S-T)
- An early recovered CP-H summary says opposing hues in a shared vessel/structure react violently. Later explicit user explanations allow controlled opposing-hue use in structures. The blanket interpretation “opposites cannot coexist in any structure” is therefore not retained. The precise conditions for safe contact or separation remain unresolved. (R-H, S-T)

| Pair | Recovered relationship | Evidence/status |
|---|---|---|
| Ember + Tide | Opposing; improper combination can be unstable; cooling/temperature balancing is a legitimate application | Explicit CP-R and furnace explanations; exact reaction rules missing |
| Gale + Terra | Opposing; sandblasting is an example of deliberate combination | Explicit user example, message 56 |
| Aura + Void | Opposing | Context-recovered CP-H; full original wording/updated rule not recovered |
| Terra + Ember | Complementary in recovered CP-H; furnace efficiency through temperature/stability in a CP-S hybrid example | Context-recovered classification; supplied CP-S example |
| Gale + Aura | Complementary in recovered CP-H; camouflage cloth is explicitly suggested by the user | User example, message 58; context-recovered classification |
| Verdant + Tide | Complementary example producing highly conductive wood | Supplied CP-R example; exact conductivity/stat effect unspecified |
| Gale + Ember | Blue Fire hybrid example, increasing attack speed/damage | Supplied CP-S example; no complete universal interaction matrix recovered |

These entries do not establish every hue-pair relationship, symmetry, numerical coefficients, or a fixed outcome for every combination.

### 2.5 Altars and learning other hues

- Players start aligned to one hue and can gain mastery of additional hues. (S-S, R-H)
- Visiting a hue altar unlocks the ability to manipulate that hue. (S-U)
- The player's hue/area of origin can make progression in another hue harder. The exact effect on rates, costs, challenges, or thresholds is not yet specified. (S-U)
- An altar taps its regional hue core. Increasing environmental protection and obscuration create a difficult journey inward. (S-U)
- Skills and combinations of crafted items, equipment, consumables, and deployables provide ways to overcome those challenges. (S-U)
- Altars of the same hue in different regions may teach the same or different skills/abilities. Learning the hue once therefore does not establish that every regional altar has the same rewards. (S-U)
- Altars may also unlock recipes, depending on how the crafting system is defined. This is explicitly conditional, not yet a fixed recipe-progression rule. (S-U)
- Exact interaction procedure, repeat-use behavior, activation costs, eligibility beyond reaching the altar, and whether environmental defenses change after a visit are unresolved.
- The player-facing interaction model for directing multiple learned hues remains unresolved. The current preference is skill/item manipulation and hybrid workflows rather than an emphasis on hotbar attacks. (S-U)

## 3. CP-R — Resources, material properties, and refining

### 3.1 Categories and distribution

- Basic resource families include metals, stones, woods, fibers, water, and airflow crystals. Hide is also explicitly harvested through Verdant skills. (S-R)
- Resources may be mundane (no hue affinity) or hue-infused. Hue-infused resources are abundant and can be more common than mundane resources. This later clarification supersedes a reading in which mundane material is the usual form everywhere and hue-infused material is always rare. (S-M)
- Hue-infused variants alter the usefulness of base materials. They can provide bonuses, tradeoffs, or special properties. (S-R, S-M)
- Refined materials result from processes applied to resources, including smelting, infusion, and transmutation. They retain or transform relevant source properties. (S-R)
- “Basic,” “hue-infused,” and “refined” describe aspects of material classification/processing; the sources do not provide a complete exclusive taxonomy or data schema.

### 3.2 Resource attributes

The supplied CP-R explicitly lists six core attributes. Later retrieval also lists weight separately. Preserve the relationship without silently deciding whether weight is independently stored or derived. (S-R, S-A, R-A)

| Attribute | Defined meaning or relationship | Implementation detail still missing |
|---|---|---|
| Density | Material compactness; associated with weight | Whether density and volume derive object weight, or weight is a separate gameplay stat |
| Weight | Explicitly discussed and modified by Gale; appears separately in a later recovered attribute list | Canonical representation relative to density |
| Hardness | Later clarified as impact and pressure tolerance | Mapping from hardness to safe operating pressure/impact; distinct from remaining durability |
| Thermal/temperature conductivity | How readily heat transfers | Numerical scale and transfer model; these two terms are treated as alternate wording, not two invented attributes |
| Thermal capacity | How much heat can be stored | Numerical scale and effect on temperature change |
| Hue conductivity | How readily hue energy transfers | Numerical scale, hue selectivity, and network behavior |
| Hue capacity | How much hue energy can be stored | Units, hue-specific storage, mixing, and saturation behavior |

- Temperature tolerance and minimum/maximum operating temperatures are explicitly used in component and structure examples. They must not be conflated with thermal capacity or conductivity. Their derivation from resource properties/bonuses is not fully specified. (S-T, S-F)
- Components can also have operating limits involving pressure and hue concentration. The list is illustrative rather than exhaustively closed. (S-M)
- Some resources possess special attributes, such as self-repair. These are not automatically shared by every material of that hue. (S-M)

### 3.3 Tier, quality, and attribute rarity

- Resource tiers increase in Roman numerals: I, II, III, and onward to an undefined upper limit. (S-A)
- This supersedes the initial use of common/rare/exotic as the tier scheme. Rarity and rare attributes can still matter; they are not the same thing as tier. (S-R, S-M, S-A)
- Resource quality and hue-affinity bonuses determine component bonuses and operating specifications. (S-M)
- Players seek better resources through higher quality, higher tier, rare attribute types, and useful combinations. (S-M)
- Higher-tier hue resources occur deeper in more dangerous high-concentration zones. Better components expand processing ranges and enable further refining/progression. (S-M)
- Exact tier gates, quality scales, generation distributions, and property-combination equations are unrecovered.

### 3.4 Gathering and tools

- Each starting hue has a natural harvesting skill that replaces a corresponding early tool. The recovered examples are in the hue table above. (S-R)
- Better tools are acquired or crafted as progression opens harder resources and locations. Pickaxes, axes, and drills are examples. (S-R)
- Tools can incorporate hue-infused resources and improve harvesting capability/efficiency. (S-R)
- Skills, tools, mastery, and resource properties jointly affect progression; exact tool requirements and rates are not yet specified.

### 3.5 Identification

- Initially unidentified resources can appear as generic stones, metals, or plants. Identification reveals their properties/type. (S-R)
- Once identified, the resource is recognized during future gathering in that hue's biome. (S-R)
- “Smolderite” is a supplied example name for an identified Ember metal; it is not a complete resource catalog. (S-R)
- An unidentified appearance does not establish that the resource is actually mundane or lacks hue affinity.
- Whether knowledge is per character, account, party, or server is unrecovered.

### 3.6 Refining

- Processes include smelting, infusion, and transmutation. (S-R)
- Processing can require particular temperatures and hue flows. (S-R)
- Materials and components are chosen to create useful operating conditions. Complementary/opposing hues can improve desired outcomes or control unwanted effects. (S-R, S-T)
- The user explicitly linked upgraded machinery, expanded operating ranges, higher-tier processing, and the search for better resources. (S-M)
- Exact yields, batch sizes, processing time, process failures, and recipes remain unrecovered.

### 3.6.1 Timed process conditions

- Players must maintain pressure, temperature, hue energy, cooling, or other conditions for certain durations to produce new materials. (S-V)
- This processing system forms the basis of the economy. Its conditions can be supplied and controlled through the skill/machinery workflows established elsewhere. (S-U, S-V)
- If conditions are not met, processing may pause, fail, or damage the crafter/equipment, depending on the material, recipe, and yield. There is no universal interruption outcome. (S-W)
- Exact acceptable ranges, stage ordering, interruption thresholds, partial progress, quality effects, yields, and damage amounts are not yet specified.
- Crafting-role assignments: Verdant provides wood framing; Tide provides precision-cut metal and cooling systems; Ember provides refined materials and power systems; Terra provides raw materials. (S-V)
- These assignments establish cultural production specialties. They do not by themselves establish exclusive recipe bans for every other hue.
- A concrete cross-hue production chain is Terra crystals altered through Aura crafting into hue-energy storage vessels for carried use or embedding in equipment. The recipe and access requirements are not yet defined. (S-W)
- Decay, Aura, and Void are reserved for rare high-level crafting with the most powerful and chaotic effects. Earlier self-repair/nullification concepts must be applied consistently with that later crafting scope. (S-V)

### 3.7 Depletion, renewal, and Void emergence

- Overharvesting and excessive hue extraction can deplete an area. (S-R, S-E)
- If the area's hue is siphoned away, resources can revert to generic forms without hue affinity. (S-R)
- Prolonged barrenness/absence of natural hue may generate Void hue, producing dangerous and unpredictable conditions. (S-R)
- Hue siphon structures extract environmental energy and can harm biomes if overused. (S-R)
- Event descriptions include resource corruption, elementals, void creatures, and possible transformation into a Void biome. (S-E)
- Resource renewal is part of the concept, but recovery rates, thresholds, restoration actions, spatial scale, and persistence through offline time are unrecovered.

## 4. CP-B — Components, structures, and automation

### 4.1 Assembly and tiers

- Structures are assembled from separately crafted components. (S-B, S-T)
- Structures have required core-component slots and accessory slots for upgrades. (S-T)
- Structures gain complexity, required/accessory slots, and input capacity as tiers increase. Exact tier layouts are structure-specific and not recovered as a complete table. (S-T)
- Components are crafted from mundane or hue-affiliated resources. Their operating specifications are directly determined by their source resources, quality, and affinity bonuses. (S-T, S-M)
- Resource combinations and component choices are intended to produce meaningful variation. The aggregation formula is unrecovered.

### 4.2 Passive, active, and supplied components

- Components can be passive or active. Active hue-powered components require hue energy to function. (S-T)
- Manual fuel is a defined alternative for a furnace heat source; the later furnace description also allows direct power from player skills. (S-T, S-F)
- Hue-affiliated components can require particular hue inputs. Players connect these to storage vessels. (S-T)
- A structure has a tier-dependent number of input ports, which can limit how many components can operate. (S-T)
- Core-component requirements take priority. Accessory benefits require their necessary hue inputs to be satisfied. (S-T)
- Some accessories add an input connection at the cost of occupying an accessory slot. (S-T)
- A component upgrade can turn a formerly passive role into an active component requiring a continuing input to tolerate extreme conditions. (S-T)
- The exact relationship between passive material bonuses, affinity, activation requirements, port capacity, manual fuel, and direct skill input remains an implementation/design gap.

### 4.3 Durability, overload, repair, and regrowth

- Every component has individual durability and normal wear. (S-T, S-M)
- Exceeding a component's operating ranges increases wear. Temperature, pressure, and hue concentration are explicit examples. (S-M)
- Players may intentionally exceed safe ranges to gain higher-tier crafting capability at the cost of durability. This is an intended strategy. (S-M)
- A required core component reaching zero durability makes the structure nonfunctional until the problem is remedied. (S-T)
- Accessory failure removes its benefits and can worsen a chain reaction. (S-T)
- Repair reduces maximum durability and eventually quality. Exact losses and quality thresholds are unrecovered. (S-T)
- Some Verdant and Aura resources uniquely possess self-repair/regrowth attributes. Other hues primarily affect operating ranges. These properties can prolong component life during overload. (S-M)
- The sources do not establish that regrowth restores lost maximum durability, removes repair penalties, works without costs, or prevents all failures.
- A stated foundation contribution to base durability and individual-component durability both exist. The rule connecting overall structure durability to component durability remains unrecovered. (S-F)

### 4.4 Latest explicit furnace anatomy

The later user description expands the furnace beyond the earlier minimal demonstration. Preserve the later anatomy; do not apply the old two-core-component example as the complete universal furnace specification. (S-F)

| Component | Explicit role |
|---|---|
| Foundation | Determines base durability |
| Core/shell | Base and outer shell; stone, metal, and/or crystal determine maximum attributes |
| Smelting chamber | Houses the crucible; higher-tier resources can provide maximum-temperature bonuses |
| Heat element | Coal-fired by default; can be upgraded to hue power or powered directly by skills |
| Chimney | Normal by default; can incorporate a Gale turbocharged chimney to force airflow |
| Accessory slot | Accepts an upgrade; bellows and a Tide cooling system are examples |

“Core” is used both for the required component category and for the furnace's named shell component. Software/schema terminology should distinguish those meanings; this is an implementation implication, not a new mechanic.

**Earlier defined demonstration:** a Tier I furnace had a passive smelting chamber, an active heat source, one accessory slot, and two input ports. Its purpose was to explain modular assembly and input limits. Later anatomy does not specify updated port counts, so those should not be silently inferred. (S-T)

**Other explicit furnace examples:**

- A Tide-infused stone chamber can reduce maximum temperature while improving ingot quality for low-melting-point metals.
- A mundane heat source consumes manually supplied fuel.
- An Ember-fed blast crystal raises minimum and maximum temperature to enable higher-tier metals.
- A Gale-powered bellows can raise maximum temperature.
- Too much heat damages an inadequate chamber; Ember-metal can provide a more heat-resistant replacement.
- A further upgrade may need active hue input to continue tolerating extreme temperatures.

These are defined examples, with no recovered numerical recipes or balancing values. (S-T)

### 4.5 Other structures and applications

- Furnaces, forges, hue vessels/reservoirs, conduits, and hue siphon structures are explicitly present. (S-B, S-R)
- Foundations and upgraded components contribute to structure capability; Terra-related strength and Gale-related weight reduction appear in the supplied concepts. (S-B, S-G)
- A crafting workbench, grain windmill, upgraded metal forge, and striking-hammer component were discussed. Complete final component inventories for those examples are not recoverable from the visible transcript.
- The user specifically asked how to bootstrap components for the first workbench. Historical retrieval reports simple handcrafting/starter tools as the response, but the visible user messages ask the question rather than establish the answer. Treat that bootstrap rule as context-recovered, pending verification. (S-Q, R-Q)
- Gale crafting is specifically focused on lightweight materials such as low-density woods, fabrics, and refined natural materials. (S-G)
- The user proposed Gale lightening a striking hammer to increase impact and lightening foundations to potentially permit mobile structures. Mobile structures remain a possibility/example, not a fully defined system. (S-G)
- Gale can intensify compatible hues and combine with opposing Terra for sandblasting. Aura plus Gale may produce camouflage cloth. (S-G)
- The sources do not define universal building placement, land claims, rental, workshop ownership transfer, structural physics, or movement rules for mobile buildings.

### 4.6 Camps and acquired land

- Machinery is deployed or used in wilderness camps to cope with hostile environments and enable further progress. (S-U)
- Camp machinery automates and advances skills the player has learned and uses for midgame crafting. (S-U)
- Modular machinery permits multiple hue power sources to be combined into a workflow. (S-U)
- The latest direction places advanced machine crafting and automation in the endgame and explicitly permits piped/assembled networks within camps, workshops, or owned areas. The boundary with earlier midgame camp equipment is not yet fixed. (S-X)
- Factory-style production and process design are central to this direction, alongside exploration and combat. (S-U)
- Once land is acquired, play can develop into a scaling, cozy economy with workshops/shops and settlement ownership. (S-U)
- Player participation in land ownership, shops, and government is desired, with Puzzle Pirates as a reference. Exact property rights, acquisition, office selection, taxation, and NPC officeholding rules remain undecided. (S-U)
- Camps are set up and broken down and serve as temporary rest points. (S-V)
- A camp can be claimed for a set duration. When its claim ends, it becomes abandoned. Other players or NPCs who pass by may take its equipment. (S-V)
- The claim duration, renewal conditions, time basis during logout/server downtime, active-claim permissions, dismantling/recovery costs, and machinery operation during absence remain unspecified.
- Free placement, transport limits, environmental protection, territorial immunity, and exact persistence rules should not be inferred from the existence of camps.

### 4.7 Automation

- Automation progressively replaces manual resource gathering, refining, component crafting, storage, and hue management. (S-B)
- Hue-powered machines and networks require sufficient compatible supply and appropriate components. (S-B, S-T)
- Higher-tier and hue-infused components can improve production speed, efficiency, operating range, or capacity where the specific material/component supports it. (S-B, S-M)
- Input shortages, conflicts, overload, and durability loss create operating constraints. (S-B, S-T)
- Missed process conditions have material/recipe/yield-specific outcomes, including pausing, failure, and damage to the crafter or equipment. Automated processes need to preserve these distinctions. (S-W)
- Earlier direction includes automation in midgame field camps; the latest emphasizes advanced crafting for endgame automation. Exact unlock levels, scale limits, and the transition remain unspecified. (S-U, S-X)
- Advanced machinery depends on the economy and player hue mastery. Energy-harvesting modules can be linked into flows of different hues; machinery has inputs and is piped together/assembled within a camp, workshop, or owned area. This does not by itself establish whether incompatible hues share a pipe or mix safely. (S-X)
- Aura crystal vessels buffer stored energy like capacitors, accept any hue, and are required for this automation/machinery stage. Storage, harvesting, and consuming energy are distinct roles in the network. (S-X)
- Hiring NPCs with particular skills may be necessary to operate parts of a process. Exact tasks, staffing requirements, pay, scheduling, and progression substitution remain open. A saved spell assembly becoming a machine program is not established by this description. (S-X)
- Conveyor/logistics behavior, autonomous transport, update frequency, offline progress, and simulation budgets are unrecovered.

## 5. CP-S — Character progression, mastery, and skills

- Each of the eight hues has its own skill tree. (S-S)
- Mastery is specific to each hue and may have bonuses/reductions based on starting hue, race, or origin. Exact modifiers, what they modify, and race choices are not defined. (S-X)
- Trees have combat and utility branches. Combat splits into offensive and defensive abilities. Utility includes harvesting/crafting, environmental manipulation, camouflage, hue imbuing/siphoning, and passive perks. (S-S)
- Combat skills can have environmental uses, such as clearing obstacles or activating traps. (S-S)
- Players gain one skill point per level. Points purchase skills, upgrades, or perks. The precise relationship between character level and hue mastery is not fully defined; they should not be silently collapsed. (S-S)
- Hue mastery ranges from 0 to 50. Higher mastery unlocks stronger abilities and improves hue-related efficiency. Recovered CP-H describes level 0 as unlearned and level 1 as basic usability. (S-S, R-H)
- Individual skills also have proficiency that grows with use. Skill-tree upgrades unlock higher proficiency caps. This is distinct from a blanket claim that every progression variable is the same XP track. (S-S)
- Earlier CP-S describes mastery of a second hue making hybrid skills available. The user's newer direction emphasizes hybrid behavior created through combinations and workflows that manipulate skills/items/conditions. The earlier concept of a separately purchased hybrid node for every pair should not be automatically retained. (S-S, S-U)
- Hybrid workflows matter in exploration, crafting, and combat. Exact mastery thresholds, action costs, and progression gates remain unspecified; altar visits now establish the basic hue-unlock mechanism. (S-S, S-U)
- Players choose how much to invest in combat versus crafting/utility. (S-S)
- Camouflage uses hue to blend into a similar-hue environment and reduce detection. (S-S)
- Perks can improve hue capacity, combat effectiveness, and crafting efficiency. Exact perk sets remain unestablished.

**Earlier illustrative skills from the supplied CP-S:** Ember Fireball, Flame Slash, Meteor Shower; Fire Cloak, Lava Shield, Inferno Barrier; Smelting, increased forge maximum temperature, Hue Siphoning. The examples use levels 1/10/20 for offensive/utility entries and 5/15/25 for defensive entries. They are examples of possible progression, not a finalized roster or a requirement to build a hotbar-centered combat system. Gale + Ember Blue Fire and Terra + Ember furnace improvement are historical hybrid examples. The newer skill direction takes precedence when deciding how they would be implemented. (S-S, S-U)

### 5.1 Manipulation and hybrid workflows

- Skills should focus more on manipulating other skills and items than on activating separate hotbar attacks. This is a preference about the central interaction model, not an explicit ban on every shortcut or directly activated ability. (S-U)
- Combinations and workflows produce hybrid behavior. (S-U)
- Both on-the-fly combinations and prepared/refined spell assemblies are supported. Players should be able to experiment during play and refine assemblies later. Exact controls, timing windows, and editing interface remain open. (S-W)
- Players may activate multiple skills together. The latest examples establish passive/active stacking and active skills acting as modifiers to one another. (S-V)
- Linking activation count to hue mastery remains the intended direction, subject to iteration. Higher-tier manipulation may cost more slots. Early passive/active combinations may be restricted; increasing mastery permits maintaining multiple skills. Numeric costs, whether slots are shared across hues, and whether sustained effects retain occupied slots remain unresolved. (S-W, S-X)
- A Gale user can generate powerful gusts. Applied to Ember effects, these can boost them, smother them, make a smokescreen, or control temperature and pressure. (S-U)
- The same hue pair can have several outcomes in different contexts. The user requested that design questions focus on concrete situations rather than treating a generic wind/fire interaction as a complete specification. (S-V)
- Exploration example: a passive Ember heat-tolerance buff stacks with an active Gale cooling whirlwind to permit deeper exploration into an extreme Ember zone. The exact cost/drain/duration and mitigation rules are unspecified. (S-V)
- Exploration refinement: Gale is easier to regenerate in this setting but can reach a cooling ceiling. An Ember skill redirecting heat away from the player can stack with that cooling. This is a distinct Ember application from heat tolerance; sustainable energy does not imply unlimited effect strength. (S-W)
- Combat example: Gust alone has no damage and causes knockback. Gust combined with Spark retains knockback and adds fire damage plus a chance to inflict burn. Both improvised combinations and prepared assemblies are supported; precise sequencing, timing windows, modifier selection, costs, and numerical outcomes remain unspecified. (S-V, S-W)
- Crafting example: skills and machinery maintain required process conditions over time, including pressure, temperature, hue energy, and cooling. (S-V)
- Origin, mastery, gear, status, and environment already have defined roles in progression/energy budgets; exact formulas and thresholds remain open. The current examples do not require the player to directly adjust physical wind vectors or simulate oxygen flow.
- An exhaustive physics simulation is not implied. A shared set of legible game rules is an implementation proposal to support these interactions.

### 5.2 Starter-area learning and Gale candidates

All starting areas teach the following foundations through culturally distinct content. These are shared learning goals, not an identical quest sequence for every hue. (S-AC)

| Foundation | Shared lesson | Proposed Gale expression from the user |
|---|---|---|
| Exploration | Use basic skills to cope with the environment | Featherfall descends map layers without stairs; a separate skill jumps back up (S-AD) |
| Combat | Deal with enemies using the hue's capabilities | Gust knockback encourages evasion and positioning; the earlier defined Gust remains non-damaging |
| Crafting | Channel hue into items, consumables, and equipment | Material manipulation that supports speed, stealth, and evasion |

Featherfall and upward jumping now have separate defined roles. Their acquisition order and whether both are immediately available at the start remain unspecified. Gale players gain distinct traversal routes; basic mastery is intended to appeal to players of other origins. Exact elevation reach, energy costs, landing constraints, falling without protection, and controls remain open. This defines elevation traversal without committing to unrestricted flight. (S-AD)

The exact crafted items, effects, quantities, mastery requirements, training order, and NPC teaching mechanisms remain unspecified. Speed/stealth/evasion are crafting directions, not universal bonuses applied to every Gale material. (S-AC interpreted consistently with S-M and S-G)

Implementation implication: represent traversable elevations separately from visual rendering layers. Descent and ascent need valid takeoff/landing locations, collision, range/cost checks, and explicit interaction with knockback. One possible implementation keeps 2D tile art and adds logical elevation levels with server-authorized transitions and client animation. This is a proposal, not a claim that the inspected client already implements it or a requirement for a full 3D physics engine.

## 6. CP-C — Combat and environmental threats

- Combat is live-action and uses skills, equipment, evasive maneuvers, and environmental interaction. (S-C)
- Offensive and defensive abilities derive from hue mastery and the skill tree. Crafted equipment supports combat progression. (S-C, S-S)
- Players can manipulate the environment, with burning obstacles and water-based traps given as examples. (S-C)
- Current skill direction emphasizes manipulating skills, items, and conditions; Gale acting on Ember can produce different outcomes within that same pair. Specific aiming/selection controls and interaction rules remain to be defined. (S-U)
- Active skills may combine as modifiers: Gust is knockback without damage; Gust + Spark adds fire damage and a burn chance. Passive Ember heat tolerance and an active Gale cooling whirlwind are a separate environmental-survival combination. (S-V)
- Enemies have hue influences and weaknesses that interact with the player's abilities and equipment. (S-C)
- Many enemies are made from resources, connecting combat and material acquisition. (S-C)
- Supplied examples include a stone golem whose defense can be weakened by Ember and a Verdant beast that yields bone/hide. These do not establish a universal elemental damage chart. (S-C)
- Difficulty increases toward biome cores. Environmental defenses can detect and attack unsuitable/inadequately camouflaged explorers. (S-C)
- Camouflage reduces detection; the supplied prose treats it as important or necessary in dangerous regions. Exact detection, immunity, compatibility, duration, and escape rules are not recovered. (S-C, S-S)
- Cross-hue learning, equipment crafting, and mastery expand combat options. (S-C)
- Attack targeting, hit detection, dodge/block controls, cooldowns, damage equations, death penalties, respawn, PvP, and loot ownership are unrecovered. TMW's existing behavior must not be assumed to be the intended Aethyra rule for these.

## 7. CP-P — Villages, factions, and economy

- Villages/factions specialize in resources and crafting associated with their biome/hue. (S-P)
- More difficult biomes can offer better resources/equipment. Access depends on reputation, mastery, or quests. (S-P)
- Reputation grows through trade, fulfilling requests, and helping upgrade infrastructure. (S-P)
- Better reputation unlocks improved deals and rarer goods. (S-P)
- Opposing-hue factions can pay more for resources that are difficult for them to obtain. (S-P)
- Donating resources and crafted components upgrades village production infrastructure, increasing production complexity and available trade goods. (S-P)
- Some items/resources/components are only available through trade under the progression/reputation restrictions described. Exact exclusivity rules are unrecovered. (S-P)
- Factions compete over resources, territory, and trade influence. (S-P)
- Supporting one faction can worsen relations with rivals, including restrictions or hostility. (S-P)
- Supplying rare resources and powerful infrastructure components can alter economic power, open routes, affect prices, or provoke rivalries. (S-P)
- Player-owned production and village investment compete for the player's resources. (S-P)
- Skills influence gathering/crafting efficiency and NPC interaction. (S-P)
- Current direction specifies a simulated economy in which NPCs also participate as players. (S-N)
- NPCs share access to the same breadth of skills available in the world. This does not mean each NPC has already mastered every skill. (S-U)
- NPC-crafted goods must not be inherently limited to inferior quality compared with player goods. Individual capability, materials, machinery, and process can vary; the detailed quality formula remains open. (S-U)
- NPCs serve as passive tutorials by demonstrating what machinery and skill combinations can accomplish. The exact observation/inspection interface and knowledge-unlock consequences are undecided. (S-U)
- Player ownership of land and shops, and participation in government, should form an environment in which NPCs also operate. Puzzle Pirates is a reference for this integration, not an automatic adoption of its specific laws or production rules. (S-U)
- The world is primarily NPC-filled. Exploration exposes players to mastery, skill combinations, and the ways each hue culture interacts with its environment. Hybrid NPCs are rarer and can provide insight into endgame possibilities. (S-V)
- NPC demonstration is established; whether observation records a recipe, grants a formal unlock, awards mastery, or simply informs the human player's understanding is still unspecified.
- Skilled NPCs may be hired to operate parts of production processes. This extends their possible role from demonstration and independent production into the player's workforce; mandatory staffing and employment rules are not yet defined. (S-X)
- Production specialties are now explicit: Verdant wood framing; Tide precision-cut metal/cooling; Ember refined materials/power systems; Terra raw materials. Gale's earlier lightweight-material specialty remains relevant. Rare high-level Decay/Aura/Void processes add powerful and chaotic effects. (S-G, S-V)

**Not yet recovered:** whether all goods require conserved physical inputs; finite NPC inventories; currency creation/removal; price formulas; NPC budgets and consumption needs; autonomous travel/gathering/learning; ownership of workshops; freight/logistics; market clearing; bankruptcy; catch-up when no human is online. These are implementation/design gaps, not grounds for discarding the established economy.

## 8. CP-E — Events and world changes

- Random events can introduce challenges and resource/progression opportunities. (S-E)
- Hue storms create resource-rich situations while increasing danger/enemy activity. (S-E)
- Storms or environmental triggers can temporarily mutate resources and grant rare harvesting bonuses. (S-E)
- Exploitation can trigger biome reactions, corruption, elementals, Void creatures, or progression toward a Void biome. (S-E)
- Time-limited trade opportunities can offer rare goods/resources. (S-E)
- Component donations can trigger village upgrades and better production/trade offerings. (S-E, S-P)
- Some quests or resource spawns are tied to events. Rare events can grant significant upgrades, blueprints, or resources. (S-E)
- Event frequencies, triggers, duration, scope, notification, repeatability, and treatment of absent players are unrecovered.

## 9. Corrections and unresolved overlaps

| Earlier wording or tempting inference | Recovered treatment |
|---|---|
| Common/rare/exotic are resource tiers | Superseded by Roman numerals with no fixed upper bound; rarity can remain a separate property |
| Mundane resources dominate; hue resources are always exceptional | Superseded by the clarification that hue-infused resources are abundant and can be more common |
| Hardness equals durability | Hardness was clarified as impact/pressure tolerance; component durability is separately tracked |
| Every hue needs a unique bonus for every equipment category | User rejected attribute proliferation and refocused discussion on material properties and resulting structure behavior |
| Every Verdant/Aura resource repairs itself | Only some resources of those affinities have the special property |
| Opposing hues always make structures unusable | Later rules deliberately use opposition to control unwanted effects; reaction conditions need specification |
| All components need hue input | Passive components exist; manual-fuel and direct-skill heat sources exist; precise activation rules need reconciliation |
| The earliest furnace example is the complete final anatomy | Later user supplied the six-part anatomy; updated port counts are not recovered |
| More thermal capacity means higher temperature tolerance | These are different concepts; the game uses both but lacks a complete mapping |
| Mastery, character levels, and skill proficiency are one progression variable | The CPL names separate concepts; their exact relationships need definition |
| Basic harvesting begins only in midgame | Starting-hue harvesting is explicit; current phase direction should be interpreted without silently removing it |
| Machinery requires permanent land ownership | Camps can host machinery; advanced automation is now described as endgame, with the boundary from earlier field equipment still open |
| Every hybrid is a separate hotbar skill | Latest direction emphasizes manipulation and workflow combinations, including multiple outcomes for one hue pair |
| A hue altar is merely an unspecified landmark | It taps a regional core, unlocks hue manipulation, and can teach region-specific abilities |
| NPC goods are always weaker than player-crafted goods | NPCs have access to the same breadth of skills and can produce competitive goods |
| A generic physical wind/fire interaction defines all hybrids | Latest examples distinguish passive/active exploration buffs, active combat modifiers, and timed crafting processes |
| Player energy is one unspecified global mana value | Each hue has a maximum and passive regeneration influenced by mastery, gear, status, and environment |
| Combinations must be either prepared or improvised | Both are supported: experiment on the fly, then refine spell assemblies |
| More stored energy automatically permits more simultaneous skills | Mastery-linked slots are the intended direction; balance remains provisional and storage does not establish more slots |
| Early hue storage requires Aura crafting | Local natural materials hold limited reserves and can later be refined; Aura vessels support advanced machinery |
| Aura vessels accepting any hue means they mix or convert all hues freely | Universal compatibility is confirmed; simultaneous mixtures, conversion, and handling rules are not |
| NPCs only demonstrate or sell finished goods | Hired NPCs with particular skills may also operate production stages |
| Sustainable Gale energy implies unlimited cooling | Gale cooling has an effect ceiling; an Ember heat-redirection skill can stack protection |
| Every missed crafting condition has the same consequence | Material, recipe, and yield determine whether the process pauses, fails, or damages the crafter/equipment |
| Camps are permanent protected homes | Camps are temporary rest points with expiring claims; abandoned equipment can be taken by passing players/NPCs |
| Tide's entire role remains deferred | Latest user decision explicitly assigns precision-cut metal and cooling systems |
| Village trade proves every NPC already has finite simulated stock | Trade/infrastructure are defined; individual conservation/autonomy was not recovered |
| Every descriptive biome feature is mandatory procedural content | Recovered landscape descriptions need to be separated from simulation rules |
| AuraFuse simply means Aura | The term appears in the user's request; no separate dependable definition was recovered |

## 10. Context-only material deliberately kept out of established canon

- **Earlier 2023 worldbuilding:** a wider set of hues (including Ice, Metal, Lightning, Celestial, and named hybrids) and a spiritual energy origin in the world's core were recovered. This may be useful history, but it is not automatically part of the later eight-hue CPL.
- **Earlier named places and seasons:** older setting descriptions and another Aether/season vocabulary appeared in retrieval. Their incorporation into the later CPL was not established; they are not merged here.
- **Aura/Void elaborations:** historical assistant readbacks proposed Void-related reductions in density, conductivity, and capacity, stealth/anti-hue equipment, and Aura-related amplification, reflectivity, storage, and illumination. Some retrieval summaries attribute parts of similar text to the user, while others identify assistant responses. Broad production themes are recorded as context, but those complete bonus lists are not promoted to approved rules.
- **Decay elaborations:** corrosion-resistant containment/material suggestions were recovered, but their acceptance and exact property mapping remain unverified.
- **Tide elaborations:** the user explicitly liked cooling stability and rejected or deferred other suggested bonuses. Earlier broad Tide claims should not be used to fill out an exhaustive bonus matrix.
- **Later Tide clarification:** S-V now explicitly adds precision-cut metal and cooling-system production. This updates the production role without approving every earlier speculative Tide attribute bonus.
- **Workbench recipe:** a historical assistant example uses a top, frame/legs, and tool rack with specific wood/stone quantities. The full approval and final recipe were not recovered, so no numeric recipe is adopted.
- **Code structure:** earlier Resource/Structure/Hue/Skill/Combat manager proposals are implementation suggestions. They are not a binding architecture or evidence that their schemas already exist.
- **Unnamed structure examples and stories:** user praise indicates that some examples worked well, but missing assistant text prevents recovery of their precise components or lore.

## 11. Implementation implications for the TMW integration plan

These are derived requirements, not newly approved gameplay mechanics. No code changes or engine choice are made by this document.

| Established behavior | Likely software requirement |
|---|---|
| Material-dependent components with individual wear and repair history | Separate item definitions from individual component instances; preserve state through storage, trade, installation, and restart |
| Structures assembled from core/accessory components | Explicit slot requirements and installed-component relationships |
| Temperature/pressure/hue operating limits and deliberate overload | A consistent operating-state and wear model with visible causes |
| Type-specific energy inputs, limited ports, and core priority | Hue supply/connection model and operation eligibility rules |
| Multiple mastery trees, skill points, and use proficiency | Distinct progression records with explicit unlock rules |
| Identification becoming persistent knowledge | A discovery/knowledge record with a defined owner/scope |
| Regional hue concentration, depletion, and Void reactions | Persistent environmental state and specified renewal/transition rules |
| Donations altering village production and trade | Persistent infrastructure upgrades connected to goods/production availability |
| Shared small-server world with NPC participation | Server-owned economic/world state; defined concurrency and offline behavior |
| Cozy onboarding and outward cultural discovery | A first playable settlement and progression sequence that exposes existing mechanics gradually |
| Skills, items, environmental challenges, and machinery interact | A shared effect/operation model with explicit targets, conditions, and outcomes; human/NPC/machine use should resolve through compatible rules |
| Regional altars unlock hue manipulation and varied abilities | Distinct hue-unlock state, origin-related progression modifiers, regional teaching content, and exploration defenses |
| Midgame camps followed by acquired land | Separate field deployment/persistence rules from permanent property/settlement rights |
| NPCs as capable producers and passive teachers | NPCs execute inspectable production/skill workflows under the same capability rules; individual decision logic can be authored |
| Multiple skills and per-hue energy budgets | Hue-specific resource accounting, capacity/regeneration modifiers, active effects, and combination rules |
| Improvised combinations and refined spell assemblies | A common representation for live combinations and reusable assemblies, with validation against the actor's capabilities |
| Provisional mastery-linked activations and likely tier-based slot costs | Configurable activation rules distinct from energy accounting; slot scope, occupancy, and progression thresholds await iteration |
| Natural vessels, refinement, and universal Aura storage | Persistent vessel contents/capacity, material-dependent compatibility, and equipment contributions; Aura accepts any hue, while charging and mixing rules await decisions |
| Voltage/current/power-like hue calculations and vessel disintegration | Distinguish stored energy from delivery behavior; evaluate overload and destruction under explicit material rules; preserve energy accounting when components fail |
| Maximum vessel current, reusable low-level use, and possible instant stack destruction | Track capacity and current rating separately; an action resolves charge use, affected vessel quantity, destruction, and spell outcome consistently under server authority |
| Exceptional mastery, hue-flow modifiers, and calculated chance allow demanding use of weak materials | Make resolution tunable from skill demand, vessel state, actor mastery, and explicit modifiers; random outcomes should be server-owned and reproducible in simulation checks, without granting locked skills |
| All starters teach exploration, combat, and crafting through distinct hue cultures | Reusable teaching/progression structure with hue-specific activities, environments, and NPC workflows |
| Gale descent/ascent between elevations, knockback combat, and mobility/concealment crafting | Gameplay elevations distinct from draw order; directional traversal eligibility, valid landings, displacement/edge handling, and observable effects from one initial recipe |
| Harvesting modules, buffers, pipes, and machine inputs | Explicit network connections, hue routing, energy accounting, and process supply requirements |
| Possible skilled NPC staffing of production stages | Tasks with capability requirements and worker assignment, using the shared skill/process rules |
| Timed crafting conditions with recipe-specific outcomes | Process state with required conditions, elapsed progress, and explicit pause/failure/damage policies |
| Camp claim expiry and salvage | Ownership/expiry state and consistent equipment transfer after abandonment, available to human and NPC actors |

Material affinity, active input requirements, temporary operating state, and learned player knowledge should be kept distinguishable. Their interactions need explicit rules before a coding agent is asked to invent a common data model.

### 11.1 Historical repository inspection — 4 October 2026

This was a source and metadata review through GitHub. No repository was modified, compiled, or launched. Build viability, runtime behavior, server compatibility, and asset-license completeness are untested.

**Located revisions**

- The supplied organization exposed four repositories: Client, Website, windows-build-support, and osx-build-support. No server or world-content repository appeared in that organization result.
- [Aethyra/Client](https://github.com/Aethyra/Client) master was `4d238e25c73fedde78a77deeebfd742b70d85a1c`, dated 10 January 2011. Its README identifies version 0.0.29.1 with an older 29 March 2009 date; these are different facts.
- [Tametomo/Aethyra](https://github.com/Tametomo/Aethyra) master was `a9265de2848d824fb6efcdebb74e60f7d5084901`, dated 26 July 2012. GitHub's [comparison](https://github.com/Tametomo/Aethyra/compare/4d238e25c73fedde78a77deeebfd742b70d85a1c...a9265de2848d824fb6efcdebb74e60f7d5084901) reports 25 commits ahead and zero behind the organization revision. It is a candidate baseline to review before restoring the older branch.
- The archived TMW-forks/aethyra master ended at a 30 January 2010 commit; its later repository push date does not establish newer game code.

**Reusable candidates and gaps**

| Inspected evidence | Consequence for the prototype |
|---|---|
| [Dye implementation](https://github.com/Aethyra/Client/blob/4d238e25c73fedde78a77deeebfd742b70d85a1c/src/core/image/dye.cpp) dispatches seven source-color channels to palettes | Multichannel recoloring exists and can inform hue appearance; this does not establish who originally invented it or that it was unique to Aethyra |
| [Map reader](https://github.com/Aethyra/Client/blob/4d238e25c73fedde78a77deeebfd742b70d85a1c/src/core/map/mapreader.cpp) handles XML tile layers, collision, tilesets, and legacy base64/gzip layer data | A tile-map grassland is a plausible reuse target; verify export compatibility rather than assuming every current map format is supported |
| [Build requirements](https://github.com/Aethyra/Client/blob/4d238e25c73fedde78a77deeebfd742b70d85a1c/INSTALL) name SDL-era libraries, Guichan 0.8.x, and PhysFS 1.0.x; Autotools and CMake files exist | A reproducible build/restoration trial is required before choosing this runtime; no successful modern build is claimed |
| Client tree includes UI/font/help assets but no playable map or world sprite collection; [state manager](https://github.com/Aethyra/Client/blob/4d238e25c73fedde78a77deeebfd742b70d85a1c/src/eathena/statemanager.cpp) loads external updates | Recover historical content archives or assemble an appropriately licensed starter content pack; repository code alone is incomplete as a playable world |
| [Item model](https://github.com/Aethyra/Client/blob/4d238e25c73fedde78a77deeebfd742b70d85a1c/src/eathena/structs/item.h) stores type ID, quantity, equipment flags, and inventory index | Individual vessels need additional identity and persistent state: stored hue, energy, material limits, condition, and component relationships |
| [Inventory handler](https://github.com/Aethyra/Client/blob/4d238e25c73fedde78a77deeebfd742b70d85a1c/src/eathena/net/inventoryhandler.cpp) and [skill handler](https://github.com/Aethyra/Client/blob/4d238e25c73fedde78a77deeebfd742b70d85a1c/src/eathena/net/skillhandler.cpp) use existing eAthena packets and RPG skill records | Hue state requires deliberate client/server protocol and persistence work; adding sprite colors or item definitions alone is insufficient |

The inspected source headers state GPL version 2 or later. Asset attribution and distribution requirements should be checked against the files actually selected for reuse; this review is not a complete licensing audit.

**Proposed implementation sequence**

1. **Reproducible baseline:** review the 25 later commits, pin a revision, establish a local build, provide one test map/character, and resolve the server/content source. Acceptance: the character walks around the grassland with working collision and a recolored sprite. Choose whether to retain the client after this evidence.
2. **Small hue simulation:** specify one hue, two vessel materials, one conduit, and one load. Use proposed quantities for stored energy, potential, hue current, and delivered power. A possible normalized model uses `P = U × I` and `E_next = E + (P_in − P_out − losses) × dt`; these are implementation proposals, not approved game equations. Potential-versus-stored-energy behavior, sharing between vessels, and failure rules need explicit definitions.
3. **Authoritative state and persistence:** make the server own charge, wear, destruction, ownership, and transfers. Connect the simulation to client display/controls. Acceptance: two clients see the same results; dropping/trading/reloading preserves state; overload can remove the affected stack exactly once and handles its energy and spell outcome according to the chosen rule. A reusable low-current action and an instant stack-destruction action are distinct checks. (S-AA informs the proposed checks.)
4. **Gale gameplay loop:** a cozy NPC/settlement, one local vessel material, elevation traversal using featherfall for descent and a separate upward jump, a Gust/evasion encounter, and a crafting activity that improves one relevant capability. Introduce better vessels/conduits through an understandable limitation. These three learning goals follow S-AC and the traversal roles follow S-AD; the exact route, skill acquisition order, sequence, and content remain proposals.
5. **Minimal production network:** connect harvesting, Aura buffering, conduits, and one process with a possible skilled NPC stage. Keep slot counts and numeric balancing configurable; add larger economy behavior after the physical production loop works.

Agentic coding tasks should each name the intended behavior, touched state/protocol, and an observable completion check. The first task is a reproducible baseline, followed by a small shared simulation, rather than an unrestricted request to transform the entire client into the final game.

## 12. Remaining questions — ask in stages

The previous questions are partly resolved by S-U through S-Z: altar purpose/unlocks are defined; prepared and improvised combinations are supported; mastery-linked activations remain the direction but balance is deliberately provisional; natural vessels provide early storage; Aura vessels accept any hue and support advanced machinery; networks use modules, inputs, and pipes, potentially with skilled NPC operators. Gale grassland, the historical repository location, and Len's art foundation are now selected. Low-capacity vessels can combine and disintegrate under overload; voltage/current/power-like calculations are intended. Camps, cultural NPC demonstrations, and process-dependent crafting consequences remain established. Do not require final slot balancing before defining a first playable slice. Natural-vessel recharge after harvesting remains unanswered and is deferred alongside other numerical/access rules.

Next questions:

1. **Knockback at elevation edges:** Can Gust push enemies off ledges to a lower map level? If allowed, fall consequences and enemy/player consistency can be specified next; falling damage or instant kills are not assumed.

S-AD resolves the traversal roles: featherfall descends map layers without stairs, and a separate skill jumps back up. Use this to build a first elevation test instead of repeating the broad free-movement-versus-contextual-action question. Exact controls remain an implementation choice awaiting later definition.

S-AC resolves the opening's learning scope: every starter teaches exploration, combat, and crafting, with hue-specific experiences. Do not ask the player to choose only one of those three foundations. Exact first tasks can now be proposed as a connected sequence.

The previous cast-outcome question is resolved at the design-principle level by S-AB: several calculations and chance apply; extraordinary mastery, flow-improving equipment/skills, or a successful roll can permit demanding use of weak materials. The precise formula and vessel-survival correlation can wait for iteration rather than prompting another binary success-versus-failure question.

Later questions, not all at once: skill duration/upfront versus sustained costs; activation allowance scope/occupancy; vessel charging, natural-material hue compatibility, and Aura mixing rules; machine/assembly relationships; skilled NPC employment; camp claim timer/renewal and offline operation; core-assisted energy mechanism; formal learning gates from NPC observation; exact material-stat equations; passive versus supplied affinity effects; port allocation; recipe bootstrap; identification scope; failure/repair costs; combat controls and death; PvP; NPC stock conservation; offline economic production; land acquisition/governance; depletion/renewal timing; event scheduling; world geometry; persistence/migration requirements.

### Proposed next planning step — first playable loop

Use the selected Gale windswept grassland and Len's tileset to define a small return journey. Proposed terrain test: a terraced area with an ordinary stair route, a featherfall descent, and an upward-jump route. Proposed teaching sequence: learn traversal near the settlement; encounter an enemy where Gust creates room to evade; collect a local material; return to manipulate it into one speed-, stealth-, or evasion-related improvement; revisit part of the route to feel the result. This covers the three established learning foundations before numeric balancing is finalized. Exact terrain, materials, skill acquisition order, quests, and improvements remain proposals. It does not imply that advanced Aura crafting or complete automation must appear in the opening.

The initial repository inspection is recorded in section 11.1. Next, establish a reproducible runtime and map movement, actors, inventory, skills, crafting, and persistence against this loop. Later, test a minimal harvesting-module → Aura-buffer → machine network, with one possible skilled operator stage. These are implementation proposals, not an approved release scope or a decision to retain a particular old engine revision.

### Selected art foundation — import preparation

The [OpenGameArt source page](https://opengameart.org/content/whispers-of-avalon-grassland-tileset) credits Leonard Pabin and offers CC BY 3.0, GPL 3.0, and GPL 2.0. It describes 32-pixel tiles with some 64-pixel groups and separately credits Crush for the barrel's underlying work. The ground sheet also visibly labels a 96-pixel sample. The six source files cover ground, cliffs, objects, layered tree artwork, water-flow graphics, and unfinished extras.

The source-art bundle preserves the downloaded bytes and includes a manifest with dimensions, hashes, source URLs, and attribution. It is an import-ready archive of sources, not a completed engine import, tile-definition file, or playable map. No image pixels were edited.

Proposed import steps: preserve originals; select valid tile rectangles on the 32-pixel grid; register larger groups explicitly; exclude labels, previews, and credit blocks from selectable terrain; define collision and foreground layering separately; choose a compatible map export for the selected runtime. Retain the layered PSD as source artwork. Preserve credits in project attribution rather than erasing them from originals.

Visual direction inferred from the inspected ground sheet: pale greens, warm earth, cool water, and softly shaded textured forms. Preserve these as an art reference; express Gale through motion and environmental details added later. The original client's recoloring dispatches specific source-color channels, so full-color terrain is not automatically suitable for that dye system. Keep original terrain colors initially; later recolorable assets can use deliberately authored masks or compatible palettes.

For an import under the offered CC BY 3.0 option, retain the title, Leonard Pabin credit, source and license links, relevant Crush credit, and notes on derivative changes. [Creative Commons' deed](https://creativecommons.org/licenses/by/3.0/deed.en) documents attribution and adaptation conditions. This note does not change the separate licensing of reused client code.

### External design reference: Puzzle Pirates

The user's reference identifies land, shops, and government as relevant precedents. Official economic documentation describes production chains built from commodities and labor, including NPC merchant transport. YPPedia's shop/governor documentation describes shops, property deeds, construction authority, and taxation. These provide comparison material; specific rules are not adopted into Aethyra by this note.

- [Official economy documentation](https://yppedia.puzzlepirates.com/Official:Economy)
- [Shoppe](https://yppedia.puzzlepirates.com/Shoppe)
- [Governor](https://yppedia.puzzlepirates.com/Governor)

### Proposed first integration test — not yet approved scope

Use the user's concrete cases as small independent integration checks: (1) Gust versus Gust + Spark, with separate hue energy accounting; (2) passive Ember heat tolerance plus an active Gale cooling whirlwind in an extreme Ember area; (3) one material-processing operation requiring sustained conditions. An NPC can demonstrate a workflow once its rules are specified. Camp claim expiry/equipment salvage is a separate persistence check. Exact costs, controls, ranges, interruption behavior, and access gates must be defined first. These checks do not lock a release scope or defer camps/automation until permanent land ownership.

## Source register

Source labels reference the user-supplied root-chat excerpts in this conversation. Message numbers are the original `msg_idx` labels where provided, not invented timestamps.

| Label | Source |
|---|---|
| S-R | Supplied CP-R entry before root message 15: classification, harvesting, attributes, refining, identification, concentration, depletion/renewal, and hue combinations |
| S-B | Root message 16, CP-B: foundations/components, refining, automation, hue flow |
| S-P | Root message 16, CP-P: villages, trade, reputation, donations, faction competition, influence |
| S-C | Root message 18, CP-C: live-action combat, environmental interactions, resource enemies, biome defenses |
| S-E | Root message 18, CP-E: storms, mutations, biome reactions, faction events, event-gated progression |
| S-S | Root message 19, CP-S: trees, hybrid skills, one point per level, use proficiency, mastery 0–50, examples |
| S-T | Root messages 32–34: required/accessory slots, active/passive components, two-port furnace example, input priority, overload, durability and repair |
| S-M | Root messages 41–43: correction of invented hue bonuses; component limits; intentional overload; material-derived specs; hue-resource abundance; Verdant/Aura exceptions |
| S-A | Root messages 44–52 and 81–91: concise integration; density/weight; hardness/impact-pressure; Roman tiers; rejection of excessive attributes; restored temperature conductivity |
| S-G | Root messages 56–58, 75–80: Gale material focus, hammer/foundation examples, sandblasting, Aura/Gale cloth, category refactoring, Tide cooling-stability correction |
| S-F | Root message 61: latest explicit furnace anatomy and direct skill-powered heat |
| S-D | Root messages 62–63: gradual complexity, intuitive onboarding, optional depth, and explicit endorsement |
| S-Q | Root messages 93–100: early base/workbench simulation and architecture questions; missing responses are not silently reconstructed |
| S-N | Current 4 October 2026 conversation: original project history; cozy homeland; cultural exploration; progression emphasis; small server; simulated NPC economy |
| S-U | User answers at 12:56 PDT on 4 October 2026: altar/core relationship, environmental protection, origin difficulty, regional teachings, conditional recipes, manipulation-based skill workflows, Gale/Ember outcomes, camp machinery, later land economy, Puzzle Pirates reference, NPC capability and passive tutorials |
| S-V | User answers at 13:17 PDT on 4 October 2026: multiple skills, hue-specific maximum energy/passive regeneration, core-dependent skills, concrete exploration/combat combinations, timed process conditions, cultural crafting roles, rare high-level Decay/Aura/Void, timed camp claims/abandonment/salvage, primarily NPC world and rare hybrid NPCs |
| S-W | User answers at 13:32 PDT on 4 October 2026: improvised and refined spell assemblies; mastery-limited activation slots and likely tier costs; Gale regeneration and environmental exceptions; contextual Tide logistics; Terra crystals altered by Aura into carried/embedded energy vessels; Gale cooling ceiling and Ember heat redirection; material/recipe/yield-dependent pause, failure, or damage |
| S-X | User answers at 21:35 PDT on 4 October 2026: iterative skill balancing and provisional mastery-linked activation slots; possible early passive/active restrictions; hue-specific mastery with possible starting-hue/race/origin modifiers; advanced crafting and endgame automation; harvesting modules, capacitor-like Aura storage, piped machinery in camps/workshops/owned areas, possible skilled NPC operators; natural early vessels and refinement; stronger storage near cores/altars; any-hue Aura crystals required for automation/machinery |
| S-Y | User answers at 21:44 PDT on 4 October 2026: likely voltage/amperage/wattage-like hue calculations; low-capacity vessels usable together; excessive energy causes disintegration; scaling demand for better vessels/conduits; Gale windswept grassland chosen; Aethyra GitHub organization supplied |
| S-Z | User message at 21:46 PDT on 4 October 2026: import Len's Whispers of Avalon grassland tileset as art foundation/inspiration; personal contribution history with that project; OpenGameArt source URL supplied |
| S-AA | User message at 21:55 PDT on 4 October 2026: items have maximum hue current and capacity; small low-level skills can permit reuse; a stronger skill/spell can instantly disintegrate an entire stack of low-level vessels |
| S-AB | User message at 21:59 PDT on 4 October 2026: casting requires several calculations and chance; high-level hue-intensive skills using stacks of low-level material should require incredible mastery, specific flow-improving items/skills, or success on a calculated chance roll |
| S-AC | User message at 22:05 PDT on 4 October 2026: every starter teaches exploration, combat, and hue-channeling crafting; Gale featherfall/boosted jump, Gust knockback/evasion, and material manipulation for speed/stealth/evasion; common cadence with distinct hue-cultural experiences |
| S-AD | User message at 22:09 PDT on 4 October 2026: featherfall descends map layers without stairs; another skill jumps back up; distinct Gale pathways make basic Gale mastery desirable for all players |
| R-H | Historical retrieval of CP-H around 2 October 2024 and later Task 3 updates: eight hues, mastery, energy handling, pair examples; original role attribution was inconsistent across summaries |
| R-A | Historical retrieval of later CP-R discussions: seven named properties when weight is separate; confirms thermal conductivity and Roman tiers; direct visible corrections take precedence |
| R-W | Historical retrieval of biome/crafting descriptions around 2–3 October 2024: landscape/affinity descriptions; treated as context where original approval is unavailable |
| R-Q | Historical retrieval around 10 November 2024: first-workbench handcrafting and software examples; approval/role attribution is incomplete |

### Selected direct user anchors

> “Components operating specifications will be directly determined from the resources they are crafted from.” (S-M, message 43)

> “A player may intentionally run a structure outside of its operating parameters in order to acquire higher tier crafting capabilities at the cost of their component durability.” (S-M, message 42)

> “the only hue types that are self-repairing are verdant and aura. They are unique attributes some resources of those hue affinity have. The rest primarily affect operating ranges” (S-M, message 43)

> “Please also associate density with weight and hardness with impact and pressure tolerance. And resource tiers will increase in Roman numerals up to an undefined number” (S-A, message 47)

> “In crafting, opposing hue types are often used to cancel out unwanted attributes or bonuses and complimentary hues are used to boost wanted attributes or bonuses.” (S-T, message 32)

> “The player should grow outwards into the world and feel like a cultural explorer visiting lands of different hues.” (S-N, current direction)

> “visiting a hue altar allows a player to unlock the ability to manipulate that hue.” (S-U)

> “Combos/workflows will be what creates hybrid workflows.” (S-U)

> “NPC crafted goods shouldn't always be inferior to player created ones. They all exist in the same world with access to the same breadth of skills.” (S-U)

> “Some skills may only be possible to activate near a hue core due to the energy needed.” (S-V)

> “In a crafting sense, the players may need to maintain pressure, temperature, hue energy, cooling or other conditions for certain times to create new materials. This is the basis of the economy.” (S-V)

> “Camps will be set up and broken down. They can be claimed for a set time and after will be abandoned and other players/NPCs who wander by may take their equipment.” (S-V)

> “Number of skill activations will be limited by hue mastery. Skills will likely have tiers that consume higher number of activation slots for high level manipulation” (S-W)

> “Terra crystals will be altered by aura crafting to create storage vessels for hue energy. These will be carried and embedded into equipment to increase energy limits and efficiency.” (S-W)

> “Depends on the material, the recipe, depending on its yield, may fail, pause or even damage the crafter/equipment if conditions aren't met” (S-W)

> “Skill customization and balancing will take time and iteration - but yes, I suspect mastery will be linked to activation slots.” (S-X)

> “It may be necessary to hire NPCs with certain skills to man parts of the process” (S-X)

> “Items found in each starting area serve as vessels naturally. Hue collects in them but their reserves are limited.” (S-X)

> “Aura crystals can store any hue and are necessary for the automation/machinery stage.” (S-X)

> “The item will have a maximum current (hue equivalent) and capacity. Small low level skills might make the item reuseable but one stronger skill/spell might instantly disintegrate an entire stack of low level vessels” (S-AA)

> “A player shouldn't be able to execute a high level, hue intensive skill with several stacks of low level material unless they have incredible mastery, items/skills specifically to improve hue flow or pass a calculated chance roll” (S-AB)

> “Each starter area will have a similar cadence but each should host a unique experience for that hue culture” (S-AC)

> “Players could descend map layers without stairs by using featherfall. They can use another skill to jump back up.” (S-AD)

This recovery preserves the rules available now and makes the limits of recovery explicit. Future edits should identify the rule being changed and the source or decision authorizing that change.
