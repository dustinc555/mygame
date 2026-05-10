# AGENT.md

## Humanoid Equipment
- Equipment belongs on `HumanoidCharacter`, not `PartyMember`, so NPCs and party members share the same system.
- Do not add player-only assumptions to equipment code. Non-party humanoids should still be able to equip and render gear.
- Equipment visuals should be rebuilt from item data and reusable visual scenes, not from test-level-specific logic.
- Multi-step equipment changes should use the reusable equipment update batch so visuals rebuild once after the final equipment state is known.
- Clothing visuals should animate in sync with the base character animation players.
- Hand-held equipment should attach through generated body grip sockets, not directly through one-off item pivots.
- `HumanoidCharacter` should create named socket markers such as `RightHandGrip` and `LeftHandGrip` under `BoneAttachment3D` nodes attached to the final `hand_r` / `hand_l` bones.
- Equipped bone visuals must align the item's grip marker, usually `GripPoint_Primary`, to the generated body socket from `HumanoidGripSocketProfile`.
- Use item `equipped_transform` only for item scale and small final overrides after socket-to-marker alignment.
- Do not hardcode per-item weapon placement in this script. Use item resources and `scenes/world/equipment/` wrapper scenes instead.
- If a weapon looks wrong, fix its wrapper scene or item resource; do not add conditional orientation code here.
- If all compatible items look wrong on one body shape, tune that body's grip socket profile instead of changing item wrappers.
- If body sliders or generated rigs change hand bones/proportions after visual setup, call `refresh_grip_sockets_for_body()` after the final body is applied so socket transforms are reapplied to the live hand-bone attachments.
- Use `show_grip_socket_markers` only as a runtime/editor debugging aid for socket visualization; do not rely on visible debug meshes for gameplay.
- Human operators should tune shared socket transforms through `scenes/tools/humanoid_grip_socket_calibrator.tscn`, not by opening `.tres` resources or editing imported character models.
- Runtime equipment placement should remain the simple snap: item `GripPoint_Primary` to body `RightHandGrip`/`LeftHandGrip`.

## Grip And Animation Architecture
- `EquipmentGripProfile` is the bridge between equipment data and future animation/IK systems.
- Phase 1 fully supports one-hand melee and offhand shield attachment only.
- Future grip profiles such as two-hand weapon, polearm, bow, crossbow, and thrown should request stance-specific animations or IK rather than adding per-item hacks.
- Normal idle, walk, run, and fighting/combat poses are the primary validation targets for hand-held gear. Sitting can use future sitting policies such as keep, hide, or relax.

## Clothing Rendering
- Keep the base character model visible when clothing is equipped.
- Use item `equipped_surface_offset_ratio` for clothing shell fit over the base body.
- Runtime clothing mesh inflation must duplicate/replace the equipped mesh instance, not mutate imported shared mesh assets in place.

## Animation Baseline
- Normal standing idle is the baseline pose for equipment placement tuning.
- If adding more idle variants, make sure equipment placement can still be inspected against a stable normal idle pose.
