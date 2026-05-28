# Attribution

This file is the canonical list of imported third-party assets and software used by this project. Project-authored assets built from Godot primitives or custom code do not need entries here.

## Models / Meshes / Animations

| Asset Pack | Author | License | Source | Project Path |
| --- | --- | --- | --- | --- |
| Universal Base Characters | Quaternius | CC0 1.0 Universal | https://quaternius.com/packs/universalbasecharacters.html | `assets/vendor/quaternius/universal_base_characters/` |
| Universal Animation Library | Quaternius | CC0 1.0 Universal | https://quaternius.com/packs/universalanimationlibrary.html | `assets/vendor/quaternius/universal_animation_library_1/` |
| Universal Animation Library 1 Pro | Quaternius | CC0 1.0 Universal | https://quaternius.com/packs/universalanimationlibrary.html | `assets/vendor/quaternius/universal_animation_library_1_pro/` |
| Universal Animation Library 2 | Quaternius | CC0 1.0 Universal | https://quaternius.com/packs/universalanimationlibrary2.html | `assets/vendor/quaternius/universal_animation_library_2/` |
| Modular Character Outfits - Fantasy | Quaternius | CC0 1.0 Universal | https://quaternius.com/packs/modularcharacteroutfitsfantasy.html | `assets/vendor/quaternius/modular_character_outfits_fantasy/` |
| Modular Weapons Pack | Quaternius | CC0 1.0 Universal | https://quaternius.com/packs/medievalweapons.html | `assets/vendor/quaternius/medieval_weapons/` |

## Software / Libraries

| Software | Author | License | Source | Project Path |
| --- | --- | --- | --- | --- |
| GECS | csprance | CC0 1.0 Universal | https://github.com/csprance/gecs | `addons/gecs/` |
| LimboAI v1.7.0 | Serhii Snitsaruk and contributors | MIT | https://github.com/limbonaut/limboai | `addons/limboai/` downloaded by `setup_limboai.sh` |

## License Notes

Quaternius marks these packs as CC0 on their pack pages. GECS includes a CC0 1.0 Universal license file in `addons/gecs/LICENSE`. LimboAI includes an MIT license file in `addons/limboai/LICENSE.md` after running `setup_limboai.sh`. CC0 1.0 Universal license text: https://creativecommons.org/publicdomain/zero/1.0/

LimboAI is fetched from the official Godot 4.6 GDExtension release archive so native extension binaries are available without a local C++ build while staying out of git history. Revisit this if the project adopts a dedicated binary artifact or build pipeline.

## Import Policy

Imported assets must be listed here before they are committed or retained in the project. If an imported asset cannot be tied to an approved source, author, and license, remove it until that information is available.
