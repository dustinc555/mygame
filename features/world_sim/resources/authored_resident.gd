@tool
extends Resource

class_name AuthoredResident

## A hand-authored member of a settlement's population. Facility role slots
## own assignments; this resource only guarantees the person exists.

## Character definition resource (features/actors/resources/characters/*).
@export var character: Resource
## Stable id override; empty derives one from the settlement + character name.
@export var stable_id := ""
