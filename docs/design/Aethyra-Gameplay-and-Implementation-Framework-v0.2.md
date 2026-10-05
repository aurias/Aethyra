# Aethyra — Gameplay and Implementation Framework

Version 0.2 · 5 October 2026 · Planning baseline: user-confirmed working Windows demo

## 1. Purpose, authority, and present state

This document explains the gameplay systems, character progression, interface, and implementation sequence needed to grow the existing Aethyra/TMWA demo into the defined game. It is both a coding-agent handoff and a reusable framework for future biomes and production content. Each implementation pass crosses server rules, persistence, client presentation, and playable content; completion means a working experience, not only new classes or windows.

**Evidence labels used throughout:** Established means a user-defined rule recorded in the mechanics reference; Demonstrated means the user reports the packaged feature works; Inspected means supporting package content was read; Proposed means a reversible design or implementation choice. Historical recovered rules remain subject to later explicit user corrections. Requesting this plan does not make every proposal canonical.

On 5 October the user confirmed the attached Windows binary runs and all included skills behave as expected. The package contains a 40×30 Gale map, Dash, non-damaging Gust, Wind Scythe harvesting, regenerating Gale energy, resources, Gust Hoppers, and Windkeeper Ama's herb/petal-to-tonic exchange. Hosting and persistent-world setup are documented in the package. Client collision and server walk data were inspected and agree on all 1,200 cells. The assistant has not run the binary, audited the merged C++ source, verified multiplayer synchronization, or tested save/restart behavior. Those remain validation tasks for the implementing agent, not reasons to restart the project from an old upstream checkout.

**Use the current merged source repository that produced this demo.** Its location and exact commit are not supplied in this planning turn. The executable archive is a reference build, not sufficient source for a maintainable implementation. Locate the actual checkout in the coding environment; if it is unavailable, report that specific source dependency. Historical Aethyra/TMWA commit candidates are provenance, not instructions to replace newer working integration.

The earlier starter-zone specification predates the working binary. This framework supersedes its assumption that integration must begin from zero; the recovered mechanics reference remains the design record.

## 2. The experience and its progression

The player begins somewhere welcoming, learns how their homeland uses its hue, and gains reasons to return. Movement, combat, gathering, and making things express the same cultural knowledge. As the player travels, learning other hues changes their options rather than merely changing damage colors.

Len's Whispers of Avalon grassland tileset remains the selected Gale art foundation. The working demo's placeholders are an effective functional baseline; replace them through the existing asset pipeline while preserving tile alignment, collision and sprite action definitions. Future cultures should express their own materials and uses of hue within a coherent art direction.

| Phase | Player activity | Systems that must support it |
|---|---|---|
| Homeland | Meet residents, learn safe movement and resource use, evade threats, make something useful | One hue; natural vessels; readable actions; forgiving practice; introductory processing |
| Regional exploration | Prepare for hazards, seek better materials, discover protected altars | Environmental exposure; equipment; mastery; traversal; resource identification; regional knowledge |
| Cross-cultural play | Learn another hue and combine capabilities | Separate hue progression and reserves; live combinations; saved assemblies; culturally different solutions |
| Midgame expeditions | Establish temporary camps, sustain protection, process resources in the field | Claims, deployables, limited machinery, process controls, energy supply, component wear |
| Advanced production | Assemble harvesting, storage, conduits, machines, and skilled labor | Aura-compatible storage; modular components; shared process rules; bounded network simulation |
| Settlement/endgame | Own workshops/shops, trade, invest in communities, explore extreme regions | Economic actors, property, reputation, NPC production, governance hooks, world consequences |

Machinery can exist in camps before permanent land ownership. Advanced networks are an endgame emphasis, not a reason to postpone every field device. The boundary between simple camp equipment and Aura-dependent automation needs a bootstrap route; a proposed route appears below.

## 3. Character model and mastery

### 3.1 Separate the progression records

| Record | Gameplay meaning | Required representation and display |
|---|---|---|
| Origin | Homeland and starting hue; possible racial/origin influences | Stable origin ID and explicit modifier sources; do not invent selectable races |
| Character level | Broad progression; the recovered design grants one skill point per level | Level, experience, unspent points, purchase history; separate from hue mastery |
| Hue access | Permission to manipulate a hue | Per-hue unlock state and learning provenance; altars unlock additional hues |
| Hue mastery | General capability in a particular hue | Separate mastery value and progress per hue; recovered scale 0–50 |
| Learned abilities/perks | What the character knows and has invested in | Definition IDs, prerequisites, purchases/grants, upgrade state |
| Skill proficiency | Familiarity gained by using a particular skill | Per-skill use progression; upgrade-defined caps; not another name for hue mastery |
| Current hue state | What the character can supply now | Personal energy, derived capacity, regeneration, conditions, selected external supplies |
| Active commitments | What the character is sustaining or executing | Occupied activation allowance, drain, dependencies, cancellation and expiry state |
| Equipment and knowledge | Physical capability and learned understanding | Item instances, modifiers, identified resources, recipes, observations and discoveries |

Mastery 0 represents an unlearned hue in the recovered model; basic usability starts at 1. Store access explicitly so migrations and exceptional grants cannot accidentally equate a numeric field with permission. A Gale-origin test character may begin with Gale access and selected introductory skills as a proposed onboarding grant. This does not make an altar visit unnecessary when learning a new hue.

Origin may affect progression in another hue. Keep the affected variable explicit—experience rate, a threshold, or another defined modifier—rather than silently applying a penalty to every statistic. Start with neutral configurable modifiers until differences are deliberately authored.

### 3.2 What mastery changes

Mastery should influence the capabilities already established: collecting, storing, channeling, crafting, fighting, and maintaining more complex skills. Give each effect its own tunable curve. Do not make mastery a universal percentage applied to all calculations.

Proposed first implementation uses small authored tables for personal capacity, regeneration contribution, activation allowance, and flow-control contribution. Skill prerequisites reference these capabilities. Values are tuning data; the 0–50 mastery scale is not permission to invent fifty mandatory skills per hue.

