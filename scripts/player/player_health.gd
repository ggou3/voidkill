class_name PlayerHealth
extends Node

## Здоровье игрока: HP, получение урона (со снижением от BPM), лечение, смерть и связь с GameManager.
## Сигналы ретранслируются через Player (health_changed, died), поэтому подписчики (HUD) работают с Player.

signal health_changed(current: int, maximum: int)
signal died

var max_health: int = 100
var health: int = 100
var is_dead: bool = false

var player: Player
var game_manager: Node

func setup(p: Player) -> void:
	player = p
	is_dead = false
	health = max_health
	health_changed.emit(health, max_health)
	game_manager = get_node_or_null("/root/GameManager")
	var gm = _get_game_manager()
	if gm and not gm.game_over_triggered.is_connected(_on_game_over_triggered):
		gm.game_over_triggered.connect(_on_game_over_triggered)

func _get_game_manager() -> Node:
	if not game_manager and is_inside_tree():
		game_manager = get_node_or_null("/root/GameManager")
	return game_manager

func take_damage(amount: int, knockback_vector: Vector3 = Vector3.ZERO, _hit_pos: Vector3 = Vector3.ZERO):
	if is_dead or amount <= 0:
		return
	var reduction = player.bpm_system.get_bpm_damage_reduction()
	var final_damage = max(1, int(round(float(amount) * (1.0 - reduction))))
	health = max(0, health - final_damage)
	health_changed.emit(health, max_health)
	if player.bpm_system is BPMSystem:
		player.bpm_system.drop_bpm_on_damage()
	if player.head:
		player.head.add_recoil(0.25, 0.0)
	if knockback_vector != Vector3.ZERO:
		player.velocity += knockback_vector
	if health <= 0:
		die()

func heal(amount: int, is_melee_bonus: bool = false):
	if is_dead or amount <= 0:
		return
	var old_health = health
	health = min(max_health, health + amount)
	var _gained = health - old_health
	health_changed.emit(health, max_health)
	AudioManager.play_sound("player_heal")
	_spawn_heal_feedback(amount, is_melee_bonus)

func _spawn_heal_feedback(heal_amount: int, is_melee_bonus: bool = false):
	var label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 6
	label.outline_modulate = Color.BLACK

	if is_melee_bonus:
		label.text = "+%d HP (MELEE SIPHON!)" % heal_amount
		label.modulate = Color(0.2, 1.0, 0.4, 1.0)
		label.font_size = 32
	else:
		label.text = "+%d HP" % heal_amount
		label.modulate = Color(0.3, 0.95, 0.5, 1.0)
		label.font_size = 26

	var scene_root = get_tree().current_scene if get_tree().current_scene else player.get_parent()
	if not scene_root:
		return
	scene_root.add_child(label)

	var start_p = player.global_position + Vector3(randf_range(-0.2, 0.2), 1.2, randf_range(-0.2, 0.2))
	label.global_position = start_p

	var target_p = start_p + Vector3(0.0, 0.85, 0.0)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(label, "global_position", target_p, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)

## Смерть игрока. Сброс состояния движения выполняет Player в обработчике сигнала died.
func die():
	if is_dead:
		return
	is_dead = true
	health = 0
	health_changed.emit(0, max_health)
	died.emit()

	var gm = _get_game_manager()
	if gm:
		gm.trigger_game_over()

func _on_game_over_triggered():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func restart_game():
	var gm = _get_game_manager()
	if gm:
		gm.restart_game()
	else:
		get_tree().reload_current_scene()
