# AGENT.md

## Item Data Scripts
- Keep item/equipment behavior data-driven so new gear can be added by creating resources rather than writing one-off code.
- `ItemDefinition` is the gameplay-facing item resource: inventory shape, icon, stats, equipped scene, grip profile, and final equipped transform live there.
- `EquipmentGripProfile` is stance/attachment metadata. It should describe how a family of equipment attaches now and how future animation/IK systems should classify it.
- Do not encode per-item model orientation in scripts. Use equipment wrapper scenes and item resources.

## Adding Future Equipment Metadata
- Add reusable fields here only when they apply to a class of items, not just one item.
- Prefer profile/resource references over stringly typed special cases when future agents will add many items.
- Two-hand, bow, crossbow, polearm, and thrown weapon support should extend grip/profile data first, then animation or IK systems.
