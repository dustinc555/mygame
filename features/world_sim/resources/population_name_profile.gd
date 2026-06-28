extends Resource

class_name PopulationNameProfile

const VISUAL_BODY_TYPE_MALE := 2
const VISUAL_BODY_TYPE_FEMALE := 3

const DEFAULT_MASCULINE_NAMES := [
	"Abel", "Abner", "Alden", "Alec", "Anton", "Arlen", "Asa", "Ashwin", "Atlas", "Bastian",
	"Beck", "Ben", "Bram", "Cade", "Cain", "Caleb", "Callum", "Cassian", "Cedar", "Cole",
	"Corin", "Dane", "Dax", "Dean", "Declan", "Eamon", "Eli", "Elias", "Emmett", "Enoch",
	"Ezra", "Felix", "Finn", "Gabe", "Gareth", "Gideon", "Grant", "Griff", "Hale", "Harlan",
	"Hayes", "Hector", "Ian", "Ira", "Isaac", "Isham", "Jace", "Jasper", "Joel", "Jonas",
	"Jude", "Kade", "Kane", "Keir", "Kellan", "Lars", "Leo", "Levi", "Lucan", "Luther",
	"Mal", "Malcolm", "Marcus", "Marek", "Milo", "Nate", "Noah", "Nolan", "Oren", "Orson",
	"Owen", "Pax", "Pike", "Quentin", "Reed", "Ren", "Rhys", "Ronan", "Rowan", "Saul",
	"Seth", "Silas", "Simon", "Soren", "Tate", "Theo", "Tobias", "Tomas", "Vance", "Vaughn",
	"Wade", "Walt", "Wes", "Wyatt", "Yves", "Zane", "Zed", "Zeke", "Ansel", "Boone",
	"Cyrus", "Dorian", "Evan", "Galen", "Harvey", "Ilan", "Jory", "Kieran", "Linus", "Micah",
	"Nico", "Otis", "Percy", "Quill", "Rafe", "Stellan", "Trent", "Ulric", "Willem", "Yori",
]

const DEFAULT_FEMININE_NAMES := [
	"Ada", "Adela", "Alia", "Alma", "Anika", "Anna", "Asha", "Bea", "Blythe", "Bria",
	"Calla", "Celia", "Cora", "Dahlia", "Della", "Dina", "Eden", "Elise", "Elowen", "Esme",
	"Eva", "Faye", "Flora", "Freya", "Gemma", "Grace", "Greta", "Gwen", "Hana", "Hazel",
	"Ida", "Iris", "Ivy", "Jane", "Jessa", "Joy", "June", "Kaia", "Kira", "Lena",
	"Lila", "Liora", "Livia", "Lydia", "Mara", "Maren", "Mina", "Mira", "Nadia", "Naomi",
	"Nell", "Nia", "Nora", "Nyra", "Olive", "Orla", "Petra", "Pia", "Quinn", "Rhea",
	"Rina", "Rose", "Ruth", "Sable", "Selah", "Sera", "Sylvie", "Talia", "Tessa", "Thea",
	"Una", "Vera", "Vesper", "Willa", "Wren", "Yara", "Zara", "Zia", "Amara", "Bryn",
	"Clara", "Dove", "Ember", "Fia", "Hester", "Isla", "Juno", "Keira", "Lark", "Mae",
	"Nola", "Opal", "Pearl", "Raisa", "Sasha", "Tova", "Veda", "Winna", "Yvette", "Zola",
	"Ari", "Bela", "Carys", "Dara", "Elin", "Farah", "Gia", "Helena", "Iona", "Lyra",
]