Level experience, hue mastery progress, and individual skill proficiency require distinct award policies. Proposed awards come from meaningful resolved actions: a valid harvest, a completed process, a relevant encounter, or a traversal challenge. Empty repeated casts should not be the default optimal training method. Record event IDs so retrying a request cannot duplicate an award. The precise award rates and anti-repetition curve are tuning decisions, not recovered canon.

### 3.3 Activation allowance and sustained effects

The established direction links simultaneous activations to mastery, with higher-tier manipulation potentially occupying more allowance. Capacity and activation allowance are different: a larger vessel does not automatically let a novice sustain more skills.

Proposed first policy: per-hue activation budgets plus a configurable character-wide ceiling to prevent acquiring many beginner hues from granting unlimited concurrency. Keep both policies replaceable; neither scope nor numerical table is finalized. Show the actual limiting budget in the UI.

An instantaneous action reserves its allowance through execution; a sustained action reserves it until cancellation, interruption, or completion. A maintained passive may reserve allowance or impose another authored cost. A permanent perk is a separate definition type, preventing every passive benefit from being treated as a continuously cast spell. Start novices with simple combinations; demonstrate increased concurrency with an advanced test character.

Define cancellation behavior: release reservations exactly once; stop future drains; preserve already-spent resources and completed effects. Losing a required item or supply pauses or ends the effect according to its definition. A disconnect policy must not leave a free defensive effect operating indefinitely.

### 3.4 Replace legacy statistics deliberately

Audit every use of STR/AGI/VIT/INT/DEX/LUK, attack, defense, weight, HP/SP, job/character levels, and old skill points in the merged source before changing them. This is a dependency audit, not a mandate to retain those names in the finished character sheet.

Expose player-relevant results—health, movement, carrying load, protection, hue capacity, regeneration and control—while routing legacy calculations through explicit adapters during migration. Retain the working basic attack and healing loop until their replacements are tested. Do not introduce a second competing source of truth for the same energy or progression value.

## 4. Skills, assemblies, and interaction rules

### 4.1 Skill definitions

A skill definition needs an ID, hue requirements, prerequisites, proficiency progression, action kind, activation cost, targeting constraints, execution duration, energy/current demand, effects, condition dependencies, interruption behavior, feedback references, and any cooldown. Fields are authored only when applicable. A harvesting skill does not need a fictitious damage field merely to fit a combat schema.

Use a limited vocabulary of implemented effects: displacement, material harvest, protection, condition adjustment, energy transfer, processing input, and status application. New effects require code; new combinations of supported effects should primarily require content data. Avoid building a general scripting language before these primitives work.

| Gale ability | Status | Next implementation role |
|---|---|---|
| Dash | Working demo behavior | Preserve movement feel; route through shared action cost and collision rules |
| Gust | Working demo; non-damaging knockback is established | Add explicit direction/range rules, vessel supply, and approved downward ledge displacement |
| Wind Scythe | Working demo behavior | Preserve harvesting; connect to material properties, proficiency, tools, and energy accounting |
| Featherfall | Established traversal direction, not verified in demo | Descend a legal elevation transition without stairs |
| Upward jump | Established traversal direction, not verified in demo | Reach a legal higher landing using a distinct skill |
| Gale material manipulation | Established crafting direction | Channel into a process that changes one meaningful material/item property |
| Sustained Gale cooling | Established cross-hue exploration example | Later environmental protection with a cooling ceiling and ongoing supply |

Existing key bindings may remain as shortcuts. The long-term interaction model must also let players target items, processes, surfaces, and other effects; it cannot assume every skill targets an enemy.

### 4.2 Live combinations and saved assemblies

Both experimentation during play and prepared assemblies are established. A proposed live interface lets the player select a base action, add compatible learned modifiers, preview the combined requirements, and execute. A saved assembly records those same selections and parameters. It does not bypass prerequisites, energy costs, activation limits, or mastery by becoming one button.

The first combined combat fixture is Gust + Spark: retain displacement, add fire damage and a burn chance. The first sustained exploration fixture is Ember heat tolerance plus Gale cooling. A later variant redirects heat with Ember to extend the usefulness of Gale cooling. Track each hue's expenditure separately.

Do not make a universal table in which every hue pair always yields one named spell. Gale acting on Ember may boost, suppress, disperse smoke, or affect temperature/pressure depending on the authored operation and target context. Start with a small explicit interaction registry that defines compatibility, ordering, outputs and limits. Reject unsupported combinations clearly; do not invent emergent physics from color overlap.

A spell assembly describes player actions. A machine workflow describes connected processes and supplies. They can reference common effects and conditions without becoming the same object or automatically compiling spells into machinery.

## 5. Hue energy, vessels, and material progression

### 5.1 Quantities that must remain distinct

| Quantity | Meaning | What it must not substitute for |
|---|---|---|
| Stored energy | Remaining usable reserve | Maximum delivery current |
| Capacity | Maximum reserve a container can hold | Activation allowance |
| Maximum hue current | Safe delivery rate for a vessel/component | Total energy in a large stack |
| Hue potential | Proposed voltage-like parameter | A finalized physical equation or approved unit |
| Delivered power | Proposed rate of useful energy delivery | Skill proficiency or learned access |
| Hue conductivity | Material transfer characteristic | Capacity or automatically identical current rating |
| Condition/durability | Remaining physical serviceability | Hardness or maximum operating temperature |

Use finite cast demand profiles: an action can happen visually in an instant while drawing energy over a defined resolution interval. Proposed normalized fixtures may use P = U × I and integrated energy demand; these are useful simulation conventions, not approved final physics. Peak demand and total demand both matter. Increasing mastery or flow equipment can reduce losses or improve tolerable delivery according to explicit curves; it must not silently create energy.

### 5.2 Personal reserves and external supply

Personal hue pools and item reserves need separate state. Proposed initial source policy: use the selected hue's personal reserve first, then only explicitly selected compatible vessels; equipment can alter this routing. Keep the policy configurable because the final relationship between carried storage and character capacity remains undecided.

