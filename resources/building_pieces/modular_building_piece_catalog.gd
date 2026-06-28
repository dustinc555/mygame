extends Resource

class_name ModularBuildingPieceCatalog

@export var catalog_id := ""
@export var display_name := ""
@export var pieces: Array = []


func get_piece(piece_id: String) -> Resource:
	for piece in pieces:
		if piece != null and piece.piece_id == piece_id:
			return piece
	return null


func get_pieces_in_category(category: String) -> Array:
	var result: Array = []
	for piece in pieces:
		if piece != null and piece.category == category:
			result.append(piece)
	return result
