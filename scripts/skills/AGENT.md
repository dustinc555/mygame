# AGENT.md

## Skill System Rules

- Skills and attributes belong to `WorldActor`, not humanoid-only classes.
- Do not add exported per-skill variables like `sleight_of_hand` to actor scripts.
- Use stable dotted string IDs from `SkillRules` and `resources/skills`.
- Add new skill metadata as `SkillDefinition` resources and update `architecture/world-actor-skills.md`.
- Keep the XP curve centralized in `SkillRules`; gameplay systems should award XP, not calculate level thresholds.
- Levels are uncapped and display as whole numbers.
- UI should show progress as current XP toward next level over XP needed for next level.
- Combine skills and attributes with diminishing returns in gameplay checks.
- Prefer deterministic checks; add small randomness only for risky contested actions such as stealing, lockpicking, and speech.
