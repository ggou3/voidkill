class_name LevelController
extends Node3D

## Корень уровня: находит секторы и кровавые перегородки среди потомков, ведёт чекпоинт и
## регистрирует уровень в GameManager. Смерть на уровне — возрождение на последнем чекпоинте
## вместо перезагрузки сцены.
##
## Чекпоинт: на старте — позиция игрока; после обрушения перегородки — её точка возрождения.
## При возрождении незачищенный (активный) сектор сбрасывается, зачищенные остаются зачищенными.

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
