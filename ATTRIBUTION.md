# Attribution

This file is the canonical list of imported third-party assets and software used by this project. Project-authored assets built from Godot primitives or custom code do not need entries here.

## Models / Meshes / Animations

| Asset Pack | Author | License | Price | Source | Project Path |
| --- | --- | --- | --- | --- | --- |
| Universal Base Characters | Quaternius | CC0 1.0 Universal | $0.00 | https://quaternius.com/packs/universalbasecharacters.html | `assets/vendor/quaternius/universal_base_characters/` |
| Universal Animation Library | Quaternius | CC0 1.0 Universal | $0.00 | https://quaternius.com/packs/universalanimationlibrary.html | `assets/vendor/quaternius/universal_animation_library_1/` |
| Universal Animation Library 1 Pro | Quaternius | CC0 1.0 Universal | $0.00 | https://quaternius.com/packs/universalanimationlibrary.html | `assets/vendor/quaternius/universal_animation_library_1_pro/` |
| Universal Animation Library 2 | Quaternius | CC0 1.0 Universal | $0.00 | https://quaternius.com/packs/universalanimationlibrary2.html | `assets/vendor/quaternius/universal_animation_library_2/` |
| Modular Character Outfits - Fantasy | Quaternius | CC0 1.0 Universal | $0.00 | https://quaternius.com/packs/modularcharacteroutfitsfantasy.html | `assets/vendor/quaternius/modular_character_outfits_fantasy/` |
| Modular Weapons Pack | Quaternius | CC0 1.0 Universal | $0.00 | https://quaternius.com/packs/medievalweapons.html | `assets/vendor/quaternius/medieval_weapons/` |
| Fantasy Props MegaKit | Quaternius | CC0 1.0 Universal | $0.00 | https://quaternius.com/packs/fantasypropsmegakit.html | `assets/vendor/quaternius/fantasy_props_megakit/` |
| Medieval Village MegaKit Source | Quaternius | CC0 1.0 Universal | Source pack | https://quaternius.com/packs/medievalvillagemegakit.html | `assets/vendor/quaternius/medieval_village_megakit/` |
| Sci-Fi Essentials Kit | Quaternius | CC0 1.0 Universal | $0.00 | https://quaternius.com/packs/scifiessentialskit.html | `assets/vendor/quaternius/sci_fi_essentials_kit/` |
| Farm Crops 01 | Luceed Studio | Unity Asset Store Standard EULA, Single Entity | Purchased | https://assetstore.unity.com/packages/3d/vegetation/plants/farm-crops-01-304324 | `assets/vendor/luceed-studio/farm-crops-01/` |

## Terrain / Materials

| Asset Pack | Author | License | Price | Source | Project Path |
| --- | --- | --- | --- | --- | --- |
| Soil & Stones (UJWAmw) | ScansLibrary | Fab Standard License | $3.17 | https://www.fab.com/listings/2193002b-8ebd-4cd2-9941-f438b896f63d | `scenes/zones/rustwash_basin/textures/soil_and_stones_ujwamw_4k/` |
| Stylized Soil 02A - Material | LarkArt Store | Fab Standard License |  | https://www.fab.com/listings/39477e0b-a19e-45cf-be76-77240006462e | `assets/vendor/larkart-store/stylized-soil-02a/` |

## Software / Libraries

| Software | Author | License | Price | Source | Project Path |
| --- | --- | --- | --- | --- | --- |
| GECS | csprance | CC0 1.0 Universal | $0.00 | https://github.com/csprance/gecs | `addons/gecs/` |
| LimboAI v1.7.0 | Serhii Snitsaruk and contributors | MIT | $0.00 | https://github.com/limbonaut/limboai | `addons/limboai/` downloaded by `setup_limboai.sh` |

## License Notes

Quaternius marks these packs as CC0 on their pack pages. GECS includes a CC0 1.0 Universal license file in `addons/gecs/LICENSE`. LimboAI includes an MIT license file in `addons/limboai/LICENSE.md` after running `setup_limboai.sh`. CC0 1.0 Universal license text: https://creativecommons.org/publicdomain/zero/1.0/

LimboAI is fetched from the official Godot 4.6 GDExtension release archive so native extension binaries are available without a local C++ build while staying out of git history. Revisit this if the project adopts a dedicated binary artifact or build pipeline. Fab assets use the license selected and purchased through Fab; keep the listing URL and purchase price in the relevant attribution row.

## Import Policy

Imported assets must be listed here before they are committed or retained in the project. If an imported asset cannot be tied to an approved source, author, and license, remove it until that information is available.
