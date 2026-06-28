extends "res://features/actors/projection/humanoid/humanoid_character.gd"

class_name BarberHumanoid

@export_range(0, 999, 1) var barber_service_price := 1


func get_barber_service_price() -> int:
	return barber_service_price
