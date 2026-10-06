class_name Sector
extends Node3D

## Сектор уровня: группа врагов, которые появляются, когда игрок входит в зону сектора.
## В редакторе враги расставляются дочерними узлами сектора (одна волна) или дочерними узлами
## узлов-волн (любой Node3D с врагами внутри) — это точки спавна. При входе сектора в дерево враги
## снимаются со сцены (до своего _ready) и хранятся как шаблоны: до активации сектора их не существует.
## Порядок волн: сначала враги прямо в секторе, затем узлы-волны по порядку. Следующая волна
## появляется, когда зачищена предыдущая. Сектор зачищен, когда убит последний враг последней волны.
##
## Спавн: на точке врага играет EnemySpawnEffect, сам враг создаётся через spawn_delay — до этого
## его нет в сцене, урона он не наносит и получить его нельзя.
##
## Охотник (EnemyHunter) — необязательная угроза: в условие зачистки и счётчик оставшихся не входит,
## погоню не получает (просыпается сам на 140+ BPM). Переживший зачистку Охотник остаётся на уровне.

signal activated
signal wave_started(index: int)
signal enemy_killed
signal cleared

enum SectorState { DORMANT, ACTIVE, CLEARED }

## Зона входа игрока. Если не задана — первый дочерний Area3D.
@export var zone: Area3D
## Время от начала эффекта спавна до появления врага (с)
@export var spawn_delay: float = 0.6
## Шаг между спавнами врагов одной волны (с)
@export var spawn_stagger: float = 0.04
## Враг ниже дна зоны на столько метров считается выпавшим с уровня: убирается и засчитывается убийством
@export var fall_limit: float = 20.0

# После сброса перекрытие зоны устарело: игрока уже перенесли на чекпоинт, а физика ещё помнит его
# в зоне до следующего шага — без паузы сектор тут же активировался бы снова
const RESET_ACTIVATION_BLOCK_FRAMES: int = 3

var state: SectorState = SectorState.DORMANT
var current_wave: int = -1

# Волна: { "parent": Node, "templates": Array } — шаблоны с настройками из редактора, вне дерева
var _waves: Array = []
# Живые враги сектора: текущая волна и Охотники, пережившие свои волны
var _alive: Array = []
# Шаблоны врагов текущей волны, чей спавн уже начат, но враг ещё не создан
var _pending: Array = []
# Эффекты спавна в процессе — сброс сектора убирает их вместе с отложенными спавнами
var _effects: Array = []
# Поколение спавна: сброс сектора увеличивает его, и отложенные спавны прошлого поколения отменяются
var _spawn_generation: int = 0
var _captured: bool = false
var _kill_y: float = -INF
var _activation_block_frames: int = 0

func _enter_tree() -> void:
	# Враги снимаются до своего _ready: в шаблонах только настройки из редактора, без компонентов,
	# которые враги создают в рантайме, и без побочных эффектов _ready
	if _captured:
		return
	_captured = true
	var direct = _take_enemies(self)
	if not direct.is_empty():
		_waves.append({ "parent": self, "templates": direct })
	for child in get_children():
		if child is Area3D:
			continue
		var group = _take_enemies(child)
		if not group.is_empty():
			_waves.append({ "parent": child, "templates": group })

func _take_enemies(parent: Node) -> Array:
	var taken: Array = []
	for c in parent.get_children():
		if c is EnemyBase:
			parent.remove_child(c)
			taken.append(c)
	return taken

func _ready() -> void:
	if not zone:
		for child in get_children():
			if child is Area3D:
				zone = child
				break
	_kill_y = _get_zone_bottom() - fall_limit

func _get_zone_bottom() -> float:
	if not zone:
		return global_position.y
	var bottom: float = zone.global_position.y
	for c in zone.get_children():
		if c is CollisionShape3D and c.shape is BoxShape3D:
			bottom = minf(bottom, c.global_position.y - c.shape.size.y * 0.5)
	return bottom

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for wave in _waves:
			for t in wave.templates:
				if is_instance_valid(t):
					t.free()

func _physics_process(_delta: float) -> void:
	match state:
		SectorState.DORMANT:
			if _activation_block_frames > 0:
				_activation_block_frames -= 1
				return
			var player = _get_player()
			if zone and is_instance_valid(player) and not player.is_dead and zone.overlaps_body(player):
				_activate()
		SectorState.ACTIVE:
			_update_alive()
			_update_wave_progress()
		SectorState.CLEARED:
			# Охотник, переживший зачистку, — его смерть всё равно идёт в статистику
			_update_alive()

func _get_player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

