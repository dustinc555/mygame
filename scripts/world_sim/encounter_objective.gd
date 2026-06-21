extends Resource

class_name EncounterObjective

## Editor-authored description of what an attacking squad WANTS and how its encounter
## plays out. The fight resolves the same way regardless (dice on combat-stat leverage);
## the objective only decides the OPENING beat (demand vs straight assault), the grace
## windows, and what the winner takes. New raider goals = a new .tres, not new code.

## "demand" = arrive and demand tribute first (a grace beat before any fighting).
## "assault" = skip the demand and go straight to the fight grace.
@export var objective_id := "demand_tribute"
@export var display_name := "Demand Tribute"
@export var opening := "demand"

## Seconds the target gets to decide (pay / refuse) before the demand commits. This is
## also the player's window to arrive and intervene (Slice 3).
@export_range(0.0, 120.0, 0.5) var demand_grace_seconds := 18.0
## Seconds the standoff holds once a fight is inevitable, before dice resolve. The
## player's window to arrive and turn it into a real fight (Slice 2).
@export_range(0.0, 120.0, 0.5) var fight_grace_seconds := 12.0

## Tribute the target pays if it complies.
@export_range(0.0, 500.0, 1.0) var demand_food_amount := 25.0
## Food the attackers haul off if they win the fight.
@export_range(0.0, 500.0, 1.0) var loot_food_on_win := 35.0
## Fraction of the losing raiders the defenders capture (jailed) when the town wins;
## the rest flee home.
@export_range(0.0, 1.0, 0.05) var capture_fraction_on_defense_win := 0.5


func get_id() -> String:
	return objective_id if not objective_id.is_empty() else display_name
