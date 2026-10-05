class_name LevelController
extends Node3D

## Корень уровня: находит секторы и кровавые перегородки среди потомков, ведёт чекпоинт и
## регистрирует уровень в GameManager. Смерть на уровне — возрождение на последнем чекпоинте
## вместо перезагрузки сцены.
##
## Чекпоинт: на старте — позиция игрока; после обрушения перегородки — её точка возрождения.
## При возрождении незачищенный (активный) сектор сбрасывается, зачищенные остаются зачищенными.

## Рейтинг конца уровня. Каждый показатель даёт оценку 0..4 (D, C, B, A, S) по порогам [S, A, B, C];
## итог — округлённое среднее трёх оценок минус штраф за каждую смерть.
## Время прохождения (с): не больше порога — оценка этого порога
@export var rank_time_thresholds: Array[float] = [150.0, 210.0, 300.0, 420.0]
## Полученный урон (HP): не больше порога
@export var rank_damage_thresholds: Array[float] = [60.0, 150.0, 280.0, 450.0]
## Доля времени в OVERDRIVE (0..1): не меньше порога
@export var rank_overdrive_thresholds: Array[float] = [0.35, 0.22, 0.12, 0.05]
## Сколько ступеней рейтинга снимает каждая смерть
@export var rank_penalty_per_death: int = 1

const RANK_LETTERS: Array[String] = ["D", "C", "B", "A", "S"]

var sectors: Array[Sector] = []
var barriers: Array[BloodBarrier] = []
var checkpoint: Transform3D

func _ready() -> void:
	_collect(self)
	for s in sectors:
		s.enemy_killed.connect(_on_enemy_killed)
	for b in barriers:
		b.collapsed.connect(_on_barrier_collapsed.bind(b))
	var player = get_tree().get_first_node_in_group("player")
	checkpoint = player.global_transform if player is Node3D else global_transform
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.register_level(self)

func _collect(node: Node) -> void:
	for child in node.get_children():
		if child is Sector:
			sectors.append(child)
		elif child is BloodBarrier:
			barriers.append(child)
		_collect(child)

func _on_barrier_collapsed(barrier: BloodBarrier) -> void:
	checkpoint = barrier.get_checkpoint_transform()
	GameTypes.debug_log(&"player", "[LEVEL] Checkpoint moved to barrier %s" % barrier.name)

func _on_enemy_killed() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.record_kill()

func respawn_player(player: Node) -> void:
	for s in sectors:
		s.reset_sector()
	if player is Player:
		player.respawn(checkpoint)

func all_sectors_cleared() -> bool:
	for s in sectors:
		if not s.is_cleared():
			return false
	return true

func compute_rank(stats: Dictionary) -> String:
	var time_grade = _grade_lower_is_better(stats.get("time", 0.0), rank_time_thresholds)
	var damage_grade = _grade_lower_is_better(float(stats.get("damage_taken", 0)), rank_damage_thresholds)
	var overdrive_grade = _grade_higher_is_better(stats.get("overdrive_fraction", 0.0), rank_overdrive_thresholds)
	var grade: int = int(round((time_grade + damage_grade + overdrive_grade) / 3.0))
	grade -= int(stats.get("deaths", 0)) * rank_penalty_per_death
	return RANK_LETTERS[clampi(grade, 0, RANK_LETTERS.size() - 1)]

func _grade_lower_is_better(value: float, thresholds: Array[float]) -> int:
	for i in range(thresholds.size()):
		if value <= thresholds[i]:
			return 4 - i
	return 0

func _grade_higher_is_better(value: float, thresholds: Array[float]) -> int:
	for i in range(thresholds.size()):
		if value >= thresholds[i]:
			return 4 - i
	return 0
