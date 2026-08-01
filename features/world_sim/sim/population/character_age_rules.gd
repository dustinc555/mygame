extends RefCounted

class_name CharacterAgeRules

const UNKNOWN_BIRTH_DAY := -2147483648
const DAYS_PER_YEAR := 365
const DEFAULT_ADULT_AGE := 23
const TARGET_STANDARD_DEVIATION := 23.0
const TEEN_MIN_AGE := 13
const TEEN_MAX_AGE := 16
const ELDERLY_MIN_AGE := 65
const ELDERLY_MAX_AGE := 95
const ADULT_MIN_AGE := 17
const ADULT_MAX_AGE := 64
const STANDARD_DEVIATION_TUNING_AGES := [17, 23, 29, 35, 41, 47, 53, 59, 64]



static func age_years(birth_day_index: int, current_day_index: int) -> int:
	if birth_day_index == UNKNOWN_BIRTH_DAY:
		return DEFAULT_ADULT_AGE
	return maxi(0, int(floor(float(current_day_index - birth_day_index) / float(DAYS_PER_YEAR))))


static func has_birth_day(record: Dictionary) -> bool:
	return int(record.get("birth_day_index", UNKNOWN_BIRTH_DAY)) != UNKNOWN_BIRTH_DAY


static func birth_day_for_age(age: int, current_day_index: int, rng: RandomNumberGenerator = null) -> int:
	var safe_age := maxi(0, age)
	var day_offset := rng.randi_range(0, DAYS_PER_YEAR - 1) if rng != null else 0
	return current_day_index - safe_age * DAYS_PER_YEAR - day_offset


static func is_teen(age: int) -> bool:
	return age >= TEEN_MIN_AGE and age <= TEEN_MAX_AGE


static func is_elderly(age: int) -> bool:
	return age >= ELDERLY_MIN_AGE


static func maximum_strict_fifth_count(population_count: int) -> int:
	if population_count <= 0:
		return 0
	return maxi(0, int(floor(float(population_count - 1) / 5.0)))


## Produces ages for the missing members of a final cohort. Existing ages remain
## authoritative while new members fill the largest teen and elderly cohorts
## that remain strictly below one fifth. Evenly covering each age band yields a
## population standard deviation close to 23 years without unbounded samples.
static func generate_missing_ages(final_count: int, existing_ages: Array[int], rng: RandomNumberGenerator) -> Array[int]:
	var safe_final_count := maxi(0, final_count)
	var missing_count := maxi(0, safe_final_count - existing_ages.size())
	if missing_count == 0:
		return []
	var max_group_count := maximum_strict_fifth_count(safe_final_count)
	var target_teen_count := max_group_count
	var target_elderly_count := max_group_count
	var existing_teen_count := 0
	var existing_elderly_count := 0
	for age in existing_ages:
		if is_teen(age):
			existing_teen_count += 1
		elif is_elderly(age):
			existing_elderly_count += 1
	var teen_count := mini(missing_count, maxi(0, target_teen_count - existing_teen_count))
	var elderly_count := mini(missing_count - teen_count, maxi(0, target_elderly_count - existing_elderly_count))
	var adult_count := missing_count - teen_count - elderly_count
	var result := _evenly_spaced_ages(teen_count, TEEN_MIN_AGE, TEEN_MAX_AGE)
	result.append_array(_evenly_spaced_ages(elderly_count, ELDERLY_MIN_AGE, ELDERLY_MAX_AGE))
	result.append_array(_evenly_spaced_ages(adult_count, ADULT_MIN_AGE, ADULT_MAX_AGE))
	_tune_standard_deviation(existing_ages, result, teen_count + elderly_count)
	_shuffle(result, rng)
	return result


static func summarize(ages: Array[int]) -> Dictionary:
	var teen_count := 0
	var elderly_count := 0
	var total_age := 0
	for age in ages:
		total_age += age
		if is_teen(age):
			teen_count += 1
		elif is_elderly(age):
			elderly_count += 1
	var average_age := float(total_age) / float(ages.size()) if not ages.is_empty() else 0.0
	var variance := 0.0
	for age in ages:
		variance += pow(float(age) - average_age, 2.0)
	variance = variance / float(ages.size()) if not ages.is_empty() else 0.0
	return {
		"population_count": ages.size(),
		"average_age": average_age,
		"standard_deviation": sqrt(variance),
		"teen_count": teen_count,
		"elderly_count": elderly_count,
	}


static func _evenly_spaced_ages(count: int, minimum_age: int, maximum_age: int) -> Array[int]:
	var result: Array[int] = []
	if count <= 0:
		return result
	for index in range(count):
		var quantile := (float(index) + 0.5) / float(count)
		result.append(roundi(lerpf(float(minimum_age), float(maximum_age), quantile)))
	return result


static func _tune_standard_deviation(existing_ages: Array[int], generated_ages: Array[int], generated_adult_start: int) -> void:
	var population_count := existing_ages.size() + generated_ages.size()
	var generated_adult_count := generated_ages.size() - generated_adult_start
	if population_count <= 1 or generated_adult_count <= 0:
		return
	var total := 0.0
	var total_squared := 0.0
	for age in existing_ages:
		total += float(age)
		total_squared += float(age * age)
	for age in generated_ages:
		total += float(age)
		total_squared += float(age * age)
	for _iteration in range(generated_adult_count * 2):
		var best_error := absf(_standard_deviation_from_totals(total, total_squared, population_count) - TARGET_STANDARD_DEVIATION)
		var best_index := -1
		var best_age := 0
		var best_total := total
		var best_total_squared := total_squared
		for generated_index in range(generated_adult_start, generated_ages.size()):
			var current_age := generated_ages[generated_index]
			for candidate_age in STANDARD_DEVIATION_TUNING_AGES:
				var candidate_total := total - float(current_age) + float(candidate_age)
				var candidate_total_squared := total_squared - float(current_age * current_age) + float(candidate_age * candidate_age)
				var candidate_error := absf(_standard_deviation_from_totals(candidate_total, candidate_total_squared, population_count) - TARGET_STANDARD_DEVIATION)
				if candidate_error < best_error - 0.000001:
					best_error = candidate_error
					best_index = generated_index
					best_age = candidate_age
					best_total = candidate_total
					best_total_squared = candidate_total_squared
		if best_index < 0:
			break
		generated_ages[best_index] = best_age
		total = best_total
		total_squared = best_total_squared
		if best_error <= 0.25:
			break


static func _standard_deviation_from_totals(total: float, total_squared: float, count: int) -> float:
	if count <= 0:
		return 0.0
	var mean := total / float(count)
	return sqrt(maxf(0.0, total_squared / float(count) - mean * mean))


static func _shuffle(values: Array[int], rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var value := values[index]
		values[index] = values[swap_index]
		values[swap_index] = value