const DEFAULT_NEUTRAL_NAMES := [
	"Alex", "Arden", "Ash", "Avery", "Blake", "Blue", "Briar", "Casey", "Cory", "Drew",
	"Ellis", "Ember", "Gray", "Harper", "Hollis", "Jules", "Kit", "Lane", "Linden", "Logan",
	"Marlowe", "Morgan", "Noa", "Oak", "Parker", "Quinn", "Reese", "Remy", "Riley", "River",
	"Robin", "Rowan", "Sage", "Sam", "Scout", "Shay", "Sky", "Sloan", "Sunny", "Vale",
	"Wynn", "Ari", "Bowie", "Cam", "Devon", "Echo", "Finch", "Haven", "Indigo", "Joss",
	"Kai", "Lake", "Marin", "North", "Onyx", "Poe", "Rain", "Shiloh", "Teal", "Winter",
	"Zen", "Bay", "Cedar", "Dale", "Ever", "Fenn", "Gale", "Hero", "Ivory", "Journey",
	"Kestrel", "Lux", "Mica", "Nova", "Ocean", "Riven", "Sorrel", "True", "Vesper", "West",
]

const DEFAULT_NICKNAMES := [
	"Ace", "Badger", "Bear", "Black", "Blade", "Bolt", "Bones", "Boot", "Brick", "Buck",
	"Burn", "Buzzard", "Chalk", "Cinder", "Copper", "Coyote", "Cricket", "Crow", "Crowbar", "Cutter",
	"Diesel", "Dice", "Dog", "Dust", "Echo", "Fever", "Finch", "Fizz", "Flint", "Flintlock",
	"Flicker", "Fox", "Fuse", "Gear", "Ghost", "Glass", "Glitch", "Grease", "Grinder", "Grit",
	"Grub", "Gutter", "Hawk", "Hex", "Hook", "Hound", "Howl", "Hush", "Jackal", "Junk",
	"Junker", "Knives", "Lead", "Lock", "Lucky", "Mercy", "Moth", "Mutt", "Nail", "Needle",
	"Onion", "Patch", "Pick", "Pike", "Pipe", "Rattle", "Rat", "Raven", "Red", "Rivet",
	"Radio", "Roach", "Rook", "Rope", "Rust", "Sawbones", "Scab", "Scar", "Scout", "Scrap",
	"Shade", "Shale", "Shank", "Shiv", "Signal", "Silver", "Snipe", "Snake", "Sneak", "Soot",
	"Sparky", "Spider", "Sprocket", "Static", "Stealth", "Stitch", "Stitcher", "Stone", "Switch", "Thorn",
	"Tin", "Torch", "Trouble", "Twitch", "Vex", "Vulture", "Watch", "Whisper", "Wire", "Wolf",
	"Wrench", "Ashcan", "Barb", "Barker", "Bash", "Bite", "Blister", "Bloom", "Boil", "Brass",
	"Bruise", "Bucket", "Bull", "Candle", "Cart", "Chain", "Chisel", "Clank", "Claw", "Clever",
	"Coal", "Crank", "Crate", "Crook", "Dagger", "Dirt", "Doc", "Drift", "Drop", "Duster",
	"Fang", "Fiddle", "Flare", "Flea", "Fluke", "Frost", "Hinge", "Hitch", "Kettle", "Knot",
	"Latch", "Mallet", "Marl", "Mask", "Mender", "Mire", "Moss", "Nettle", "Nine", "Pale",
	"Penny", "Piston", "Plank", "Quarry", "Rag", "Razor", "Rebar", "Riddle", "Rim", "Rivet",
	"Root", "Saw", "Scratch", "Seven", "Shear", "Shell", "Smoke", "Snare", "Spark", "Spike",
	"Spoke", "Spoon", "Squire", "Strap", "Tack", "Tallow", "Tangle", "Tarp", "Thimble", "Three",
	"Tick", "Tooth", "Track", "Trap", "Vine", "Wasp", "Wheel", "Whip", "Wick", "Worm",
]

@export var profile_id := ""
@export var display_name := "Population Names"
@export_range(0.0, 100.0, 0.1) var body_specific_weight := 70.0
@export_range(0.0, 100.0, 0.1) var neutral_weight := 15.0
@export_range(0.0, 100.0, 0.1) var nickname_weight := 15.0
@export_range(0.0, 1.0, 0.01) var duplicate_name_chance := 0.02
@export_range(1, 100, 1) var unique_retry_count := 32
@export var masculine_names: PackedStringArray = PackedStringArray()
@export var feminine_names: PackedStringArray = PackedStringArray()
@export var neutral_names: PackedStringArray = PackedStringArray()
@export var nickname_names: PackedStringArray = PackedStringArray()