If an embedded vessel contributes accessible capacity, the HUD may show a combined total, but the underlying stored energy must be counted once. Removing, transferring, or destroying that vessel must transfer/remove its actual reserve. Do not create the same energy in both the item and the character record.

Gale regeneration responds to environment. Open air normally supports it; underground and underwater conditions reduce or otherwise constrain it through authored values. Do not assume Gale is always available at the outdoor rate or that Tide is universally harder to sustain. Core proximity can be an explicit skill prerequisite and later an energy source; the initial implementation must not grant unlimited energy merely because an altar is nearby.

Natural-vessel charging remains unresolved. A proposed non-production test profile can provide precharged harvests and an explicitly labeled developer refill. Keep this separate from personal passive regeneration; the current demo's SP refill does not prove reeds recharge in the backpack.

### 5.3 Item instances, stacks, and overload

Make Breeze Reed the first functional natural vessel. Introduce a clearly named test grade with better capacity/current limits for comparison; its name and recipe remain provisional. Store stable instance or homogeneous-lot identity, definition/material, quantity, contents, charge, limits, condition, ownership and location. Stack grouping must preserve heterogeneous charge/condition by splitting lots or retaining underlying instances. Trades, drops and equipment transfers must preserve that state.

A selected supply group may contain several low-grade vessels. Quantity can increase available energy, but the actor/conduit routing rule limits simultaneous delivery. Specify how current divides and which instances bear stress; never sum every inventory rating and declare all high-level casts safe. One intense attempt may destroy the entire participating stack. Unrelated stacks must remain untouched.

Resolve casts in this order:

1. Validate learned access, skill prerequisites, target, environment and activation allowance.
2. Determine demand and the explicitly selected supply path.
3. Check energy sufficiency and delivery conditions; calculate mastery/equipment contributions.
4. Apply the authored risk policy, including server-owned chance where relevant.
5. Commit expenditure, damage/destruction, progression and skill outcome consistently; publish the result.

Exceptional mastery, flow-improving equipment/skills, or a successful calculated roll can permit demanding use of weak material. These are not three mandatory simultaneous requirements. A successful roll cannot grant an unlearned hue, remove the energy bill, or multiply an item's reserve. Spell success and vessel survival are distinct outcomes. Cover success with survival, success with destruction, and failure with destruction where the selected policy permits them; do not make any one universal.

Normal starter actions should be understandable and dependable under rated conditions. The server can expose predicted risk when the player has sufficient knowledge, but a guaranteed warning or a grace period before disintegration is not established. Developer tests may force seeds/outcomes; players cannot submit their own roll result.

### 5.4 Materials and identification

Preserve the established material vocabulary: density/weight, hardness as impact/pressure tolerance, thermal conductivity, thermal capacity, hue conductivity and hue capacity. Operating limits and current ratings are separate derived/authored component properties. Avoid adding dozens of attributes before their gameplay use exists.

Use Roman numeral resource tiers, with quality and rare attributes separate from tier. Hue-infused materials can be abundant. An affinity does not automatically grant the same bonus to every object. Only specifically defined Verdant/Aura materials gain self-repair.

Identification reveals resource types/properties and supports future recognition. Proposed first scope is per-character knowledge; keep the keying policy explicit so sharing can be decided later. The UI must not reveal a hidden material's full statistics in a tooltip while claiming it remains unidentified.

## 6. Interface specification

The interface should help players answer: What can I do? What is limiting me? What will this consume? What changed? Use progressive disclosure so the starter zone is readable without opening a factory dashboard.

| Surface | Required content and interactions | First appearance |
|---|---|---|
| Main HUD | Health; relevant hue reserve and regeneration; selected action/assembly; occupied activation allowance; active effects; contextual target prompt | Character/hue pass |
| Character and Hues | Origin; level and points; each hue's access/mastery; capacity/regeneration with modifier breakdown; equipment influence | Character/hue pass |
| Skills | Learned/locked nodes; prerequisites; purchase/upgrade; skill proficiency and cap; demand and effect description | Character/hue pass |
| Inventory and Equipment | Distinguish material, consumable, vessel and component roles; inspect charge/current/capacity/condition; select supply; split/group compatible items | Vessel pass |
| Active Effects | Source, hue, remaining duration, ongoing cost, reserved allowance; cancel action; interruption reason | Sustained skills pass |
| Assemblies | Choose base action/modifiers; compatible targets; per-hue cost; allowance; warnings; save/name/edit; bind a shortcut | Combination pass |
| Crafting | Inputs, stages, required condition ranges, actual conditions, progress, output prediction, pause/failure reason | Process pass |
| Journal and Map | Identified resources, demonstrated techniques, discovered places, tasks and preparations | Exploration/content passes |
| Camp and Machinery | Claim status; deploy/pack; ports and connections; buffers; bottlenecks; process conditions; component wear | Field machinery pass |
| Workshop and Economy | Stock, orders, work assignments, production capacity, reputation, property permissions and transactions | Economy pass |

### 6.1 Interaction details

Keep X/C/V working initially. Add rebindable selection, targeting, modifier selection, confirm and cancel actions. A saved assembly can occupy a shortcut; the UI must still show its separate hue commitments. Paused menus must not silently pause a multiplayer world.

Only show detailed bars for learned/relevant hues; locked hues can remain quiet entries in the character screen. Provide numeric values on inspection rather than forcing every reserve onto the HUD. Use hue names, icons and patterns in addition to color. Support keyboard focus, readable contrast and scalable text; those are interface requirements rather than changes to game lore.

Proposed vessel tooltip order: name/tier and identification state; stored energy/capacity; safe current; condition; selected supply role; then detailed material properties. Explain concrete outcomes such as "Gust cannot start: Gale allowance occupied by Cooling" or "Two selected reeds disintegrated during overload." Keep raw packet IDs, RNG seeds and internal units in developer diagnostics.

Preview valid traversal landings and show why invalid ones fail. Do not mark every hidden altar on an unexplored map. NPC inspection may reveal an observed process and its visible conditions; merely looking must not automatically unlock its recipe or award mastery unless a separate learning rule says so.

