@tool
extends Resource
class_name WorldSkySettings
## Shared sky art direction. Edit sky_settings.tres in the FileSystem Inspector.
## Saved changes apply on the next launch; edits to this live resource apply immediately.
## Periods use game days/hours, not wall-clock seconds. These are visual orbits,
## not a simulation of an Earth solar system.

@export_group("Giant World")
## Apparent diameter in degrees. Large values intentionally create overwhelming scale.
@export_range(5.0, 70.0, 0.1) var planet_diameter_degrees := 58.0:
	set(value):
		planet_diameter_degrees = clampf(value, 5.0, 70.0)
		emit_changed()
## Direction at midnight on day zero. Zero faces +Z, 90 faces +X.
@export_range(0.0, 360.0, 1.0) var planet_heading_degrees := 140.0:
	set(value):
		planet_heading_degrees = fposmod(value, 360.0)
		emit_changed()
@export_range(-60.0, 80.0, 1.0) var planet_altitude_degrees := 32.0:
	set(value):
		planet_altitude_degrees = clampf(value, -60.0, 80.0)
		emit_changed()
@export_range(-70.0, 70.0, 1.0) var planet_axial_tilt_degrees := 27.0:
	set(value):
		planet_axial_tilt_degrees = clampf(value, -70.0, 70.0)
		emit_changed()
@export_range(2.0, 100.0, 0.1) var planet_orbit_days := 18.0:
	set(value):
		planet_orbit_days = maxf(value, 2.0)
		emit_changed()
@export_range(0.1, 10.0, 0.05) var planet_rotation_days := 0.65:
	set(value):
		planet_rotation_days = maxf(value, 0.1)
		emit_changed()
@export var planet_surface: Texture2D:
	set(value):
		planet_surface = value
		emit_changed()

@export_group("Rings")
## Radii in planet radii, not metres. Keep an empty gap above the atmosphere.
@export_range(1.05, 2.5, 0.01) var ring_inner_radius := 1.18:
	set(value):
		ring_inner_radius = clampf(value, 1.05, minf(2.5, ring_outer_radius - 0.05))
		emit_changed()
@export_range(1.1, 3.0, 0.01) var ring_outer_radius := 1.68:
	set(value):
		ring_outer_radius = clampf(value, ring_inner_radius + 0.05, 3.0)
		emit_changed()
## Multiplies particle optical depth; zero removes rings and their shadows.
@export_range(0.0, 3.0, 0.01) var ring_density := 1.0:
	set(value):
		ring_density = clampf(value, 0.0, 3.0)
		emit_changed()
@export_range(0.0, 3.0, 0.01) var ring_brightness := 1.0:
	set(value):
		ring_brightness = clampf(value, 0.0, 3.0)
		emit_changed()
## RGB is particle colour; alpha is face-on opacity. Rings run left to right.
@export var ring_profile: Texture2D:
	set(value):
		ring_profile = value
		emit_changed()

@export_group("Sun and Moon")
@export_range(0.1, 3.0, 0.05) var sun_diameter_degrees := 0.7:
	set(value):
		sun_diameter_degrees = clampf(value, 0.1, 3.0)
		emit_changed()
@export_range(0.25, 10.0, 0.05) var moon_diameter_degrees := 2.6:
	set(value):
		moon_diameter_degrees = clampf(value, 0.25, 10.0)
		emit_changed()
@export_range(2.0, 100.0, 0.1) var moon_orbit_days := 28.0:
	set(value):
		moon_orbit_days = maxf(value, 2.0)
		emit_changed()
## Fraction of an orbit at day zero: 0 is full, 0.5 is new.
@export_range(0.0, 1.0, 0.01) var moon_phase_offset := 0.12:
	set(value):
		moon_phase_offset = fposmod(value, 1.0)
		emit_changed()
@export var moon_surface: Texture2D:
	set(value):
		moon_surface = value
		emit_changed()

@export_group("Deep Sky")
@export_range(0.0, 2.0, 0.01) var nebula_brightness := 0.65:
	set(value):
		nebula_brightness = clampf(value, 0.0, 2.0)
		emit_changed()
@export_range(0.0, 1.0, 0.01) var nebula_coverage := 0.55:
	set(value):
		nebula_coverage = clampf(value, 0.0, 1.0)
		emit_changed()
@export var nebula_teal := Color(0.17, 0.63, 0.65):
	set(value):
		nebula_teal = value
		emit_changed()
@export var nebula_violet := Color(0.48, 0.23, 0.64):
	set(value):
		nebula_violet = value
		emit_changed()
@export_range(0.0, 3.0, 0.05) var star_brightness := 1.0:
	set(value):
		star_brightness = clampf(value, 0.0, 3.0)
		emit_changed()

@export_group("Atmosphere")
@export_range(0.0, 1.0, 0.01) var cloud_coverage := 0.28:
	set(value):
		cloud_coverage = clampf(value, 0.0, 1.0)
		emit_changed()
## Wind phase in radians per game hour. Zero freezes wind, not celestial motion.
@export_range(0.0, 1.0, 0.01) var cloud_wind_speed := 0.12:
	set(value):
		cloud_wind_speed = clampf(value, 0.0, 1.0)
		emit_changed()
@export_range(0.0, 2.0, 0.01) var aurora_brightness := 0.16:
	set(value):
		aurora_brightness = clampf(value, 0.0, 2.0)
		emit_changed()
@export_range(0.0, 3.0, 0.01) var sun_energy := 1.25:
	set(value):
		sun_energy = maxf(value, 0.0)
		emit_changed()
@export_range(0.0, 1.0, 0.01) var moon_energy := 0.46:
	set(value):
		moon_energy = maxf(value, 0.0)
		emit_changed()
@export_range(0.0, 1.0, 0.01) var twilight_energy := 0.28:
	set(value):
		twilight_energy = maxf(value, 0.0)
		emit_changed()
## Presentation-only ambient illumination; does not change stealth game rules.
@export_range(0.0, 1.0, 0.01) var night_ambient_energy := 0.36:
	set(value):
		night_ambient_energy = clampf(value, 0.0, 1.0)
		emit_changed()
