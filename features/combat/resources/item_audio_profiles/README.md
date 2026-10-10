# Equipment combat-audio profiles

`ItemDefinition.combat_audio` is the saved, typed authority for an item's sound classification. These shared resources contain no sound files and change no damage, protection, hit location, animation, equipment rules or visuals. Contact playback is owned by the combat audio consumer; the profile is data, not a playback service.

## Authoring in Godot

1. In **FileSystem**, open `res://features/inventory/resources/items/<item>.tres`.
2. In the **Inspector**, find **Combat Audio**, immediately after **Equip Slot**. Drag an existing `.tres` from `res://features/combat/resources/item_audio_profiles/` into that property, or use its resource picker to load one.
3. Click the assigned resource to expand **Weapon Kind**, **Strike Surface**, **Guard Surface** and **Worn Surface**. These are named enum dropdowns; prefer the Inspector to editing serialized integer values. `combat_item_audio_profile.gd` is the single enum definition.
4. Editing a shared resource changes the classification for every item referring to it. For a genuinely different construction, duplicate the closest profile into this directory, give it a descriptive name, edit its dropdowns, and assign the new saved resource to that item. Do not enable **Local To Scene** or create one anonymous copy per item.
5. Save the profile and item. Existing running instances can retain cached resources: reload the relevant resources or restart the game to test saved changes. Verify through `tests/unit/test_item_audio_profiles.gd`; its catalog test loads saved item definitions rather than scanning source strings. Inspect the actual icon and, when unclear, the equipped model in `tools/outfitter/outfitter.tscn` before changing material assignments.

There is no special audio editor dock. This uses the normal Godot Resource Inspector, and the exported property's type and saved assignments are covered by the focused tests.

## What each field means

- **Weapon Kind:** audio family, not a stat or attack-type override. `NONE` is appropriate for shields and worn items. Improvised equipment is legitimate: tools, the bucket and watering can remain classified, and the table knife uses the blade family.
- **Strike Surface:** the working head, point or blade. Spear/axe/hammer/hoe/scythe heads are metal even with wooden shafts. For shields it records the dominant face if shield contact is used; it does not enable shield attacks. Bow profiles describe the bow body's material, not unmodeled ammunition.
- **Guard Surface:** the likely parrying shaft/blade or dominant shield face. Wood shields remain wood despite metal rims, bosses and reinforcing strips. A sword parries on its blade, not its leather-wrapped grip.
- **Worn Surface:** dominant worn contact material only. Clothing uses `CLOTH`, hide/leather gear uses `LEATHER`, rigid armor shells use `PLATE`, and cuffs/crowns/collars use generic `METAL`. Unused fields are explicitly `NONE`.

`CHAINMAIL` is intentionally distinct from `PLATE` and `METAL`. No reviewed equipped picture establishes a mail garment: the knight gambeson is cloth, the knight/skeleton/hellwarden armor has solid plates, and the chain linking imp shackles does not make them mail. For real mail, duplicate a worn profile and set **Worn Surface → CHAINMAIL**. Do not classify from the word "armor" alone. Likewise, decorative helmet horns do not change the whole helmet to bone. `FLESH`, `BONE` and `STONE` remain available in the schema; these equipment resources do not choose the actor body's material.

## Construction decisions and uncertainty

Assignments use the existing transparent model-rendered PNG icons, their actual item scene/visual references, and relevant authored data. They are best-effort dominant-contact classifications, not measurements of every triangle or a hit-location/armor-coverage system. A profile cannot express alternating head/shaft blocks or simultaneous textile/plate layers.

| Case | Chosen profile and reason | Remaining uncertainty |
| --- | --- | --- |
| Spear | `polearm_metal_head_wood_shaft`: visible metal point, long brown shaft | Contact is not localized along the shaft. |
| Axes, hammers, hoe, scythe | Metal working head, wooden parrying shaft | The skeleton axe's brown wrapped shaft is inferred wood; metal collars are secondary. |
| Heater/round shields, including reinforced variants | `shield_wood`: broad visible wood planks | An actual rim/boss hit is not distinguished. |
| Golden Celtic shield | `shield_metal`: smooth pale panels with continuous gold framing rather than visible planks | Panel substrate is not declared; metal is an appearance-based proxy, not an inference from its boss alone. |
| Evil/golden bows | `bow_metal`: thin angular ornamental limbs | Red/gold coloring does not establish substrate; rigid metal is a disclosed proxy. Wooden/recurve bows visibly use wood. No projectile material is inferred. |
| Rusted pickaxe | `tool_metal`: shaft and head both appear corroded metal | Generic source material does not prove a hidden handle core; revise if better evidence establishes wood. |
| Imp mace | `blunt_metal`: spiked rigid head/cage is the dominant contact | Wrapped handle core is unspecified; guard is approximated as metal body contact. |
| Tidebreaker anchor | `blunt_metal`: heavy metal anchor, supported by its existing negative cut-ratio modifier | Sharp flukes do not turn every impact into a blade strike; this does not modify that statistic. |
| Ranger jerkin | `worn_leather`: stiff vest plus quilted brown lower panels and straps | Green panels could be cloth; one dominant leather classification cannot model the layers. |
| Wizard footwear | `worn_cloth`: soft dark split-toe covering and wraps | An unseen leather sole is not established. |
| Knight arms/legs and horned helmets | `worn_plate`: visible solid armor components | Cloth/leather underlayers and ornamental horns remain secondary. |
| Imp shackles/collar and noble crown | `worn_metal`: rigid metal accessories | Chain connectors are not chainmail; this grants no coverage/protection. |
| Bucket / watering can / table utensils | Wood staves / metal vessel / metal utensils | Bands, handles and wraps do not replace the dominant contact material. |

Keep genuinely uncertain choices explicit here when replacing their art or material data. Do not add runtime filename guesses or automatically infer audio from stats, item names, race or price.