func generate_name(body_type: int, rng: RandomNumberGenerator, used_names: Dictionary = {}) -> String:
	var last_candidate := ""
	for attempt in range(maxi(1, unique_retry_count)):
		var candidate := _pick_candidate(body_type, rng)
		if candidate.is_empty():
			continue
		last_candidate = candidate
		if not used_names.has(_name_key(candidate)):
			return candidate
	for candidate in _all_candidates_for_body(body_type):
		if not used_names.has(_name_key(candidate)):
			return candidate
	if not last_candidate.is_empty() and rng.randf() <= duplicate_name_chance:
		return last_candidate
	return last_candidate if not last_candidate.is_empty() else "Wanderer"


func contains_name(name: String) -> bool:
	return _all_name_keys().has(_name_key(name))


func _pick_candidate(body_type: int, rng: RandomNumberGenerator) -> String:
	var body_names := _body_names(body_type)
	var neutral := _neutral_names()
	var nicknames := _nickname_names()
	var total_weight := 0.0
	if not body_names.is_empty() and body_specific_weight > 0.0:
		total_weight += body_specific_weight
	if not neutral.is_empty() and neutral_weight > 0.0:
		total_weight += neutral_weight
	if not nicknames.is_empty() and nickname_weight > 0.0:
		total_weight += nickname_weight
	if total_weight <= 0.0:
		return ""
	var roll := rng.randf_range(0.0, total_weight)
	if not body_names.is_empty() and body_specific_weight > 0.0:
		roll -= body_specific_weight
		if roll <= 0.0:
			return body_names[rng.randi_range(0, body_names.size() - 1)]
	if not neutral.is_empty() and neutral_weight > 0.0:
		roll -= neutral_weight
		if roll <= 0.0:
			return neutral[rng.randi_range(0, neutral.size() - 1)]
	return nicknames[rng.randi_range(0, nicknames.size() - 1)] if not nicknames.is_empty() and nickname_weight > 0.0 else ""


func _all_candidates_for_body(body_type: int) -> PackedStringArray:
	var result := PackedStringArray()
	for name in _body_names(body_type):
		result.append(name)
	for name in _neutral_names():
		result.append(name)
	for name in _nickname_names():
		result.append(name)
	return result


func _all_name_keys() -> Dictionary:
	var result := {}
	for name in _masculine_names():
		result[_name_key(name)] = true
	for name in _feminine_names():
		result[_name_key(name)] = true
	for name in _neutral_names():
		result[_name_key(name)] = true
	for name in _nickname_names():
		result[_name_key(name)] = true
	return result


func _body_names(body_type: int) -> PackedStringArray:
	if body_type == VISUAL_BODY_TYPE_FEMALE:
		return _feminine_names()
	if body_type == VISUAL_BODY_TYPE_MALE:
		return _masculine_names()
	var result := PackedStringArray()
	for name in _masculine_names():
		result.append(name)
	for name in _feminine_names():
		result.append(name)
	return result


func _masculine_names() -> PackedStringArray:
	return masculine_names if not masculine_names.is_empty() else PackedStringArray(DEFAULT_MASCULINE_NAMES)


func _feminine_names() -> PackedStringArray:
	return feminine_names if not feminine_names.is_empty() else PackedStringArray(DEFAULT_FEMININE_NAMES)


func _neutral_names() -> PackedStringArray:
	return neutral_names if not neutral_names.is_empty() else PackedStringArray(DEFAULT_NEUTRAL_NAMES)


func _nickname_names() -> PackedStringArray:
	return nickname_names if not nickname_names.is_empty() else PackedStringArray(DEFAULT_NICKNAMES)


func _name_key(name: String) -> String:
	return name.strip_edges().to_lower()
