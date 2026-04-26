# AGENT.md

- Scenes in `scenes/test_levels/` are demo/test levels, not system owners.
- Do not put feature-specific or one-off gameplay logic in these scenes.
- If a feature only works because of code hardcoded for a test level, stop and move that logic into a reusable system.
- Test levels should showcase systems, wire shared components together, and place content.
- Prefer reusability, scalability, and clear project architecture over quick scene-specific hacks.
