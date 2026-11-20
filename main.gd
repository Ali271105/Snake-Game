extends Node2D

# --- Settings you can tweak ---
const CELL := 20                  # size of one grid square in pixels
const GRID := Vector2i(30, 20)    # grid size (30 x 20 cells = 600 x 400 px)
const START_DELAY := 0.12         # seconds between moves (smaller = faster)
const SAVE_PATH := "user://snake_save.cfg"   # where the high score is stored

# --- Game state ---
enum State { TITLE, PLAYING, GAME_OVER }
var state := State.TITLE

var snake: Array[Vector2i] = []
var direction := Vector2i.RIGHT
var next_direction := Vector2i.RIGHT
var food := Vector2i.ZERO
var score := 0
var high_score := 0
var new_record := false
var muted := false
var timer := Timer.new()

# --- Sprites ---
var head_tex: Texture2D
var body_tex: Texture2D
var apple_tex: Texture2D

# --- Audio players ---
var music_player: AudioStreamPlayer
var eat_player: AudioStreamPlayer
var start_player: AudioStreamPlayer
var over_player: AudioStreamPlayer


func _ready() -> void:
	randomize()
	head_tex = load("res://head.svg")
	body_tex = load("res://body.svg")
	apple_tex = load("res://apple.svg")

	music_player = _make_player("res://music.wav", -12.0)
	eat_player = _make_player("res://eat.wav", -6.0)
	start_player = _make_player("res://start.wav", -6.0)
	over_player = _make_player("res://gameover.wav", -4.0)
	# The music clip is short, so start it again every time it finishes
	music_player.finished.connect(func(): if state == State.PLAYING: music_player.play())

	timer.timeout.connect(_step)
	add_child(timer)

	_load_high_score()
	_setup_board()  # shows a snake behind the title screen
	queue_redraw()


