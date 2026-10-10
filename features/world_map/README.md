# World map

The M-key map is an orthographic **cartographic rendering of the played world's actual terrain**, not a screenshot, PDF, or separately drawn continent. X is east/right; Z is south/down. Missing terrain is blank, never fabricated ocean.

## Player controls

- **M** opens/closes; **Esc** closes without opening the pause menu.
- Wheel or **+/−** zooms. Wheel zoom stays under the cursor.
- Left/middle drag pans. **Fit world** fits every present terrain region; **Party** returns to the party.
- Right-click terrain, including unexplored ground, to send the existing selected-party movement command using the destination's actual terrain height. Clicking does not reveal terrain or locations; the party must travel there to discover them. Missing terrain, holes and outside-world clicks are refused. Normal navigation determines the route.
- Travel permanently reveals soft-edged patches. Party knowledge is shared and saved in the normal GECS session save. New terrain does not move existing exploration.
- Visited buildings/roads/towns are remembered. Changes to them are learned when observed again. Moving squads are shown only near current awake party observers, not everywhere the party has ever visited.

## Human-editable settings

Open the world scene, select its **WorldRoot**, then expand **World Map → Map Settings** in the Inspector. Use **Make Unique** to customize that world and save the world scene. Shared defaults:

`features/world_map/resources/default_world_map_settings.tres`

| Property | Purpose |
|---|---|
| `discovery_enabled` | Player discovery on by default; disable for an authoring overview. Does not erase saved exploration. |
| `reveal_radius_meters` | Reveal distance around each awake realized party member. |
| `opening_width_meters` | Width shown when focusing the party. |
| `max_pixels_per_meter` | Close zoom limit. |
| `contour_interval_meters` | Height interval; zero disables contour ink. |
| `relief_strength` | Strength of terrain hillshading. |
| `land_color`, `unknown_color` | Map land ink and uncharted parchment. Authored terrain paint tints the land. |
| `ocean_enabled`, `ocean_height_meters`, `ocean_color` | Optional sea-level rendering. Enable only when the world actually has an ocean at that height. |
| `resident_tile_limit` | In-memory image cache budget. |

Settings apply on the next game launch. Discovery cell/chunk dimensions are **save-format constants**, not visual tuning knobs; changing them requires a migration.

## Ownership and update flow

```text
Played WorldRoot (all composed zones)
  ├─ Terrain3D regions + edit signals ─→ MapWorldSource ─→ WorldAtlasController
  │                                      immutable images     one worker + tile cache
  └─ Buildings / towns / roads ─────────→ indexed map features           │
                                               │                       │
PartyManager ─→ MapExplorationController ─→ GECS exploration component  │
                  current observers         chunks + remembered places │
                                               └───────────┬───────────┘
                                                     WorldMapView
                                                masked tiles + markers
```

- Bootstrap installs both bridge services through `world_map_module.gd`. The old UI entrypoint is only a compatibility facade.
- Only the small realized party is sampled, at a bounded cadence. Stationary party positions do not rewrite exploration. Sleeping/incapacitated bodies remain party pins but do not discover new terrain.
- Terrain/feature discovery scans the composed world once. Additions, removals, transforms and Terrain3D edit signals drive subsequent updates. Local terrain edits retain unrelated region snapshots and invalidate intersecting cached tiles.
- Each view requests a screen-sized set of level-of-detail tiles. One worker consumes immutable snapshots; it never reads scene nodes or changes the gameplay camera. Late invalidated results are rejected. Closing clears queued work; teardown joins the one in-flight job.
- Building silhouettes derive from structural mesh bounds and merge touching modular pieces. They are cartographic footprints, not photorealistic roof captures. Furniture/actors are excluded.
- Discovery is a sparse world-coordinate grid independent of atlas resolution and terrain region IDs. There is no continent-sized fog texture. Render masks are composed only for visible tiles.

```text
on party movement:
    reveal nearby fixed world cells (maximum with existing coverage)
    remember currently observed static features
on world edit:
    replace affected immutable terrain/feature snapshots
    invalidate affected cached images
on map navigation:
    choose tile detail from screen scale
    queue only visible missing tiles
    compose saved discovery masks, then draw remembered features
```

### Content/streaming boundary

The source describes Terrain3D regions present in the composed played WorldRoot, including regions well outside the camera. It does not invent geography for uninstantiated scenes. If a future world streamer unloads regions, it must supply retained lightweight map snapshots/extent through this source boundary; the map UI must not instantiate distant 3D zones to obtain an overview. No such world-streaming manifest currently feeds this feature.

## Verification

- `./tests/run.sh` — full unit suite, including map coordinates, input forwarding/refusal, sparse discovery, GECS restoration, remembered features, native Terrain3D edits/holes and bounded tile requests.
- `./tests/run.sh validation --filter world_map` — actual World1 bootstrap, viewport M/wheel/drag/Esc, native terrain and full-session save/load.
- For optional rendered captures, set `MAP_CAPTURE_DIR` and run `godot --path . --script res://tests/validation/validate_world_map.gd` on a rendered display. Captures disable 3D drawing to isolate the real 2D UI, not to measure game FPS. `geography-preview` captures temporarily disable discovery on a duplicated in-memory setting; no world or default resource is saved.

Serialize Godot runs with the shared project execution lock when other agents are validating. Keep captured output and user data isolated; do not overwrite player saves.