### 6.2 UI implementation strategy

Each gameplay pass includes enough real UI to operate and understand its system. Existing windows can be adapted first; a full visual reskin follows stable information needs. All authoritative values come from server snapshots/events. Client predictions are labeled estimates and reconciled with server outcomes. Tooltips, error messages and disabled-action reasons use shared reason codes so they cannot contradict the rules.

## 7. Traversal, combat, and environmental exploration

Treat graphical layers and gameplay elevation as different concepts. The first map can have non-overlapping terraces with surface IDs and explicit stair, descent and jump transitions. Overlapping bridge/tunnel floors can come later. Client and server consume equivalent terrain/transition definitions; map export should generate server walk data and preserve a consistency check.

One movement resolver handles ordinary movement, stairs, Dash, featherfall, upward jump and forced displacement. It checks path segments, takeoff, height difference, landing occupancy, obstructions and actor capabilities. Different causes have different eligibility, but cannot disagree about whether a wall exists. The server authorizes transitions; the client animates motion and shadows without changing final authority.

Gust can push enemies onto a lower level. Gust itself does no direct damage. Proposed introductory fall behavior is nonlethal displacement followed by brief recovery; later fall damage and PvP displacement remain separate decisions. A displaced enemy must find a legal path afterward and respect elevation when attacking. Invalid voluntary landings should reject before expenditure in the first test policy; forced movement should stop at the last legal location when no legal landing exists.

Add environmental state incrementally: hue concentration, exposure conditions, terrain flags, and relevant hazards. Define how a condition accumulates, how protection changes it, and what crossing thresholds does. Demonstrate Ember heat tolerance plus Gale cooling against one heat hazard before simulating entire climates. Give Gale cooling a ceiling so adequate energy does not guarantee adequate protection. Equipment, consumables and deployables can satisfy parts of a hazard challenge alongside skills.

Environmental concealment and hostile detection should use explicit visibility/affinity/protection inputs. Camouflage can reduce detection in suitable environments; it is not blanket invulnerability. Regions become more protective and obscure their altars toward the core. Author one legible defense before adding dynamic regional reactions.

Death penalties, PvP, loot ownership, attack formulas and respawn rules are not settled. Preserve the current demo's behavior as a labeled compatibility policy, verify it, and avoid expanding it into new irreversible losses during these early passes.

## 8. Crafting as the common process system

### 8.1 From Ama's exchange to a real process

Keep Ama's existing tonic exchange as a functioning introductory service until the replacement works. The new crafting system must support inputs, apparatus, stages, condition ranges, required duration, output/yield, and recipe-specific interruption/failure policies.

Proposed first process: manipulate gathered Gale material into one mobility-related item or component. A lightened travel wrap is a test candidate, not a canonical item. Begin with one condition and one stage. A more complex material later requires temperature, pressure, supplied hues and cooling to remain within specified ranges over time.

Separate what the process requires from who supplies it. A player can channel energy; an NPC can perform that same operation; a machine can maintain the condition through connected supplies. Recipe resolution and quality rules stay common. This does not imply an NPC starts with all skills or that machinery grants its owner mastery.

A process has reserved inputs and explicit states such as prepared, running, paused, completed, failed or cancelled. Author each recipe's consumption points and cancellation policy; avoid free outputs on reconnect and duplicated refunds. A proposed introductory recipe pauses safely on interruption. Other authored recipes may consume the batch, damage equipment or harm the operator. Deviation tolerance, yield and quality must be recipe/material data, not one universal failure switch.

Use material-derived output characteristics where an implemented process supports them. An item made from identical materials under identical conditions must not receive a hidden quality penalty merely because its crafter is an NPC.

### 8.2 Components and machinery

Structures consist of required components and optional accessories. Materials, quality and affinity determine component operating limits and bonuses. Components track individual durability; exceeding operating ranges accelerates wear. Failure of a required component stops the structure; accessory failure removes its benefit and may expose another component to unsafe conditions.

Retain the defined furnace anatomy: foundation, core/shell, smelting chamber, heat element, chimney and accessory. Do not silently reuse the old two-core-component example as the final complete furnace. Its final input-port counts remain open.

A heat element may burn fuel, accept direct skill power, or use a compatible hue source. Gale airflow and Tide cooling are separately controlled contributions. Passive properties and active supplied benefits are different. Upgrading a component can create a new continuous supply requirement; the UI should show it before installation.

Repair reduces maximum durability and eventually quality under a tunable policy. Special regrowth materials do not automatically erase these penalties. Intentional overload remains a legitimate strategy when the recipe and equipment permit it.

## 9. Reusable biome and culture framework

### 9.1 Required content contract

Every biome/content package should specify the following. Existing engine data formats may be extended; this table is a contract, not an instruction to introduce a new file format for every row.

| Definition | Required decisions |
|---|---|
| Identity and culture | Dominant hue, names, visual palette, architecture/materials, daily work, welcome and return experience |
| Regions | Settlement, learning area, frontier, high-concentration area, core/altar approach; transition and hazard rules |
| Energy ecology | Regeneration contexts, local vessels, storage/current progression, resource renewal, extraction consequences |
| Exploration lesson | One characteristic obstacle, first coping skill/tool, practice situation, later use and alternative preparation |
| Combat lesson | Enemy behavior, hue interaction, terrain opportunity, evasion/defense lesson and rewards |
| Crafting lesson | Local input, condition to control, apparatus/bootstrap, output with a visible use |
| Resources | Base families, affinity variants, tiers, identification, yields, refined forms and useful properties |
| Altar | Core relationship, concealment/defenses, access journey, hue unlock, regional ability offerings, repeat-visit policy |
| NPC demonstrations | Actor capabilities, visible process, supplied inputs, output, optional information revealed |
| Progression links | What this region teaches, what another culture contributes, where better equipment becomes necessary |
| Production and trade | Cultural specialty, demand for imports, exports, skill/material requirements and village investment |
| Validation route | A short playable journey demonstrating exploration, combat and crafting, with multiplayer/save checks |

