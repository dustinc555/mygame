# AGENT.md

## Reusable Containers
- World containers must be reusable scene components, not test-level-specific storage logic.
- Use `starting_items: Array[InventoryStock]` to seed reusable container inventories.
- Container scenes such as lockers and weapon chests should be draggable into any bootstrapped scene and work without custom level code.
- Keep ownership, locking, inventory display, and interaction distance data-driven through exported properties.
- Do not hardcode armory/test-scene item lists in `WorldContainer`; configure stock on the placed container or reusable container scene.
