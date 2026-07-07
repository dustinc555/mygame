@tool
extends Resource

class_name AuthoredResident

## A hand-authored member of a settlement's population. The seeding pass
## places these first (optionally pinned to a specific staff role), then
## generates the rest of the town around them.

## Character definition resource (features/actors/resources/characters/*).
@export var character: Resource
## Optional staff role this person always holds ("guard", "barkeep",
## "merchant", "worker", ...). Empty = unassigned surplus resident.
@export var pinned_role_id := ""
## Stable id override; empty derives one from the settlement + character name.
@export var stable_id := ""
