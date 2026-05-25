# AGENT.md

## Skill System Rules

- Skills and attributes belong to `WorldActor`, not humanoid-only classes.
- Do not add exported per-skill variables like `sleight_of_hand` to actor scripts.
- Use stable dotted string IDs from `SkillRules` and `resources/skills`.
- Add new skill metadata as `SkillDefinition` resources and update `architecture/world-actor-skills.md`.
- Keep the XP curve centralized in `SkillRules`; gameplay systems should award XP, not calculate level thresholds.
- Treat awarded XP as training pressure from meaningful action. Do not add per-skill low-level XP multipliers to compensate for the global curve.
- Weight training by challenge or risk when relevant, and compress/cap many simultaneous trivial sources to prevent farming exploits.
- For stealth-style risk, prefer one strongest valid contested observer/source per actor per tick. Do not sum crowds of equivalent weak sources into power-leveling XP.
- Levels are uncapped and display as whole numbers.
- UI should show progress as current XP toward next level over XP needed for next level.
- Combine skills and attributes with diminishing returns in gameplay checks.
- Prefer deterministic checks; add small randomness only for risky contested actions such as stealing, lockpicking, and speech.
