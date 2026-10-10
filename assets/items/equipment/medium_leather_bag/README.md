# Medium Leather Bag

Project-authored leather backpack. This is the accepted rounded-flap model: a
rough tan hide sack, scuffed firmer leather flap, dark closure strap and dull
metal buckle. Reference photographs informed the material; no photo pixels are
embedded. There are deliberately no wrapping shoulder straps.

## Source and import

- `source/medium_leather_bag.blend`: editable source with packed textures. The
  source directory is excluded from Godot import by `.gdignore`.
- `medium_leather_bag.glb`: the same source geometry/materials, exported in metres
  with Godot Y-up and the bag's outward face toward local +Z.
- Textures are embedded in the GLB and imported scene. Keep the `.glb.import`
  sidecar; do not extract or bind the old draft backpack's loose texture maps.
- `../../icons/medium_leather_bag.png`: transparent picture of this exact model.

Edit the Blender source and export this single GLB; do not maintain male/female
or race-specific bag meshes. Preserve its orientation, material UVs and scale.

## Item and fitting controls

Open `features/inventory/resources/items/medium_leather_bag.tres` in Godot.
The item uses the **Backpack** slot, a 2×3 inventory footprint, weight 1.5 and
stack limit 1. **Humanoid Only** checks body anatomy, not a race-name whitelist.
Humanoid body archetypes use visual body type Male or Female; the race must expose
a backpack slot. QuadBot's Cargo slot is not humanoid anatomy.

Expand **Equipped Visuals → Visual_shared → Rigid Back Fit** to tune:

- **Back Height Ratio**: maximum bag height relative to pelvis–neck length.
- **Back Width Ratio**: maximum bag width relative to shoulder span.
- **Back Clearance Ratio**: space behind the measured torso surface.
- **Back Raise Ratio**: bag-bottom height above the pelvis, in torso lengths.

Scale is uniform, preserving the accepted silhouette. The shared fitter measures
the posed body once on equip/rebuild and attaches to `spine_03`; it has no
per-frame fitting process. New humanoid rigs must provide `pelvis`, `neck_01`,
`spine_03`, `upperarm_l` and `upperarm_r`, and a skinned torso. Unsupported rigs
report a fit error instead of showing an unfitted mesh. The same fitter serves
live humanoids, the character editor and Bestiary equipment projection.

## Storage and trading

The bag owns a **10×10 inventory**, separate from personal pockets. Click **Open**
attached directly to its equipped slot, or double-click the equipped bag's icon.
For a carried bag, right-click and choose **Open Bag**. Its popup can be moved and
closed independently, with the full grid visible when the viewport has room.

With a trader open, the character, backpack and merchant windows fit side by side
at the normal game-window size. On narrower screens, the merchant stock view
scrolls horizontally rather than shrinking item art or covering the backpack.
Closing the bag restores the merchant's normal width. This only constrains the
visible scroll area; the stock's actual grid and item positions do not change.

Drag items between the grids normally. During merchant trading, open the same bag
and drag purchases into it or its contents into the merchant grid, then press
**Trade**. **Reset** clears trade proposals, not ordinary pocket/bag rearrangements.
Payment uses the character's personal purse; the bag is not a second purse.

**Shift-click transfers** share the same destination rule for looting, party
handover and buying: try the recipient's open owned bag before personal inventory.
With the equipped backpack closed, try personal inventory first, then automatically
open the equipped bag for overflow. "No room" appears when neither grid can fit the
item. Shift-click also takes worn equipment from the other character into storage;
it does not equip that item on the recipient. A source bag belongs to its owner's
side of the exchange, not a third participant.

`PartyInventoryController._route_quick_transfer` owns this destination order.
Loose and equipped loot use the same transfer checks as dragging: capacity is
checked before theft, and a refused theft stops rather than retrying through
another inventory. Existing ownership, nesting and carry-weight rules still apply.
Manual dragging chooses the destination explicitly.

Purchases stay pending until **Trade**. Their preview grids reserve cells, so later
clicks account for earlier offers; closing/reopening a bag retains those offers.
Additional units of a partially offered stack join its existing placement.

**Equipping owned items** returns replaced equipment to the inventory the new item
came from, including when a merchant window is open. It tries the vacated cells
first, then another position in that same inventory. If the replacement cannot be
stored there, the swap is refused without moving either item into pockets or onto
the cursor. Item identities and condition are retained; Reset does not undo an
owned equipment swap. Merchant purchases and NPC looting keep their own rules.

Contents belong to the exact bag item and follow equip/unequip, handover,
drop/pickup and save/load. Their weight and the equipped bag's own weight count
toward the character's existing carry limit: this adds slots, not another weight
allowance. Bags cannot contain other bags. Empty a bag before selling the bag
itself; selling its contents separately is supported. Existing theft and work
inventory restrictions still apply.

Tune **Storage Grid Size** on the item resource above. It is measured in inventory
cells and takes effect when the bag is next opened. Zero disables storage. Existing
saved contents are retained when dimensions change; shrinking below occupied cells
may require removing/rearranging goods. This setting is independent of the bag's
2×3 footprint in another inventory and of the fitting controls.

`ItemStorageView` projects saved item metadata into an `InventoryData` while the
window is open. It publishes changes through the existing GECS item record, and
invalidates on ownership change, projection loss or load rather than writing stale
contents back. Trading snapshots each participating inventory and restores them
together when payment, placement or carry capacity refuses the deal.

## Merchant controls

In `scenes/zones/rustwash_basin/rustwash_basin.tscn`, select
`Towns/Canyon/CanyonTradeStation`. Its **Stock Overrides** sets this item's target
to **2**, with **Replenishes** enabled. The existing delivery schedule is every
3 in-game days at 08:00. Restocking fills missing stock, never adds two on top or
resets merchant money. Other shops' presets are unchanged.

Already-saved merchant inventories retain their saved supply policy; this change
does not reset or migrate existing saves. A newly created merchant uses this
updated authored policy.

## Verification

- `tests/unit/test_backpack_inventory.gd`: separate storage, pointer-driven opening,
  dragging, Shift-click routing and trading, rollback, shared weight, exact-item
  lifecycle and save/load.
- `tests/unit/test_item_storage.gd`: storage serialization and separate trade endpoints.
- `tests/unit/test_npc_inventory_access.gd`: pointer-driven loose/equipped loot,
  nested body bags, single-attempt theft checks, capacity refusal and invalidation
  when the opponent recovers or its body is removed.
- `tests/unit/test_backpack_equipment.gd`: canonical item and race-independent
  humanoid eligibility, including Rustdead and a new synthetic humanoid race.
- `tests/unit/test_shared_clothing_projection.gd`: upper-spine following,
  source preservation, shared mesh reuse, actor/editor/Bestiary removal and
  missing-anatomy refusal.
- `godot --headless --path . --script res://tests/validation/validate_medium_leather_bag.gd`:
  actual authored Canyon stock, initial inventory, top-up behavior, above-target
  sales, inventory space and currency preservation without world startup.
