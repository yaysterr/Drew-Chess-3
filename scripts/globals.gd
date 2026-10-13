extends Node

enum PLAYER { ONE, TWO }
enum PLAYER_2_TYPE { 
	HUMAN, AI
}

enum COLORS {
	BLACK, WHITE
}

enum PIECE_TYPES {
	ROOK,
	KNIGHT,
	BISHOP,
	QUEEN,
	KING,
	PAWN
}

enum GAME_MODE {
	PVP,
	PVB
}

# Brief movement descriptions shown in the Card Info panel when a piece is hovered.
const PIECE_MOVE_DESC = {
	PIECE_TYPES.PAWN:   "Moves forward 1 (or 2 from its start square); captures diagonally.",
	PIECE_TYPES.KNIGHT: "Moves in an L-shape; can jump over other pieces.",
	PIECE_TYPES.BISHOP: "Moves any distance diagonally.",
	PIECE_TYPES.ROOK:   "Moves any distance horizontally or vertically.",
	PIECE_TYPES.QUEEN:  "Moves any distance horizontally, vertically, or diagonally.",
	PIECE_TYPES.KING:   "Moves 1 square in any direction; can castle.",
}

const SPRITE_MAPPING = {
	COLORS.BLACK : {
		PIECE_TYPES.ROOK: "res://pieces_new/B-Rook.png",
		PIECE_TYPES.KNIGHT: "res://pieces_new/B-knight.png",
		PIECE_TYPES.BISHOP: "res://pieces_new/B-bishop64x64.png",
		PIECE_TYPES.QUEEN: "res://pieces_new/B-Queen64x64.png",
		PIECE_TYPES.KING: "res://pieces_new/B-king64x64.png",
		PIECE_TYPES.PAWN: "res://pieces_new/B-Pawn.png",
	},
	COLORS.WHITE:{
		PIECE_TYPES.ROOK: "res://pieces_new/W-Rook.png",
		PIECE_TYPES.KNIGHT: "res://pieces_new/W-Knight.png",
		PIECE_TYPES.BISHOP: "res://pieces_new/W-Bishop.png",
		PIECE_TYPES.QUEEN: "res://pieces_new/W-Queen64x64.png.png",
		PIECE_TYPES.KING: "res://pieces_new/W-King64x64.png",
		PIECE_TYPES.PAWN: "res://pieces_new/W-Pawn.png",
	},
}

enum CARD_ID {
	BOUNCE,
	DEVOUR,
	SPRING_HORSE,
	LAND_MINE,
	SACRIFICE,
	YOU_AND_ME,
	REVIVE
}

# Mana cost to revive each piece type with the Revive card. This same number
# is also the Exhausted duration (in turns) applied to the revived piece.
# King and Bishop are intentionally absent — they can never be revived.
const REVIVE_MANA_COST = {
	PIECE_TYPES.PAWN:   1,
	PIECE_TYPES.KNIGHT: 2,
	PIECE_TYPES.ROOK:   3,
	PIECE_TYPES.QUEEN:  4,
}

const CARD_DATA = {
	CARD_ID.BOUNCE: {
		"name": "Bounce",
		"category": "Ascend",
		"cost": 1,
		"desc": "Pick any one of your pieces. Next time it captures, it retreats 2 squares back along its line of attack. If something blocks the 1st square back, it doesn't move at all and that blocker gets bumped back 1 square instead.",
		"art_path": "res://cards/bounce.png",
	},
	CARD_ID.DEVOUR: {
		"name": "Devour",
		"category": "Ascend",
		"cost": 3,
		"desc": "Pick any one of your pieces. Next time it captures another piece, it transforms into that piece's type.",
		"art_path": "res://cards/devour.png",
	},
	CARD_ID.SPRING_HORSE: {
		"name": "Spring Horse",
		"category": "Ascend",
		"cost": 1,
		"desc": "Pick one of your Knights. From now on it can also hop over a piece directly next to it (up/down/left/right), landing one square beyond.",
		"art_path": "res://cards/spring_horse.png",
	},
	CARD_ID.LAND_MINE: {
		"name": "Land Mine",
		"category": "Spell",
		"cost": 1,
		"desc": "Plant a mine on an empty square within 1 square of one of your Pawns. Hidden from everyone — only flickers visible to you every 3rd of your turns. Destroys the next piece, either side, that steps on it.",
		"art_path": "res://cards/land_mine.png",
	},
	CARD_ID.SACRIFICE: {
		"name": "Sacrifice",
		"category": "Spell",
		"cost": 1,
		"desc": "Target any enemy piece (not the King) to destroy. Value 1 target: sacrifice 1 friendly piece of the same type, or any friendly Value-1 piece. Value >1 target: sacrifice 1 friendly piece of the exact same type PLUS 1 friendly Pawn.",
		"art_path": "res://cards/sacrifice.png",
	},
	CARD_ID.YOU_AND_ME: {
		"name": "You and Me",
		"category": "Spell",
		"cost": 2,
		"desc": "Pick the frontmost enemy piece in its file and the frontmost piece of yours in its file. For the next 3 of your turns, those two can only capture each other. Pairing a non-Queen against an enemy Queen costs +2 mana.",
		"art_path": "res://cards/you_and_me.png",
	},
	CARD_ID.REVIVE: {
		"name": "Revive",
		"category": "Spell",
		"cost": 1,
		"desc": "Bring back a friendly piece from your Graveyard (not King or Bishop) next to one of your living, non-Exhausted Bishops. Costs Mana equal to the piece's value (Pawn 1, Knight 2, Rook 3, Queen 4) — the Bishop and the revived piece both become Exhausted for that many turns.",
		"art_path": "res://cards/revive.png",
	},
}

const DECK_COPIES_PER_CARD = 3
const MAX_SKILL_POINTS = 4
const MAX_HAND_SIZE = 4

const INITIAL_PIECE_SET_SINGLE = [
	[PIECE_TYPES.ROOK, 0, 0],
	[PIECE_TYPES.KNIGHT, 1, 0],
	[PIECE_TYPES.BISHOP, 2, 0],
	[PIECE_TYPES.QUEEN, 3, 0],
	[PIECE_TYPES.KING, 4, 0],
	[PIECE_TYPES.BISHOP, 5, 0],
	[PIECE_TYPES.KNIGHT, 6, 0],
	[PIECE_TYPES.ROOK, 7, 0],
	[PIECE_TYPES.PAWN, 0, 1],
	[PIECE_TYPES.PAWN, 1, 1],
	[PIECE_TYPES.PAWN, 2, 1],
	[PIECE_TYPES.PAWN, 3, 1],
	[PIECE_TYPES.PAWN, 4, 1],
	[PIECE_TYPES.PAWN, 5, 1],
	[PIECE_TYPES.PAWN, 6, 1],
	[PIECE_TYPES.PAWN, 7, 1]
]

# Stored between scenes
var selected_color: COLORS = COLORS.WHITE
var game_mode: GAME_MODE = GAME_MODE.PVB
