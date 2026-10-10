@tool
extends Resource
class_name CombatItemAudioProfile
## Authored contact classification only; does not change damage or equipment rules.

enum WeaponKind { NONE, BLADE, AXE, BLUNT, POLEARM, BOW, TOOL }
enum Surface { NONE, FLESH, BONE, CLOTH, LEATHER, WOOD, METAL, CHAINMAIL, PLATE, STONE }

@export var weapon_kind: WeaponKind = WeaponKind.NONE
## The working head, blade or point, not necessarily the handle.
@export var strike_surface: Surface = Surface.NONE
## The dominant parrying or shield surface, not decorative fittings.
@export var guard_surface: Surface = Surface.NONE
## The worn item's contact surface; body material is resolved separately.
@export var worn_surface: Surface = Surface.NONE
