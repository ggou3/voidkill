extends Node

## Глобальный менеджер состояния игры (Autoload singleton).
## Отвечает за жизненный цикл игры (PLAYING, GAME_OVER), реакцию на системные события и перезапуск уровней.

signal game_over_triggered
# signal score_changed(new_score: int)
# signal wave_started(wave_number: int)
# signal game_paused(is_paused: bool)

enum State {
	PLAYING,
	GAME_OVER
	# PAUSED
}

var current_state: State = State.PLAYING

# --- Заготовки под будущее расширение ---
# var score: int = 0
# var current_wave: int = 0
# var enemies_alive: int = 0

func _ready():
	# GameManager должен обрабатывать сигналы и ввод даже при возможной паузе дерева сцен
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent):
	# При состоянии GAME_OVER слушаем нажатие клавиши R для перезапуска
	if current_state == State.GAME_OVER:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_R:
				get_viewport().set_input_as_handled()
				restart_game()

func trigger_game_over():
	if current_state == State.GAME_OVER:
		return
	current_state = State.GAME_OVER
	game_over_triggered.emit()

func restart_game():
	current_state = State.PLAYING
	# Сброс статистики сессии для будущих систем:
	# reset_session_stats()
	get_tree().reload_current_scene()

# ==========================================
# Заготовки методов для будущего расширения:
# ==========================================

# func add_score(amount: int):
# 	score += amount
# 	score_changed.emit(score)

# func start_next_wave():
# 	current_wave += 1
# 	wave_started.emit(current_wave)

# func toggle_pause():
# 	var paused = not get_tree().paused
# 	get_tree().paused = paused
# 	current_state = State.PAUSED if paused else State.PLAYING
# 	game_paused.emit(paused)
