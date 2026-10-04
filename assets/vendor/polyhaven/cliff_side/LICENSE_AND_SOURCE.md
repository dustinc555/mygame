# Cliff Side — source texture maps

- Asset: Cliff Side, Poly Haven
- Photography: James Ray Cock and Dario Barresi
- Processing: Jenelle van Heerden
- License: CC0 1.0 Universal
- Source: https://polyhaven.com/a/cliff_side
- License statement: https://polyhaven.com/license
- CC0 terms: https://creativecommons.org/publicdomain/zero/1.0/

The four 4K maps are unmodified downloads verified against the API's MD5 hashes.
Godot skips this source directory via `.gdignore`. Runtime texture assets are
packed in `scenes/zones/rustwash_basin/textures/canyon_cliff/`:
RGB albedo + displacement in alpha; OpenGL normal RGB + roughness in alpha.
Both layers have mipmaps and RGBA8 format to match the existing soil array.
The original soil maps are not modified.
