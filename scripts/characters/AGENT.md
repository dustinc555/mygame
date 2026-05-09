# AGENT.md

## Humanoid Equipment
- Equipment belongs on `HumanoidCharacter`, not `PartyMember`, so NPCs and party members share the same system.
- Do not add player-only assumptions to equipment code. Non-party humanoids should still be able to equip and render gear.
- Equipment visuals should be rebuilt from item data and reusable visual scenes, not from test-level-specific logic.
- Clothing visuals should animate in sync with the base character animation players.
- Hand-held equipment should attach through `BoneAttachment3D` using grip profile metadata, falling back to the configured slot-to-bone mapping.
- Equipped bone visuals must use an attachment pivot: apply item `equipped_transform` to the pivot, then add the equipped scene under it without overwriting the scene root transform.
- Do not hardcode per-item weapon placement in this script. Use item resources and `scenes/world/equipment/` wrapper scenes instead.
- If a weapon looks wrong, fix its wrapper scene or item resource; do not add conditional orientation code here.

## Grip And Animation Architecture
- `EquipmentGripProfile` is the bridge between equipment data and future animation/IK systems.
- Phase 1 fully supports one-hand melee and offhand shield attachment only.
- Future grip profiles such as two-hand sword, two-hand axe, two-hand blunt, polearm, bow, crossbow, and thrown should request stance-specific animations or IK rather than adding per-item hacks.
- Normal idle, walk, run, and fighting/combat poses are the primary validation targets for hand-held gear. Sitting can use future sitting policies such as keep, hide, or relax.

## Clothing Rendering
- Keep the base character model visible when clothing is equipped.
- Use item `equipped_surface_offset_ratio` for clothing shell fit over the base body.
- Runtime clothing mesh inflation must duplicate/replace the equipped mesh instance, not mutate imported shared mesh assets in place.

## Animation Baseline
- Normal standing idle is the baseline pose for equipment placement tuning.
- If adding more idle variants, make sure equipment placement can still be inspected against a stable normal idle pose.
