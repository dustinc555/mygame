extends GutTest

const THUGS = preload("res://features/factions/resources/factions/roaming_desert_thugs.tres")
const CITY = preload("res://features/factions/resources/factions/canyonites.tres")
const CRIMES := ["theft", "trespass", "assault", "murder", "lockpicking", "escape"]

var factions: FactionController
var alerts: CrimeAlertController

func before_each() -> void:
	factions = FactionController.new()
	add_child_autofree(factions)
	factions.faction_definitions = {THUGS.get_id(): THUGS, CITY.get_id(): CITY}
	alerts = CrimeAlertController.new()
	add_child_autofree(alerts)
	alerts._factions = factions

func test_desert_thugs_have_no_enabled_crimes() -> void:
	for crime in CRIMES:
		assert_false(alerts.crime_is_illegal_for_faction(crime, THUGS.get_id()), "Thug camp must not file %s charges" % crime)

func test_city_keeps_its_enabled_crimes() -> void:
	for crime in CRIMES:
		assert_true(alerts.crime_is_illegal_for_faction(crime, CITY.get_id()), "City still enforces %s" % crime)
