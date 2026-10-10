# Sky art direction

In Godot's **FileSystem**, open `features/world/resources/sky/sky_settings.tres`.
The Inspector groups the shared defaults into **Giant World**, **Rings**, **Sun and Moon**,
**Deep Sky** and **Atmosphere**. Save the resource and restart the game to use
saved changes. Editing the runtime controller's shared resource applies immediately
but is not a saved authoring change unless the resource is explicitly saved.

- **Planet Diameter Degrees** changes apparent scale, not physical world geometry.
  The default 58° intentionally fills much of the view. Heading and altitude set
  its day-zero midnight position; orbit and rotation periods use **game days**.
- **Planet Axial Tilt Degrees** tilts the surface bands and thin ring plane together.
  The authored -9° inclination gives a long, shallow ring silhouette rather than
  a broad overhead arch. Rings cast shadows on the surface, and the planet shadows
  its rings.
- **Rings → Inner/Outer Radius** sets the ring span in planet radii (1 = the planet's
  surface), not metres. The outer edge must remain at least 0.05 beyond the inner.
  **Density** changes particle opacity and the shadow together; zero removes both.
  **Brightness** controls scattered light without changing opacity. The two faces
  reflect/transmit sunlight differently instead of sharing one uniform brightness.
  **Ring Profile** stores particle colour in RGB and face-on opacity in alpha,
  progressing from the inner edge at the image's left to the outer edge at its right.
- **Sun/Moon Diameter Degrees**, **Moon Orbit Days**, and **Moon Phase Offset**
  control the disks and the changing moon phase. Offset zero starts near full.
- **Nebula Brightness/Coverage**, the teal/violet colors, **Star Brightness** and
  **Aurora Brightness** control the full-direction night composition.
- **Cloud Coverage** and **Cloud Wind Speed** control foreground atmospheric veils.
  Wind speed is angular pattern travel in radians per game hour; zero freezes
  wind only. **Night Ambient Energy** controls landscape readability, not stealth.

`DayNightLightingController` projects the canonical `WorldTimeController` clock
into matching light directions and GPU shader parameters. The sky has no separate
wall-clock timer or saved state: pausing freezes it, and loading the world clock
reconstructs the same sky. Distant nebulae rotate with the sky; nearby clouds and
auroral veils evolve. Visual orbits are authored fantasy art direction, not a
scientific model of the Earth solar system.

All celestial bodies are rendered by `celestial_sky.gdshader` in the sky background.
They do not create nearby meshes, write world depth, or move with camera translation.
Opaque terrain, buildings and characters therefore remain in front of them.
Surface maps/stars render at screen resolution; soft nebula/cloud layers use the
half-resolution sky pass. Lighting cubemap rendering omits expensive space detail.
Gameplay's established ambient stealth-visibility curve is preserved separately.

The mineral-blue/ivory giant and its ring profile are original project-authored
images in `assets/sky/mineral_giant/`, not Jupiter/Saturn photographs or recolours.
Replace **Giant World → Planet Surface** or **Rings → Ring Profile** to change their
art without changing the sky system. The unchanged Moon map is credited in the
root `ATTRIBUTION.md` and the vendor directory's `ATTRIBUTION.md`; retain those
credits in distributed builds. The former Jupiter/Saturn source images are preserved
in the vendor directory but are no longer assigned to the sky.

## Verification

- Fast behavior checks: `./tests/run.sh unit -gselect=test_day_night_sky.gd`.
- Full unit gate: `./tests/run.sh`.
- Native rendered workflow: `godot --path . res://tests/validation/validate_celestial_sky_rendered.tscn`.
  This self-terminating GPU check verifies camera translation, pause, clock restore,
  visible evolution and opaque occluders at 450 and 4500 metres. It writes images
  and JSON to `.test-results/celestial-sky/`; `SKY_CAPTURE_PREFIX` overrides the prefix.
  It is explicitly opt-in in the validation manifest because the headless suite's
  dummy renderer cannot read actual sky pixels. A passing headless test alone is
  not a visual or performance acceptance.
