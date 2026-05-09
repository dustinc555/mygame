# AGENT.md

## Humanoid Equipment
- Equipment belongs on `HumanoidCharacter`, not `PartyMember`, so NPCs and party members share the same system.
- Do not add player-only assumptions to equipment code. Non-party humanoids should still be able to equip and render gear.
- Equipment visuals should be rebuilt from item data and reusable visual scenes, not from test-level-specific logic.
- Clothing visuals should animate in sync with the base character animation players.
- Hand-held equipment should attach through `BoneAttachment3D` using the configured slot-to-bone mapping.
- Do not hardcode per-item weapon placement in this script. Use item resources and `scenes/world/equipment/` wrapper scenes instead.

## Clothing Rendering
- Keep the base character model visible when clothing is equipped.
- Use item `equipped_surface_offset_ratio` for clothing shell fit over the base body.
- Runtime clothing mesh inflation must duplicate/replace the equipped mesh instance, not mutate imported shared mesh assets in place.

## Animation Baseline
- Normal standing idle is the baseline pose for equipment placement tuning.
- If adding more idle variants, make sure equipment placement can still be inspected against a stable normal idle pose.