Shared cadence does not mean identical quests with different colors. The second biome must introduce a different problem and working method. Core regions can require combinations and field preparation; homelands should not require rare-hue machinery merely to begin playing.

### 9.2 Initial planning cards

The specialties below are established. Specific challenges and opening lessons marked as proposals are candidates for playtesting, not approved new canon. These five cards do not establish the final character-creation roster.

| Hue | Established identity/application | Proposed exploration/combat lesson | Proposed first process and later role |
|---|---|---|---|
| Gale | Wind, movement, lightweight materials; grassland starter selected | Terraced descent/ascent; Gust creates distance and ledge opportunities | Controlled airflow/lightening of a fabric component; later ventilation, cooling support and airflow machinery |
| Ember | Heat, refining and power systems | Heat-exposure route; distinguish generating heat from tolerating/redirecting it | Maintain a small refining temperature window; later heat elements and demanding thermal processes |
| Tide | Water use/navigation, precision-cut metal and cooling | Navigate a water-related obstacle using an authored water-control ability; combat teaches placement/control | Hold a cooling condition, later precision cutting and stable process cooling |
| Terra | Stone/crystal extraction, stone shaping, raw materials | A stone/terrain obstacle; combat teaches positioning against a resource-bearing enemy | Shape a useful part from stone; later foundations, housings and crystal supply |
| Verdant | Wood/fiber/hide harvesting, framing; selected materials may regrow | Dense vegetation and concealment; combat teaches using living surroundings | Prepare a fiber/frame component; later framing and specifically authored regrowth materials |

Recommended second playable region: a small Ember frontier, because it validates the already-defined Gale/Ember combat and heat-protection examples. A Tide process fixture can validate cooling without requiring a complete Tide homeland at the same time. Choosing Ember second is a proposal, not a change to Gale as the first homeland.

Decay, Aura and Void need advanced-content cards rather than an invented starter kit. Aura crafting of Terra crystals into universal hue vessels is established. Decay's exact process effects remain undefined. Void emergence after prolonged depletion is established, while restoration methods and thresholds remain open. Their high-level crafting effects can be powerful and chaotic without assigning arbitrary universal bonuses to all their materials.

### 9.3 Altar and knowledge progression

Implement altar offerings as data separate from hue unlock. On the first valid visit, grant hue access according to the selected interaction policy; on later visits, resolve regional skills/abilities without duplicating grants. Recipe unlocks are optional authored offerings because their inclusion remains conditional.

The journey should reveal a defended place through exploration rather than simply following an automatic waypoint. Proposed first test has a discoverable route with one increasing hazard and a preparation solution; it need not procedurally hide a moving altar. Learning a hue does not confer all its regional skills, recipes or mastery.

## 10. Camps, automation, and the economy

### 10.1 Temporary camps

Camps are rest/preparation points that can be assembled and packed. A timed claim protects their defined ownership state; on expiry they become abandoned and passing players/NPCs may take equipment. Active-claim permissions, timer basis and renewal remain undecided.

Proposed test policy uses a server world clock that advances while the host is running and pauses during shutdown. Both expiry and machinery operation use that documented clock. This avoids silently introducing offline losses or production; it is not the final offline policy. Show remaining claim time and abandonment clearly. Test expiry with an accelerated developer clock, not real waiting.

Deployment needs an area/occupancy rule, placement validation, ownership, item-to-world transfer and packing back into inventory. Packing preserves charge, component identity and wear. Claim expiry changes access; it does not create duplicate items or immediately teleport equipment to another actor.

### 10.2 Machinery networks

Represent harvesters, buffers, conduits and consuming processes separately. Give ports compatible hue requirements, limits, direction where relevant and connection state. Solve supply and demand with bounded server work; begin with small networks and a fixed simulation step. Do not apply transport twice because a cycle exists or create energy from two sources both claiming the same reserve.

Aura crystal vessels accept any hue, but universal compatibility does not establish mixing or conversion. Proposed first storage policy holds one hue per compartment and requires it to be empty before switching. A multi-hue workflow can use separate supplies feeding different process inputs. More permissive mixing is later design work.

Introduce one field workflow: a source, an Aura buffer, a conduit and a consumer that sustains a useful camp condition or process. For bootstrap, propose access to a village-made buffer or rental station before players can manufacture Aura vessels themselves. Trade can supply a component without granting the buyer Aura mastery; using purchased advanced components still needs an explicit equipment policy. Do not require a rare-hue factory to build the first tool needed to reach that factory.

Advanced networks add multiple process stages, component upgrades, shortages and skilled operator requirements. NPC staffing is attached to specific tasks with capability requirements. Ownership alone cannot satisfy every mastery requirement, and one employee cannot operate unlimited concurrent stations without an explicit scheduling rule.

### 10.3 NPC economic participation

Begin with a few authored NPC roles that use the same item, skill and process rules as players. A scheduled crafter is enough for early demonstrations; full autonomous planning is a later layer. Hybrid NPCs should remain rarer and demonstrate combinations that suggest new approaches.

Proposed economy foundation: finite stock, tracked recipe inputs, explicit currency sources/sinks, production tasks and bounded orders. These are implementation recommendations; the historical design had not settled inventory conservation, budgets or prices. Distinguish economic actors from intentionally subsidized tutorial services. Any replenishment/subsidy should be explicit in world data and visible in diagnostics.

Start with one producer, one supplier, one customer and a player-owned workshop. Let stock shortages affect production and demand. Use a simple authored pricing policy before adding speculation or complex market clearing. Show players what is scarce and what their production changes.

Reputation, requests, trade and infrastructure donations connect players to villages. Supporting a faction can affect rivals. Village upgrades change actual production capacity and available goods, not only a reputation number. Land/workshop/shop ownership and government need separate permissions and transfer records; taxation, office selection and NPC officeholding are unresolved, so expose extension points without inventing a complete political simulation.

### 10.4 World consequences and high-level play

