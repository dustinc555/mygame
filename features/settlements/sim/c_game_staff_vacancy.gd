extends "res://addons/gecs/ecs/component.gd"

class_name CGameStaffVacancy

@export var vacancy_id := ""
@export var settlement_id := ""
@export var slot_id := ""
@export var assignment_domain := "employment"
@export var role_id := ""
@export var authority_scope := ""
@export var assignment_exclusivity_group := ""
@export var population_cost := 1
@export var replacement_due_minute := 0
@export var reason := ""
@export var active := true
