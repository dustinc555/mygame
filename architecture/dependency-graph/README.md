# Dependency & Coupling Graph

Interactive, code-derived view of how the game's scripts actually depend on each
other — and where they break our architecture rules. This is **how we visualize
architecture in this project from now on**: dependency graph + layer coupling +
rule-violation insights. Charts that only show *containment* (trees, treemaps,
taxonomies) don't reveal architecture — the insight lives in the **edges**.

## Run it

```sh
cd architecture/dependency-graph
node extract_deps.js     # parse scripts/ → graphdata.js  (also prints a report)
node serve.js            # serve on http://localhost:3031
```

Or in one line: `node extract_deps.js && node serve.js`.
ECharts is vendored in `vendor/` — no internet or `npm install` needed.

## What it shows

Two views (toggle, top-left):

- **Dependencies** — force-directed graph of every script. Color = architectural
  layer. Node size = in-degree (how many things depend on it → hubs are big).
  Hover a node to spotlight its neighbors; drag, scroll-zoom, filter by name.
- **Layer coupling** — the macro view: the ~16 layers in a ring, edge thickness =
  number of cross-layer dependencies, arrows = direction. The "shape" of the
  architecture on one screen.

Three rule highlights (checkboxes) + an **Insights** panel:

| Highlight | Color | Means |
|---|---|---|
| **truth-rule** | red | a GECS system/component depends on a live node — violates *"GECS owns truth; systems read components, not nodes."* |
| **self-tick** | gold | a durable-domain node runs real work on `_process`/`_physics_process` every frame, ungated by LOD and not on world-sim cadence — violates the tick rule below. |
| **cycles** | orange | circular dependencies (Tarjan SCCs) — can't be reasoned about / tested in isolation. |

The Insights panel also lists **top hubs** (most depended-upon — change carefully)
and **most-coupled** (god-objects).

## The rules it checks

1. **Truth rule.** GECS is the single source of durable truth. Systems and
   components read/write components — never reach into live scene nodes.

2. **Tick / cadence rule.** A per-frame tick is only allowed if it is *either*:
   - **projection-side** — it only behaves within LOD and stops outside it (the
     node only exists / acts when near the camera); **or**
   - **driven by the controlled world-sim ticker at O(1) cadence** (e.g.
     `NestWorldSimPlugin.world_sim_tick(...)`, not its own `_process`).

   A node that ticks durable logic **every frame regardless of camera/LOD and not
   on cadence is a violator** (e.g. `SettlementJail`, `SettlementKeep`). Editor-only
   ticks (`set_process(Engine.is_editor_hint())`) are fine.

## Tuning

- **Layers** and excluded folders: `layerOf()` / `EXCLUDE` in `extract_deps.js`.
- **Tick allowlist**: `TICK_ALLOW` in `extract_deps.js` — the sanctioned tick
  *drivers* and projection/visual controllers that can't be told apart from
  violators by static text. Edit if a classification is wrong.
- **Edge sources**: `extends` + `preload`/`load` + `class_name` usage. Usage edges
  are text-based, so a class named in code (not comments/strings) counts as a dep —
  occasional false positives are possible.

`graphdata.js` is generated — regenerate with `node extract_deps.js` after code
changes.