Track regional resource/hue depletion and recovery. Extraction can reduce affinity and eventually create dangerous Void conditions; storms can alter resources, danger and opportunities. Exact rates and thresholds must be authored and tested in a small region first.

World manipulation should reuse existing supply, condition, process and regional-state rules. Core-assisted skills need explicit access and energy policies. Advanced Decay/Aura/Void recipes need individually defined effects and failure behavior. Do not satisfy "endgame" by multiplying every numerical stat or adding a separate unrelated combat mode.

## 11. Technical integration contract

These are proposed responsibilities, not claims about classes already present in the merged repository.

| Responsibility | Shared data/rules | Server authority | Client responsibility |
|---|---|---|---|
| Character progression | Definitions, prerequisites, award policies | Grants, purchases, mastery/proficiency, saves | Presentation, requests and explanations |
| Actions | Demand/effect definitions and reason codes | Eligibility, reservation, RNG, outcome | Targeting, previews, animation and feedback |
| Items/materials | Material definitions, component derivation | Instance/lot state, ownership, transfers, destruction | Inventory grouping, supply selection and inspection |
| Traversal | Terrain and transition definitions | Legal movement, occupancy, displacement | Input, preview and interpolation |
| Processes | Recipes, conditions, failure/yield policy | Time, consumption, output, damage | Condition display and control intentions |
| Networks | Ports, connections, limits and supply policies | Flow allocation, conservation, wear | Placement, wiring and bottleneck feedback |
| World/economy | Region, actor, job and ownership definitions | Production, expiry, transactions, events | Discovery, orders, claims and reports |

Keep static definitions separate from runtime instances. Stable IDs connect content to saves; display names can change without breaking inventory or learned skills. Use content/schema versions and validate missing references, cyclic prerequisites, impossible starter recipes and unsupported effect combinations at load time.

Inspect the current merge's actual hue handlers and hosting code before assigning file paths. Package symbols show `LocalPlayer::useHueSkill` and server `hue_use_skill`/`hue_gale_max_energy`, but this is not a source audit. The current implementation may already solve parts of the needed contract.

New state requires deliberate protocol versioning and save migration. Negotiate capability/version, reject incompatible builds clearly, and keep source revision/content version with the packaged release. Do not hide hue state in unrelated legacy attributes or packet bytes.

For every pass: validate intent on the server; bound work per request; commit state changes consistently; make repeated commands safe; send authoritative deltas plus reconnect snapshots. Preserve item identity through drop/trade/equip/process/pack operations. Use exact transaction semantics or a documented journal appropriate to the existing storage backend; do not claim flat-file writes are atomic across several files merely because each file is renamed atomically.

Back up representative worlds before migration, migrate a copy, and demonstrate the old account/character/inventory still loads. Keep a known working release as rollback; do not promise downgrading new-format saves unless a reverse migration exists. Transient active skills can stop on disconnect under a documented policy; ongoing machinery/jobs use the declared world-time policy. Never award repeated progress or duplicate output during reconnect recovery.

Developer tools should expose actor state, active reservations, selected supply, demand, resolved modifiers, rolls, transitions, process conditions and persistence events. Provide deterministic fixtures and map/world resets independent of ordinary player commands. Do not grant these controls to normal clients.

## 12. Sweeping implementation passes

Each pass is a broad product change delivered through smaller reviewable commits. Include rules, persistence, content, UI, packaging and evidence in the pass. Keep the previous loop playable throughout. Do not implement all nine passes in one unreviewable rewrite.

| Pass | Playable result | Primary dependency |
|---|---|---|
| 0 — Preserve and map the working build | Reproducible current demo with source/release provenance | Actual merged repository |
| 1 — Character, skills and hue supply | Gust uses real character/vessel state and explains its limits | Pass 0 |
| 2 — Gale traversal and homeland loop | Featherfall, jump and ledge Gust make the landscape useful | Pass 1 |
| 3 — Concurrency and assemblies | Improvised and saved combinations obey separate hue budgets | Pass 1; Pass 2 supplies playable terrain |
| 4 — Materials and process crafting | Player and NPC make useful goods through the same process rules | Passes 1 and 3 |
| 5 — Second culture and altar expedition | A distinct region teaches another hue through an actual journey | Passes 2–4 |
| 6 — Camps and connected machinery | A temporary field site sustains a useful process | Passes 4–5 |
| 7 — Workshops and NPC economy | Several economic actors exchange goods produced from real inputs | Pass 6 |
| 8 — Regional consequences and advanced content | Extraction and production change the world meaningfully | Passes 5–7 |

### Pass 0 — Preserve and map the working build

**Work:** Identify the exact merged source revision, build/package commands, dependencies, hosting path, save locations and current skill implementation. Record which old statistics feed combat, regeneration, weight, skills and persistence. Preserve source/asset provenance and the known working Windows release. Recover existing test tools before inventing a replacement harness.

**Playable gate:** Build the current source, host a fresh world, connect two clients, use Dash/Gust/Wind Scythe, harvest, complete Ama's exchange, consume the tonic, reconnect and restart the host. Compare behavior with the user-confirmed release. Verify both clients see the same displacement/resource outcomes. Save a representative test world for later migrations.

**Deliver:** A short baseline report and feature/dependency map. If the source cannot reproduce the package, identify the exact mismatch before feature work. This pass is bounded validation; do not repeat upstream restoration work that the current merge has already completed.

### Pass 1 — Character, skills and hue supply

**Work:** Introduce versioned character/hue/skill records and definition IDs; keep character level/points, hue mastery and proficiency separate. Migrate the current Gale reserve into the new authoritative state. Preserve existing controls. Route Gust through a common action resolver, then adapt Dash and Wind Scythe without changing their intended behavior. Implement Breeze Reed and one better test vessel, supply selection, current/capacity/condition accounting, and configurable risk. Add the character, skill and item views plus HUD/reason feedback.

**Content:** Provide novice and advanced developer profiles, adequately rated starter supplies, and controlled overload fixtures. Starting access and skills are explicit grants. Use neutral origin modifiers and a versioned balance file for provisional curves.