func _activate() -> void:
	state = SectorState.ACTIVE
	GameTypes.debug_log(&"enemy", "[SECTOR %s] Activated (%d wave(s))" % [name, _waves.size()])
	activated.emit()
	if _waves.is_empty():
		_finish()
		return
	_start_wave(0)

func _start_wave(index: int) -> void:
	current_wave = index
	var wave: Dictionary = _waves[index]
	var generation = _spawn_generation
	for i in range(wave.templates.size()):
		var t = wave.templates[i]
		_pending.append(t)
		var delay: float = i * spawn_stagger
		if delay <= 0.0:
			_begin_spawn(t, wave.parent, generation)
		else:
			get_tree().create_timer(delay, false, true).timeout.connect(_begin_spawn.bind(t, wave.parent, generation))
	AudioManager.play_sound("flask_splash")
	GameTypes.debug_log(&"enemy", "[SECTOR %s] Wave %d started (%d enemies)" % [name, index + 1, wave.templates.size()])
	wave_started.emit(index)

func _begin_spawn(template: Node, parent: Node3D, generation: int) -> void:
	if generation != _spawn_generation:
		return
	var fx = EnemySpawnEffect.new()
	var root = get_tree().current_scene if get_tree().current_scene else self
	root.add_child(fx)
	fx.global_position = parent.global_transform * template.position
	fx.play(spawn_delay)
	_effects = _effects.filter(func(f): return is_instance_valid(f))
	_effects.append(fx)
	get_tree().create_timer(spawn_delay, false, true).timeout.connect(_finish_spawn.bind(template, parent, generation))

func _finish_spawn(template: Node, parent: Node3D, generation: int) -> void:
	if generation != _spawn_generation:
		return
	_pending.erase(template)
	var e = template.duplicate()
	# Враг появляется в секторе, где уже стоит игрок: погоня с момента появления и до смерти
	e.persistent_aggro = _is_required(e)
	parent.add_child(e)
	_alive.append(e)
	if _is_required(e):
		var player = _get_player()
		if is_instance_valid(player) and not player.is_dead:
			e.start_chase(player)

## Обязательный враг: входит в условие зачистки и счётчик оставшихся. Охотник — нет.
func _is_required(e: Node) -> bool:
	return not (e is EnemyHunter)

func _update_alive() -> void:
	for i in range(_alive.size() - 1, -1, -1):
		var e = _alive[i]
		if not is_instance_valid(e) or e.current_state == e.State.DEAD:
			_alive.remove_at(i)
			enemy_killed.emit()
		elif e.global_position.y < _kill_y:
			# Выбит за пределы уровня (под пол, за стены) — падает бесконечно и не умрёт сам
			GameTypes.debug_log(&"enemy", "[SECTOR %s] %s fell out of the level at %s — removed" % [name, e.name, e.global_position])
			_alive.remove_at(i)
			e.queue_free()
			enemy_killed.emit()

func _update_wave_progress() -> void:
	if not _pending.is_empty() or get_remaining_count() > 0:
		return
	if current_wave + 1 < _waves.size():
		_start_wave(current_wave + 1)
	else:
		_finish()

func _finish() -> void:
	state = SectorState.CLEARED
	GameTypes.debug_log(&"enemy", "[SECTOR %s] Cleared" % name)
	cleared.emit()

## Сброс незачищенного сектора после смерти игрока: живые враги сектора и начатые спавны убираются,
## волны начнутся с первой при следующем входе в зону — тем же спавном.
func reset_sector() -> void:
	# Зачищенный остаётся зачищенным (вместе с выжившим Охотником), спящий и так в исходном состоянии
	if state != SectorState.ACTIVE:
		return
	_spawn_generation += 1
	for e in _alive:
		if is_instance_valid(e):
			e.queue_free()
	for fx in _effects:
		if is_instance_valid(fx):
			fx.queue_free()
	_alive.clear()
	_pending.clear()
	_effects.clear()
	state = SectorState.DORMANT
	current_wave = -1
	_activation_block_frames = RESET_ACTIVATION_BLOCK_FRAMES

func is_cleared() -> bool:
	return state == SectorState.CLEARED

func is_active() -> bool:
	return state == SectorState.ACTIVE

## Сколько обязательных врагов осталось в текущей волне, включая ещё появляющихся
func get_remaining_count() -> int:
	var count: int = 0
	for e in _alive:
		if is_instance_valid(e) and e.current_state != e.State.DEAD and _is_required(e):
			count += 1
	for t in _pending:
		if _is_required(t):
			count += 1
	return count

func get_wave_count() -> int:
	return _waves.size()
