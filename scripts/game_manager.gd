extends Node

## Глобальный менеджер состояния игры (Autoload singleton).
## Отвечает за жизненный цикл игры (PLAYING, GAME_OVER), реакцию на системные события и перезапуск уровней.
## Игрок регистрируется через register_player(); решение о Game Over принимается здесь по сигналу died игрока.
## Уровень (LevelController) регистрируется через register_level(): тогда смерть ведёт к возрождению
## на последнем чекпоинте, а перезапуск уровня с начала — отдельное действие restart_level().

signal game_over_triggered
signal player_respawned

enum State {
	PLAYING,
	GAME_OVER
}

var current_state: State = State.PLAYING
var player: Node = null
var level: Node = null

func _ready():
	# GameManager должен обрабатывать сигналы и ввод даже при возможной паузе дерева сцен
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent):
	# При состоянии GAME_OVER слушаем нажатие клавиши R: возрождение на чекпоинте (или перезапуск сцены вне уровня)
	if current_state == State.GAME_OVER:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_R:
				get_viewport().set_input_as_handled()
				restart_game()

## Подписка на смерть игрока. Вызывается игроком из _ready() (в том числе после перезагрузки сцены).
func register_player(p: Node) -> void:
	player = p
	if p.has_signal("died") and not p.died.is_connected(_on_player_died):
		p.died.connect(_on_player_died)

## Регистрация уровня. Вызывается LevelController из _ready() (в том числе после перезагрузки сцены).
func register_level(l: Node) -> void:
	level = l
	current_state = State.PLAYING
	kills = 0

func is_level_active() -> bool:
	return is_instance_valid(level)

## Статистика уровня: убийство врага (сообщает LevelController)
var kills: int = 0

func record_kill() -> void:
	if is_level_active():
		kills += 1

func _on_player_died():
	trigger_game_over()

func trigger_game_over():
	if current_state == State.GAME_OVER:
		return
	current_state = State.GAME_OVER
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	game_over_triggered.emit()

## Продолжить после смерти: на уровне — возрождение на последнем чекпоинте, вне уровня — перезапуск сцены
func restart_game():
	if is_level_active() and is_instance_valid(player):
		current_state = State.PLAYING
		level.respawn_player(player)
		player_respawned.emit()
	else:
		restart_level()

## Перезапуск уровня (сцены) с самого начала
func restart_level():
	current_state = State.PLAYING
	level = null
	get_tree().paused = false
	get_tree().reload_current_scene()