**Playable gate:** A tester can inspect Gale mastery, use Gust, see correct energy consumption, and understand why a demanding attempt is constrained. The same action produces different legitimate outcomes with better vessels, mastery or flow modifiers. Buying an eligible upgrade changes its defined effect; meaningful use advances proficiency under the selected policy. Selecting no external vessel does not delete inventory reserves. Two clients agree on effects, and charge survives drop/pickup/equip/reconnect. A migrated demo character retains inventory and usable introductory actions.

**Focused checks:** Separate unlock/energy/current/activation failures; no unlimited throughput from stack count; selected-stack destruction exactly once; deterministic success/failure fixtures; no client-supplied mastery or roll result. Migration and conservation are required gates.

### Pass 2 — Gale traversal and the homeland loop

**Work:** Add authored elevation regions and legal transitions; implement featherfall and upward jump; extend Gust to ledges using the shared resolver. Update pathfinding, enemy pursuit/attack eligibility and animation replication. Add landing previews and readable failure messages. Preserve the current world size or expand only as needed.

**Content:** Build a cozy arrival and short practice route, a terrain encounter, a resource destination and a recognizable return route. Ama remains an anchor; other residents/ambient activity can make the settlement feel inhabited without introducing an economy simulation yet. A stair route can prevent an introductory character being stranded without charge. This is a starter-map proposal, not a universal requirement for every future shortcut.

**Playable gate:** Walk stairs, descend without stairs, jump up, and push a Hopper down. Validate walls, diagonal corners, occupied landings and mid-transition disconnects. The Hopper cannot attack through the cliff or ignore elevation when returning. A new tester can understand the route from in-world instruction and normal UI. Terrain art upgrades may accompany this pass but do not substitute for movement correctness.

### Pass 3 — Concurrency and assemblies

**Work:** Add action lifecycles, ongoing drains, activation reservations, maintained effects, cancellation and explicit combination rules. Build the live modifier selector and saved assembly editor. Add a developer-only second-hue grant to exercise multi-hue behavior before the altar expedition exists; keep that grant out of normal progression.

**Content:** Implement Gust + Spark and Ember heat tolerance + Gale cooling as the first fixtures. Add one exposure zone and, if needed, a heat-redirection variant to demonstrate cooling limits. Keep the finished game focused on manipulating actions/items/conditions; a shortcut is an execution convenience, not a new hybrid skill tree for every pair.

**Playable gate:** The same combination works when assembled live or loaded from a saved definition. Both hues pay their own costs. A novice cannot bypass concurrency by saving several skills as one assembly. Cancellation releases allowance without refunding already-spent energy. Removing a supply or entering a low-regeneration area has the defined effect. Reconnect cannot preserve free effects or duplicate costs.

### Pass 4 — Materials and process crafting

**Work:** Introduce material definitions/properties, identification, useful item results and staged process state. Implement input reservation, energy/condition supply, pause/failure policies, quality/yield and operator capability. Build the condition/progress UI and NPC observation view. Keep the old tonic service available while the new process is integrated.

**Content:** One Gale material-manipulation process, one upgraded vessel/conduit recipe or demonstrator, and one more demanding temperature/cooling fixture. For the latter, developer profiles or a supplied village station avoid pretending the second culture is already released. Ama or another crafter must use the shared recipe and actual supplied inputs for the new demonstration.

**Playable gate:** Gather, identify, inspect, process and equip/use one output that changes a recognizable action or route. A player and NPC with equivalent inputs/capabilities can achieve equivalent results. A missing condition pauses the starter recipe; a separate authored hazardous fixture demonstrates failure/damage. Reconnect during crafting cannot create output twice or return consumed inputs. Displayed quality predictions match the implemented formula.

### Pass 5 — Second culture and altar expedition

**Work:** Implement the biome contract, regional concentration/hazards, discoverable altar state, hue unlocks and regional offerings. Extend journal/inspection and travel preparation. Use content data to instantiate skills, resources and recipes without forking the character/action systems for the new hue.

**Content:** Recommended first expansion is an Ember frontier and small cultural settlement. Provide an authored preparation route using existing Gale knowledge, equipment and consumables; it must be possible to reach the first Ember altar without already possessing an Ember skill that only that altar grants. After learning Ember, the return route can demonstrate the new combination. Keep this dependency visible in the content graph.

**Playable gate:** A Gale character reaches the altar through a legitimate preparation route, unlocks Ember, learns an authored offering and uses it back in Gale territory. A second same-hue altar can teach a different offering without duplicating hue access. Origin modifiers are visible and do not silently lock the player out. New resources improve an existing vessel/component/process in a way the UI can explain.

**Deliver:** A completed second-biome planning card and a reusable authoring checklist. A palette swap alone does not pass.

### Pass 6 — Camps and connected machinery

**Work:** Implement deployment/packing, timed claims, abandonment, ownership transfer and persistent component instances. Add the source/buffer/conduit/consumer network, port validation, bounded flow updates and wear. Connect a machine to the same process conditions used by manual crafting. Add camp status, placement, connection and machine-inspection UI.

**Content:** One field camp with one useful environmental or crafting service, one Aura buffer obtained through an explicit bootstrap route, and one upgrade that resolves a real bottleneck. Introduce a limited skilled NPC operator only if the demonstration genuinely needs a staffed stage.

**Playable gate:** The camp helps an expedition, can be packed without duplicating or resetting components, and persists through a normal host restart. Under the chosen world-clock policy, expiry marks it abandoned and allows another player/NPC to take equipment once. Disconnecting a supply changes the process; overloading the weakest component has an observable consequence. A novice owner cannot evade a required operator skill by attaching a machine. Two players cannot acquire the same abandoned component.

**Scope:** One small functioning network before a sprawling factory. Advanced multi-hue pipelines and more component categories extend the same model afterward.

### Pass 7 — Workshops and NPC economy

**Work:** Introduce property/workshop permissions, stock, jobs/orders, explicit money accounting, operator assignments and simple demand/pricing. Build commerce/production views. Add village reputation and one infrastructure investment with a real production effect. Define how scheduled NPC work uses shared skills, items and processes under a bounded simulation budget.

