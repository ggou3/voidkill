class_name Sector
extends Node3D

## Сектор уровня: группа врагов, которая спит, пока игрок не войдёт в зону сектора.
## Враги — дочерние узлы сектора (одна волна) или дочерние узлы узлов-волн (любой Node3D
## с врагами внутри). Порядок волн: сначала враги прямо в секторе, затем узлы-волны по порядку.
## Следующая волна просыпается, когда зачищена предыдущая. Сектор зачищен, когда убит последний
## враг последней волны.
##
## Спящий враг не меняет своё поведение: он отключён через process_mode (тело и зоны выпадают из
## физики — нет обнаружения игрока и попаданий) и временно убран из группы "enemy" (его не находят
## эффекты по радиусу). Поэтому враги следующего сектора не агрятся сквозь перегородку.

signal activated
signal wave_started(index: int)
signal enemy_killed
signal cleared

enum SectorState { DORMANT, ACTIVE, CLEARED }

## Зона входа игрока. Если не задана — первый дочерний Area3D.
@export var zone: Area3D

var state: SectorState = SectorState.DORMANT
var current_wave: int = -1

# Волна: { "parent": Node, "templates": Array[Node], "enemies": Array } — enemies[i] == null, когда враг убит
var _waves: Array = []
var _captured: bool = false

func _enter_tree() -> void:
	# Шаблоны для сброса снимаются до _ready врагов: чистые копии с настройками из редактора,
	# без компонентов, которые враги создают в рантайме
	if _captured:
		return
	_captured = true
	var direct: Array = []
	for child in get_children():
		if child is EnemyBase:
			direct.append(child)
	if not direct.is_empty():
		_waves.append(_make_wave(self, direct))
	for child in get_children():
		if child is EnemyBase or child is Area3D:
			continue
		var group: Array = []
		for c in child.get_children():
			if c is EnemyBase:
				group.append(c)
		if not group.is_empty():
			_waves.append(_make_wave(child, group))

func _make_wave(parent: Node, enemies: Array) -> Dictionary:
	var templates: Array = []
	for e in enemies:
		templates.append(e.duplicate())
	return { "parent": parent, "templates": templates, "enemies": enemies.duplicate() }

func _ready() -> void:
	if not zone:
		for child in get_children():
			if child is Area3D:
				zone = child
				break
	for wave in _waves:
		for e in wave.enemies:
			_set_dormant(e, true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for wave in _waves:
			for t in wave.templates:
				if is_instance_valid(t):
					t.free()

func _physics_process(_delta: float) -> void:
	match state:
		SectorState.DORMANT:
			var player = get_tree().get_first_node_in_group("player")
			if zone and is_instance_valid(player) and not ("is_dead" in player and player.is_dead) and zone.overlaps_body(player):
				_activate(player)
		SectorState.ACTIVE:
			_update_current_wave()

func _activate(player: Node3D) -> void:
	state = SectorState.ACTIVE
	GameTypes.debug_log(&"enemy", "[SECTOR %s] Activated (%d wave(s))" % [name, _waves.size()])
	activated.emit()
	if _waves.is_empty():
		_finish()
		return
	_start_wave(0, player)

func _start_wave(index: int, player: Node3D) -> void:
	current_wave = index
	for e in _waves[index].enemies:
		if is_instance_valid(e):
			_set_dormant(e, false)
			e.start_chase(player)
	GameTypes.debug_log(&"enemy", "[SECTOR %s] Wave %d started" % [name, index + 1])
	wave_started.emit(index)

func _update_current_wave() -> void:
	var wave: Dictionary = _waves[current_wave]
	var alive: int = 0
	for i in range(wave.enemies.size()):
		var e = wave.enemies[i]
		if e == null:
			continue
		if not is_instance_valid(e) or e.current_state == e.State.DEAD:
			wave.enemies[i] = null
			enemy_killed.emit()
		else:
			alive += 1
	if alive > 0:
		return
	if current_wave + 1 < _waves.size():
		_start_wave(current_wave + 1, get_tree().get_first_node_in_group("player"))
	else:
		_finish()

func _finish() -> void:
	state = SectorState.CLEARED
	GameTypes.debug_log(&"enemy", "[SECTOR %s] Cleared" % name)
	cleared.emit()

## Сброс незачищенного сектора после смерти игрока: враги возвращаются на исходные позиции
## с полным HP и засыпают, волны начнутся с первой при следующем входе в зону.
func reset_sector() -> void:
	# Зачищенный остаётся зачищенным, спящий и так в исходном состоянии
	if state != SectorState.ACTIVE:
		return
	for wave in _waves:
		for e in wave.enemies:
			if e != null and is_instance_valid(e):
				_set_dormant(e, true)
				e.queue_free()
		var fresh: Array = []
		for t in wave.templates:
			var e = t.duplicate()
			wave.parent.add_child(e)
			_set_dormant(e, true)
			fresh.append(e)
		wave.enemies = fresh
	state = SectorState.DORMANT
	current_wave = -1

func is_cleared() -> bool:
	return state == SectorState.CLEARED

func _set_dormant(e: Node, dormant: bool) -> void:
	if dormant:
		e.process_mode = Node.PROCESS_MODE_DISABLED
		if e.is_in_group("enemy"):
			e.remove_from_group("enemy")
	else:
		e.process_mode = Node.PROCESS_MODE_INHERIT
		e.add_to_group("enemy")
