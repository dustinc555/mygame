# World Actor Skills

This document is the contract for attributes and skills on world actors. Update it whenever skill ownership, IDs, progression, UI, or training hooks change.

## Ownership

- Every `WorldActor` owns an `ActorSkillSet`.
- Humanoids, animals, monsters, pack beasts, robots, and future actors all use the same skill API.
- Gameplay systems must not add one-off exported skill variables to `HumanoidCharacter` or subclasses.
- Use `actor.get_skill_level(skill_id)`, `actor.add_skill_xp(skill_id, amount, reason)`, and related APIs.
- Skills are runtime state. Skill definitions are reusable data resources.

## IDs

Skill IDs are stable string IDs. Do not rename IDs once they can appear in saves, spawned actors, jobs, AI templates, or tests.

Use lowercase dotted IDs:

- `attribute.strength`
- `attribute.perception`
- `combat.swords_one_handed`
- `subterfuge.sleight_of_hand`

Do not use enums for the full skill list. The game is expected to grow a large skill taxonomy.

## Attributes Versus Skills

Attributes and skills share the same storage and progression system.

Attributes are broad physical/social/mental capabilities:

- `attribute.strength`
- `attribute.perception`
- `attribute.dexterity`
- `attribute.toughness`
- `attribute.endurance`
- `attribute.charisma`

Skills are narrower learned proficiencies, such as mining, sword use, sneaking, medical work, and lockpicking.

Gameplay checks should usually combine one primary skill with zero or more attributes through diminishing-return formulas. Avoid raw linear scaling that makes high levels break the game.

## Progression

- Skill levels are whole numbers in UI and gameplay checks.
- Skill XP tracks progress toward the next whole level.
- Levels are uncapped.
- Level `1` is the generic default for new actors.
- `1-10` is untrained and improves quickly through real use.
- `10-20` is improving and starts taking noticeably longer.
- `30-50` is competent/specialist territory and should take sustained play.
- `80+` is legendary.
- `90+` is extreme.
- `100+` is god-tier and should take absurdly long.

The XP curve must stay centralized in `SkillRules`. Do not hardcode per-level XP formulas in gameplay systems.

Use a smooth uncapped curve, not threshold buckets. Early levels should be fast, intermediate levels should demand repeated practice, and mastery should slow sharply without adding sudden cliffs at milestone levels.

Progression intent:

- `1-10`: fast enough that the player sees early progress from normal risky/actionful use.
- `10-20`: still practical, but no longer throwaway levels.
- `30-50`: major investment. Strength around 40 should take multiple real play days when trained normally.
- `80+`: effectively long-term mastery.
- `100+`: possible but not practical for ordinary play.

## Training Hooks

Actions may train a main skill and one or more attributes. Weight the primary skill heavily.

Gameplay systems should award training pressure for meaningful action. Let `SkillRules` decide how much that pressure advances the next level. Do not add skill-specific low-level XP multipliers to compensate for progression pacing.

Training should be challenge- or risk-weighted without becoming all-or-nothing gated. Easy repetition can still teach beginners, but it should fade for skilled actors; harder targets, observers, materials, or opponents should matter more at higher levels. Crowd or idle-farming sources must be capped or compressed so many trivial sources cannot explode XP.

Examples:

- Mining trains mostly `labor.mining`, with a small amount of `attribute.strength`.
- Mining XP is awarded continuously while actively mining, not only when ore enters inventory. Tune mining around ore-duration worth of effort, so faster or slower mining nodes can still produce sensible progression.
- Running trains mostly `movement.running`, with a small amount of `attribute.endurance`.
- Taking real damage trains `attribute.toughness` based on damage taken.
- Bandaging/healing trains `knowledge.medicine`.
- Stealing near NPCs trains `subterfuge.sleight_of_hand`; detecting it trains observer `attribute.perception`.
- Sneaking should train `subterfuge.sneaking` when there is actual risk, not by crouching alone in a field. Sneak training should use the strongest valid observer the actor is currently hiding from, not summed crowd XP; being clearly seen is failure, not sneak training. Moving repeatedly through an observer's cone with clear line of sight should accumulate sustained exposure over time, so high sneak can cross a watched area briefly but cannot pace in front of an elite watcher forever.
- Guard duty can train `attribute.perception`, but must be throttled to avoid free farming.

## Checks

Most checks should be deterministic. Add small randomness only where uncertainty is part of the fantasy, such as speech, lockpicking, stealing, and other contested risky actions.

Examples:

- Theft noise: thief `subterfuge.sleight_of_hand` plus diminishing `attribute.dexterity` versus item difficulty, observer proximity, and observer `attribute.perception`.
- Sneak visibility: observer `attribute.perception` plus lighting/line-of-sight/distance and sustained moving exposure versus sneaker `subterfuge.sneaking` and cover/darkness.
- Speech checks: `attribute.charisma` and relevant social context, with limited randomness.
- Combat initiative: ready melee attackers use dexterity-weighted randomness plus fairness credit so high dex attacks more often, while low dex fighters are not starved forever.

## HUD/UI

- The party panel remains a required HUD element.
- The full skill list belongs in a dedicated skills window, not inside the compact status panel.
- The `Skills` button is only available for selected player party members.
- Inspected NPCs may show compact core attributes in the details panel later, but should not expose the full skills window in Phase 1.
- Skills window rows show whole level and XP progress as `current_xp / next_level_xp`.

## Phase 1 Catalog

Attributes:

- `attribute.strength` - Carrying, blunt damage, heavy labor.
- `attribute.perception` - Detecting sneaking, theft, ambushes, and guard awareness.
- `attribute.dexterity` - Combat initiative, dodge, sleight of hand, lockpicking, daggers/finesse weapons.
- `attribute.toughness` - Death resistance, natural damage dampening, reduced bleeding.
- `attribute.endurance` - Stamina pool, stamina recovery, running capacity, hunger efficiency.
- `attribute.charisma` - Speech checks and social negotiation.

Combat:

- `combat.swords_one_handed`
- `combat.axes_one_handed`
- `combat.daggers`
- `combat.unarmed`

Movement:

- `movement.running`

Labor and gathering:

- `labor.mining`
- `labor.farming`
- `labor.fishing`
- `labor.construction`

Crafting:

- `craft.blacksmithing`
- `craft.weaving`
- `craft.leatherworking`

Subterfuge:

- `subterfuge.sneaking`
- `subterfuge.sleight_of_hand`
- `subterfuge.lockpicking`

Other:

- `knowledge.medicine` displayed as `Medical`.
- `tech.robotics`
- `knowledge.archeology`

## Future Weapon Metadata

Weapon definitions should eventually expose tags such as:

- `finesse` - benefits more from dexterity and relevant finesse skills.
- `heavy` - benefits more from strength and heavy-weapon handling.

Do not bake these traits into skill IDs. Keep them as reusable item/weapon metadata so one item can interact with multiple formulas.
