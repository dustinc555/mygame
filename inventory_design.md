# Inventory Design

- Item art lives in `assets/items/` and is grouped by category such as `ore/`, `food/`, and `armor/`.
- Prefer `png` for item icons; `webp` is acceptable for source art but items should be imported into the project in a stable UI-friendly format.
- Inventory size is measured in grid cells, not source pixels.
- Item icons are drawn once across their occupied rectangle and keep aspect ratio; they do not stretch to fill mismatched shapes.
- A small padding margin is kept inside the occupied rectangle so icons do not touch grid lines.
- Current copper ore uses `assets/items/ore/copper.png` and a `3x2` footprint because the source image is `75x50` (`1.5:1`).
- World resource nodes and inventory item footprints are separate decisions; a large copper vein in the world can still produce a `3x2` copper ore item.
