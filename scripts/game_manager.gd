extends Node

## Глобальный менеджер состояния игры (Autoload singleton).
## Отвечает за жизненный цикл игры (PLAYING, GAME_OVER), реакцию на системные события и перезапуск уровней.
## Игрок регистрируется через register_player(); решение о Game Over принимается здесь по сигналу died игрока.

signal game_over_triggered

enum State {
	PLAYING,
	GAME_OVER
}

var current_state: State = State.PLAYING

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

## Подписка на смерть игрока. Вызывается игроком из _ready() (в том числе после перезагрузки сцены).
func register_player(player: Node) -> void:
	if player.has_signal("died") and not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)

func _on_player_died():
	trigger_game_over()

func trigger_game_over():
	if current_state == State.GAME_OVER:
		return
	current_state = State.GAME_OVER
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	game_over_triggered.emit()

func restart_game():
	current_state = State.PLAYING
	get_tree().reload_current_scene()
