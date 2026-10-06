extends Node

## Глобальный менеджер состояния игры (Autoload singleton).
## Отвечает за жизненный цикл игры (PLAYING, GAME_OVER, LEVEL_COMPLETE), реакцию на системные события и перезапуск уровней.
## Игрок регистрируется через register_player(); решение о Game Over принимается здесь по сигналу died игрока.
## Уровень (LevelController) регистрируется через register_level(): тогда смерть ведёт к возрождению
## на последнем чекпоинте, а перезапуск уровня с начала — отдельное действие restart_level().
## На уровне здесь же собирается статистика для экрана конца уровня.

signal game_over_triggered
signal player_respawned
signal level_completed(stats: Dictionary)
## Отладочные полоски HP над врагами переключены (клавиша H, действие debug_toggle_hp_bars)
signal enemy_health_bars_toggled(bars_visible: bool)

enum State {
	PLAYING,
	GAME_OVER,
	LEVEL_COMPLETE
}

var current_state: State = State.PLAYING
var player: Node = null
var level: Node = null

# Статистика уровня (сбрасывается в register_level)
var level_time: float = 0.0       # время прохождения; идёт только пока игрок жив (без экрана смерти)
var kills: int = 0
var damage_taken: int = 0
var overdrive_time: float = 0.0   # время в тире OVERDRIVE
var deaths: int = 0
var _last_health: int = -1

## Отладка: полоски HP над врагами. По умолчанию выключены — компонент полоски у врагов тогда не
## создаётся вообще. Состояние живёт в автозагрузке, поэтому держится всю сессию (и после перезапуска сцены).
var show_enemy_health_bars: bool = false
func _ready():
	# GameManager должен обрабатывать сигналы и ввод даже при возможной паузе дерева сцен
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if not is_level_active() or current_state != State.PLAYING:
		return
	level_time += delta
	if is_instance_valid(player) and "bpm_system" in player and is_instance_valid(player.bpm_system):
		if player.bpm_system.get_bpm_tier() == GameTypes.BPMTier.OVERDRIVE:
			overdrive_time += delta

func _input(event: InputEvent):
	if event.is_action_pressed("debug_toggle_hp_bars") and not event.is_echo():
		get_viewport().set_input_as_handled()
		show_enemy_health_bars = not show_enemy_health_bars
		GameTypes.debug_log(&"enemy", "[DEBUG] Enemy HP bars: %s (H)" % ("ON" if show_enemy_health_bars else "OFF"))
		enemy_health_bars_toggled.emit(show_enemy_health_bars)
		return
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R):
		return
	# R на экране смерти — возрождение на чекпоинте (или перезапуск сцены вне уровня);
	# R на экране конца уровня — пройти уровень заново
	if current_state == State.GAME_OVER:
		get_viewport().set_input_as_handled()
		restart_game()
	elif current_state == State.LEVEL_COMPLETE:
		get_viewport().set_input_as_handled()
		restart_level()

## Подписка на смерть и здоровье игрока. Вызывается игроком из _ready() (в том числе после перезагрузки сцены).
func register_player(p: Node) -> void:
	player = p
	if p.has_signal("died") and not p.died.is_connected(_on_player_died):
		p.died.connect(_on_player_died)
	if p.has_signal("health_changed") and not p.health_changed.is_connected(_on_player_health_changed):
		p.health_changed.connect(_on_player_health_changed)
	_last_health = p.health if "health" in p else -1

## Регистрация уровня. Вызывается LevelController из _ready() (в том числе после перезагрузки сцены).
func register_level(l: Node) -> void:
	level = l
	current_state = State.PLAYING
	level_time = 0.0
	kills = 0
	damage_taken = 0
	overdrive_time = 0.0
	deaths = 0

func is_level_active() -> bool:
	return is_instance_valid(level)

## Убийство врага на уровне (сообщает LevelController)
func record_kill() -> void:
	if is_level_active():
		kills += 1

func _on_player_health_changed(current: int, _maximum: int) -> void:
	if is_level_active() and _last_health >= 0 and current < _last_health:
		damage_taken += _last_health - current
	_last_health = current

func _on_player_died():
	if is_level_active():
		deaths += 1
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

## Конец уровня (LevelExit): засчитывается, только если все секторы зачищены.
## Ставит игру на паузу и отдаёт статистику с буквой рейтинга экрану конца уровня.
func complete_level() -> void:
	if not is_level_active() or current_state != State.PLAYING:
		return
	if level.has_method("all_sectors_cleared") and not level.all_sectors_cleared():
		return
	current_state = State.LEVEL_COMPLETE
	var stats: Dictionary = {
		"time": level_time,
		"kills": kills,
		"damage_taken": damage_taken,
		"overdrive_time": overdrive_time,
		"overdrive_fraction": overdrive_time / max(level_time, 0.001),
		"deaths": deaths
	}
	stats["rank"] = level.compute_rank(stats) if level.has_method("compute_rank") else "-"
	GameTypes.debug_log(&"player", "[LEVEL] Complete: %s" % str(stats))
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true
	level_completed.emit(stats)
