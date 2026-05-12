# AGENT.md

## Character Race Resources
- Race resources define broad playable/NPC species data such as race id, display name, equipment slot list, slot labels, and default body archetypes.
- Do not put item-specific clothing fit data on races. Clothing fit belongs in `EquipmentVisualDefinition` entries or future body fit-family resources.
- A race may be male-only, female-only, or support multiple body archetypes. Only assign default archetypes that actually exist.
- Equipment slots are race-level capability data. Keep slot ids stable and use existing ids such as `undershirt`, `hands`, `chest`, `legs`, `feet`, `backpack`, `head`, `weapon`, and `offhand` unless a new slot has clear gameplay value.
- Avoid creating a race-by-sex-by-item explosion. Prefer reusable fit families for humanoids with compatible proportions, then add exact body-archetype visual overrides for items that visibly fail.
- If a race has no compatible clothing visual for an item, the item should not render worn clothing on that race until a proper visual is authored.