**Content:** A small closed demonstration with a supplier, producer, customer and player workshop. Give NPCs differentiated mastery/material access so some outputs compete with or exceed the player's. One rare hybrid practitioner demonstrates an advanced workflow. A basic shop or workshop can be acquired by a clearly labeled test mechanism until the permanent acquisition rule is designed.

**Playable gate:** A shortage stops relevant production; supplying inputs restarts it; a sale moves stock and currency exactly once; labor assignment respects capability/time; infrastructure changes actual output options. Workshop ownership survives restart. All subsidies and stock replenishment are explicit. Do not claim a complete self-sustaining economy from a scripted shop with infinite inventory.

**Deferred:** Elaborate government, political simulation, freight and offline catch-up. Preserve extension points and decide their policies when a concrete scenario requires them.

### Pass 8 — Regional consequences and advanced content

**Work:** Add bounded regional depletion/recovery, storms/events, affinity changes and authored Void emergence. Connect infrastructure and extraction rates to these states. Add selected high-level processes and core-assisted abilities using existing access, supply and process rules.

**Content:** One small region where sustained extraction changes resources and danger, one event that creates an opportunity, and one advanced material/process whose outcome matters to machinery or exploration. Define a recovery policy for the test region without presenting it as an already-established universal restoration mechanic.

**Playable gate:** A known extraction history produces a reproducible regional change, persists through restart and is legible to players. Server load remains bounded as actors and machines increase. New high-level effects have authored costs, access conditions and failure behavior. There is a worthwhile reason to return to the homeland with new knowledge and goods.

## 13. Unresolved choices and reversible working policies

The agent may implement the proposed policies below as named test configuration, recording them in release notes and a decision ledger. Do not ask the user to settle every number before coding. Escalate a choice when it changes established progression, causes lasting player losses, or requires an irreversible save/content commitment that cannot be isolated.

| Choice | Proposed working policy | Revisit when |
|---|---|---|
| Character XP versus mastery/proficiency awards | Separate events/curves; meaningful resolved activities award the appropriate tracks | First sustained playtest exposes incentives |
| Origin bonuses and race roster | Neutral modifiers; retain an origin field; no invented race selection | Second culture has evidence for a meaningful difference |
| Activation scope | Per-hue budgets with a configurable global ceiling; tier costs in data | Multi-hue concurrency is playable |
| Natural-vessel recharge | Precharged test items plus developer refill; no hidden backpack recharge | Harvest-to-consumption pacing is assessed |
| Personal versus vessel routing | Personal first, then explicitly selected vessels; separate underlying reserves | Equipment and supply choices need finer control |
| Current sharing and risk | Named, bounded routing policy; deterministic safe fixtures and seeded risky fixtures | Mastery, materials and costs can be compared in play |
| Fall consequences | Nonlethal introductory drops; preserve space for authored fall rules | Traversal and knockback are reliable |
| Resource identification scope | Per-character knowledge | Shared discovery/trade requires a different scope |
| Observation grants | Record optional notes; do not automatically award skills/recipes | Formal teaching or apprenticeship is designed |
| Aura storage mixing | One hue per compartment; empty before switching | An actual mixed-hue process needs different behavior |
| Camp and machine offline time | World time advances while the host runs, pauses during shutdown | Long-lived hosted worlds require an offline policy |
| Machinery bootstrap | Village access/trade for advanced buffers; manually operated early processes | Endgame acquisition and labor economy are balanced |
| NPC stock, money and pricing | Finite tracked stock, explicit subsidies/currency flows, simple authored prices | The small economy demonstrates shortages and exchange |
| Death, PvP and inherited combat | Preserve and document current demo behavior; no new irreversible losses | A dedicated combat/death design pass is justified |

No numeric profile is final. The agent may choose a small set of consistent costs/capacities/rates to make each gate testable, store them in versioned data, and report the rationale. Do not scatter tuning literals through gameplay code or present test values as recovered user requirements.

## 14. Completion, testing and agent reporting

Before each pass, state what existing behavior it changes, which saves/content it touches, and its playable gate. Afterward, provide the build artifact or reproducible build instructions, source revision, migration notes, screenshots or a short capture where useful, and an exact distinction between automated checks, manual tests and unverified claims.

Minimum recurring checks are the proven host/join/action/gather/tonic loop and representative save migration. Expand testing for the concrete risks introduced by the pass: conservation and serialization for vessels; legality and replication for movement; reservation/cancellation for concurrency; consumption/output consistency for crafting; conservation and bounded work for networks; ownership/transaction consistency for economy. A screenshot is not proof of persistence or server authority.

Test with a real second client where replication matters. If the agent cannot run Windows, it must report that limitation and validate through the supported build/test environment without claiming a Windows playtest. User confirmation of the current binary is baseline evidence, not proof that subsequent revisions work.

Keep an implementation-status file in the source repository with these categories: implemented and tested; implemented but unverified; provisional tuning; missing; blocked. Keep a short decision ledger with date, evidence/status, chosen policy and replacement trigger. Broad passes should leave small, understandable changes in version control and a runnable release at their end.

**Immediate execution scope:** Pass 0, then Pass 1. Continue through later passes when those passes are the active coding assignment. This full roadmap does not instruct an agent to implement an economy and every biome in the first change.

## 15. Companion material

- [Aethyra-Recovered-Mechanics-v0.1.md](Aethyra-Recovered-Mechanics-v0.1.md): established rules, historical context, source register and corrections.
- [Aethyra-Gale-Starter-Zone-Build-Spec-v0.1.md](Aethyra-Gale-Starter-Zone-Build-Spec-v0.1.md): earlier technical slice; its pre-demo build status is historical.
- [Aethyra-Coding-Agent-Handoff-v0.2.md](Aethyra-Coding-Agent-Handoff-v0.2.md): concise execution instructions to accompany this framework.

This document plans implementation. It does not claim that the new progression, vessel, traversal, crafting, machinery or economy systems have been coded or verified.
