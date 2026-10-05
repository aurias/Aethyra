# Aethyra — Coding-Agent Handoff

5 October 2026 · Use with Aethyra-Gameplay-and-Implementation-Framework-v0.2.md

## Mission

Evolve the existing working Aethyra/TMWA game into the hue-based exploration, crafting and production game defined in the companion framework. Work in broad implementation passes that include server rules, persistence, client UI, content and a playable acceptance gate. Keep each pass reviewable and the existing game runnable.

The user has confirmed that the Windows demo runs and its Dash, Gust and Wind Scythe actions work. The package also includes a Gale map, harvestables, enemies, items, hosting documentation and Ama's tonic exchange. Do not begin by restoring an unrelated old upstream revision. Use the current merged repository that produced this build. The supplied ZIP has no C++ source; if the matching checkout is absent, identify that concrete dependency instead of claiming to edit the binary into a maintained codebase.

Read applicable repository instructions. Inspect the exact current head, existing hue handlers, hosting integration, build/test commands, save formats and character-stat dependencies before editing. Preserve unrelated work, provenance and a known working release. Record the baseline revision. Do not rewrite the engine or introduce a new framework merely to match suggested module names.

## Design constraints

- Separate character level/skill points, hue mastery and individual skill proficiency. Recovered mastery range is 0–50; one skill point per character level is recorded, while award curves remain tunable.
- Model per-hue access, reserve, capacity, regeneration and mastery. Origin modifiers and activation policies must be explicit data. Storage does not automatically grant more simultaneous skills.
- Distinguish knowing an action, having energy, delivering it safely and having free activation allowance.
- Give vessels stable state: energy, capacity, maximum current, condition and ownership. Stack quantity must not grant unlimited safe current. Overload can destroy a whole participating low-level stack; exceptional mastery, flow modifiers or calculated chance can affect the outcome.
- The server owns eligibility, expenditure, RNG, progression, item loss and effects. Do not reuse unrelated legacy fields as hidden hue state.
- Preserve Gust's lack of direct damage. Add approved ledge displacement later, with fall consequences separately configurable.
- Support live combinations and saved assemblies through the same action rules. A saved combination cannot bypass costs, hue access or activation limits.
- Player actions, NPC work and machinery must ultimately feed the same process/condition rules. NPC goods are not inherently inferior. Observation does not automatically grant a skill or recipe.
- Every homeland teaches exploration, combat and crafting through distinct cultural content. Gale remains the initial region. Decay/Aura/Void crafting is advanced; do not invent starter kits for them.
- Camps are temporary, with expiring claims and salvage after abandonment. Machinery is usable in camps before permanent land ownership. Advanced automation requires an explicit Aura-buffer bootstrap route.
- Treat proposed test defaults as versioned configuration, not established lore. Preserve remaining open choices in the decision ledger.

## Active assignment: Pass 0, then Pass 1

**Pass 0:** Reproduce the current build from the merged source. Verify local hosting, two clients, all three existing actions, harvesting, Ama's exchange, item use, reconnect and host restart. Locate dependency paths for legacy stats, HP/SP, progression, inventory and skill resolution. Record actual outcomes and environment limitations. Do not call undocumented or unexecuted behavior verified.

**Pass 1:** Implement the character/hue/skill records, configurable definition/award policies, save migration and protocol changes needed for authoritative hue actions. Make Breeze Reed a functional vessel and add one clearly provisional better-grade comparison fixture. Route Gust through the common action/supply resolver, then integrate Dash and Wind Scythe without regressing their behavior. Include skill learning/upgrades, proficiency state, relevant activation checks, character/hue inspection, vessel/supply UI and clear outcome feedback.

Prove safe reusable use, insufficient energy, current-limited use despite ample total reserve, controlled risky success/failure, selected-stack destruction, mastery/flow advantages and preserved state on transfer/reconnect. Use deterministic developer fixtures for chance-dependent outcomes. Do not expose control of RNG or authoritative stats to normal clients.

Back up and migrate a copy of an existing demo world. Preserve accounts, inventory and useful introductory actions. Verify that energy is not duplicated between a personal pool and an embedded/carried vessel, requests cannot duplicate outcomes, and no unrelated stack is destroyed. Preserve a rollback build; do not assume new saves can be opened by the old binary.

## Later passes

Follow the companion framework's detailed scopes and gates:

1. Gale elevation traversal, featherfall, upward jump, ledge Gust and homeland route.
2. Sustained actions, activation reservations, live modifiers and saved assemblies; Gust + Spark and heat protection fixtures.
3. Material identification, shared condition-based crafting and NPC process demonstrations.
4. A distinct second culture and protected altar journey with legitimate prerequisites.
5. Deployable camps, claims, component wear and one connected machinery workflow.
6. Workshops, finite-stock NPC production, trade, labor and infrastructure investment.
7. Regional depletion/events and selected advanced processes.

These are roadmap stages, not authorization to collapse every system into the first revision. Finish the active pass's playable gate before broadening scope.

## Deliverables for each pass

Provide the source revision and changes, runnable package or build/launch instructions, migration behavior, testing evidence, remaining limitations and a brief list of provisional design/tuning choices. Update an implementation-status file and decision ledger in the repository. Use clear categories: tested, unverified, provisional, missing and blocked.

Make reasonable reversible choices when the framework provides a policy. Ask only when missing source/access or a material unresolved design commitment genuinely blocks the assigned work. Do not turn open numeric balancing into another planning-only session.

Companion: [Aethyra-Gameplay-and-Implementation-Framework-v0.2.md](Aethyra-Gameplay-and-Implementation-Framework-v0.2.md).
