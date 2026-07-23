extends Control

const LEDGER := preload("res://features/settlements/projection/town_ledger_window.tscn")


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("24303a")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var ledger := LEDGER.instantiate() as TownLedgerWindow
	add_child(ledger)
	ledger.setup("visual:test", {
		"settlement_name": "Canyon",
		"record_state": "current",
		"reported_at_text": "Mon 01:00 PM",
		"overview": {
			"population": 12,
			"housing_capacity": 18,
			"food_outlook": "Well supplied",
			"provisions": 16.5,
			"reserve": "Self-sustaining",
			"daily_use": 12.0,
			"daily_output": 12.0,
			"daily_balance": 0.0,
		},
		"people": [
			{"name": "Vaughn", "job": "Ruler", "workplace": "Canyon Keep"},
			{"name": "Mara", "job": "Warden", "workplace": "Canyon Jail"},
			{"name": "Alden", "job": "Guard", "workplace": "Canyon Keep"},
			{"name": "Bess", "job": "Barkeeper", "workplace": "Dustcup Rest Stop"},
			{"name": "Corin", "job": "Unassigned", "workplace": "None"},
			{"name": "Della", "job": "Farmer", "workplace": "South Field"},
			{"name": "Emery", "job": "Unassigned", "workplace": "None"},
			{"name": "Fenn", "job": "Guard", "workplace": "Canyon Jail"},
			{"name": "Garrick", "job": "Unassigned", "workplace": "None"},
			{"name": "Hale", "job": "Farmer", "workplace": "North Field"},
		],
		"buildings": [
			{"name": "Canyon Keep", "purpose": "Keep", "owner": "Vaughn"},
			{"name": "Canyon City Rest Stop", "purpose": "Bar", "owner": "Bess"},
			{"name": "Canyon Granary", "purpose": "Storehouse", "owner": "Town-owned"},
		],
		"food": [
			{"food": "Bread", "stored": 7, "produced": "0.0", "consumed": "4.0", "remaining": "1.8 days"},
			{"food": "Provisions", "stored": 3, "produced": "6.0", "consumed": "2.0", "remaining": "Sustainable"},
		],
		"stores": [
			{"item": "Green Bottle", "quantity": 1},
			{"item": "Bandage", "quantity": 4},
		],
	})
