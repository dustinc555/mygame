extends Resource

## Select food_sharing_settings.tres in the Inspector to tune sharing reach.
## Changes apply to the next meal check; no saved food or toggles are reset.
@export_range(0.1, 50.0, 0.1, "suffix:m") var distance := 5.0
