# Original mineral giant

Original fictional-world art authored for this project, not a photograph, recolour,
paint-over or derivative of Jupiter, Saturn or another supplied planetary map.
No external source images or third-party image generators were used.

- `mineral_giant_surface.png`: 4096 × 2048 RGB equirectangular albedo. Mineral-blue,
  slate and muted ivory cloud decks; irregular sheared storm vortices, fine cloud
  sheets, seamless longitude and convergent poles. Lighting is not baked in.
- `mineral_giant_rings.png`: 4096 × 32 RGBA radial profile, inner edge at the left.
  RGB is particle colour; alpha is face-on opacity, not brightness. Fine ringlets,
  two denser belts, an open division and a fading dust fringe are authored here.
  Rows repeat intentionally; this is a radial lookup, not a planet panorama.

These are editable source images. Both use mipmapped high-quality VRAM compression
in Godot. The ring's RGB must survive low/zero alpha: keep `fix_alpha_border=false`
and `premult_alpha=false` in its import settings.

The original art was constructed from seeded periodic noise and coordinate-advection
vortices, not sampled from vendor imagery. Its initial authoring seed was 84173.
The sky consumes only the saved images; there is no runtime texture generator,
external dependency, separate animation clock or new art-tool framework.

Assign images and tune size, ring span, density and brightness through Godot's
FileSystem → `features/world/resources/sky/sky_settings.tres` → Inspector.
The shader owns sunlight, translucency and mutual planet/ring shadows. See that
resource directory's README for units and when saved changes take effect.