func _make_player(path: String, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	player.volume_db = volume_db
	add_child(player)
	return player


# ---------- High score saving ----------

func _load_high_score() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_score = cfg.get_value("score", "high", 0)


func _save_high_score() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("score", "high", high_score)
	cfg.save(SAVE_PATH)


# ---------- Starting and ending a round ----------

func _setup_board() -> void:
	snake = [Vector2i(5, 10), Vector2i(4, 10), Vector2i(3, 10)]
	direction = Vector2i.RIGHT
	next_direction = Vector2i.RIGHT
	score = 0
	new_record = false
	_place_food()


func _start_game() -> void:
	_setup_board()
	state = State.PLAYING
	timer.wait_time = START_DELAY
	timer.start()
	start_player.play()
	music_player.play()
	queue_redraw()


func _end_game() -> void:
	state = State.GAME_OVER
	timer.stop()
	music_player.stop()
	over_player.play()
	if score > high_score:
		high_score = score
		new_record = true
		_save_high_score()
	queue_redraw()


func _go_to_title() -> void:
	state = State.TITLE
	_setup_board()
	queue_redraw()


func _place_food() -> void:
	# Keep picking random cells until we find one the snake isn't on
	while true:
		food = Vector2i(randi() % GRID.x, randi() % GRID.y)
		if not snake.has(food):
			return


# ---------- Input ----------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	# Mute / unmute works on every screen
	if event.keycode == KEY_M:
		muted = not muted
		AudioServer.set_bus_mute(0, muted)
		queue_redraw()
		return

	var confirm: bool = event.keycode == KEY_SPACE or event.keycode == KEY_ENTER

	match state:
		State.TITLE:
			if confirm:
				_start_game()
		State.GAME_OVER:
			if confirm:
				_start_game()
			elif event.keycode == KEY_ESCAPE:
				_go_to_title()
		State.PLAYING:
			# Change direction, but never allow a 180-degree turn into yourself
			match event.keycode:
				KEY_UP, KEY_W:
					if direction != Vector2i.DOWN:
						next_direction = Vector2i.UP
				KEY_DOWN, KEY_S:
					if direction != Vector2i.UP:
						next_direction = Vector2i.DOWN
				KEY_LEFT, KEY_A:
					if direction != Vector2i.RIGHT:
						next_direction = Vector2i.LEFT
				KEY_RIGHT, KEY_D:
					if direction != Vector2i.LEFT:
						next_direction = Vector2i.RIGHT


# ---------- Game loop ----------

func _step() -> void:
	direction = next_direction
	var new_head := snake[0] + direction

	# Hit a wall?
	if new_head.x < 0 or new_head.y < 0 or new_head.x >= GRID.x or new_head.y >= GRID.y:
		_end_game()
		return

	# Hit yourself? (the tail will move away this step, so ignore the last cell)
	if snake.slice(0, snake.size() - 1).has(new_head):
		_end_game()
		return

	snake.push_front(new_head)

	if new_head == food:
		# Ate food: keep the tail (snake grows), score, speed up a little
		score += 1
		eat_player.play()
		timer.wait_time = max(0.05, timer.wait_time - 0.003)
		_place_food()
	else:
		snake.pop_back()

	queue_redraw()


# ---------- Drawing ----------

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var board := Vector2(GRID * CELL)

	# Background: checkerboard "grass"
	for x in GRID.x:
		for y in GRID.y:
			var grass := Color(0.55, 0.78, 0.35) if (x + y) % 2 == 0 else Color(0.5, 0.73, 0.31)
			draw_rect(Rect2(Vector2(x * CELL, y * CELL), Vector2(CELL, CELL)), grass)

	# Food
	draw_texture(apple_tex, Vector2(food * CELL))

	# Snake body (draw from the tail up so the head ends up on top)
	for i in range(snake.size() - 1, 0, -1):
		draw_texture(body_tex, Vector2(snake[i] * CELL))

	# Snake head: rotate the sprite to face the direction we're moving
	var half := Vector2(CELL, CELL) / 2.0
	var head_center := Vector2(snake[0] * CELL) + half
	draw_set_transform(head_center, Vector2(direction).angle(), Vector2.ONE)
	draw_texture(head_tex, -half)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)  # reset so text isn't rotated

	# HUD (score, best score, mute indicator)
	draw_string(font, Vector2(8, 20), "Score: %d    Best: %d" % [score, high_score], HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	if muted:
		draw_string(font, Vector2(0, 20), "MUTED", HORIZONTAL_ALIGNMENT_RIGHT, board.x - 8, 16, Color(1, 0.8, 0.3))

	match state:
		State.TITLE:
			draw_rect(Rect2(Vector2.ZERO, board), Color(0, 0, 0, 0.6))
			draw_string(font, Vector2(0, 130), "SNAKE", HORIZONTAL_ALIGNMENT_CENTER, board.x, 64, Color(0.4, 1.0, 0.4))
			draw_string(font, Vector2(0, 175), "Best score: %d" % high_score, HORIZONTAL_ALIGNMENT_CENTER, board.x, 22, Color(1, 0.9, 0.3))
			draw_string(font, Vector2(0, 250), "Press Space to start", HORIZONTAL_ALIGNMENT_CENTER, board.x, 24)
			draw_string(font, Vector2(0, 285), "Arrow keys or WASD to move  -  M to mute", HORIZONTAL_ALIGNMENT_CENTER, board.x, 15, Color(0.8, 0.8, 0.8))
		State.GAME_OVER:
			draw_rect(Rect2(Vector2.ZERO, board), Color(0, 0, 0, 0.5))
			draw_string(font, Vector2(0, 140), "GAME OVER", HORIZONTAL_ALIGNMENT_CENTER, board.x, 48)
			if new_record:
				draw_string(font, Vector2(0, 185), "New high score: %d!" % score, HORIZONTAL_ALIGNMENT_CENTER, board.x, 24, Color(1, 0.9, 0.3))
			else:
				draw_string(font, Vector2(0, 185), "Score: %d   Best: %d" % [score, high_score], HORIZONTAL_ALIGNMENT_CENTER, board.x, 22)
			draw_string(font, Vector2(0, 250), "Space: play again    Esc: title screen", HORIZONTAL_ALIGNMENT_CENTER, board.x, 18)
