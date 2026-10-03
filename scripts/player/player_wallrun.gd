class_name PlayerWallrun
extends Node

## Бег по стене (wallrun) игрока: детекция стены боковыми лучами, вход/выход,
## физика бега вдоль стены и прыжок со стены во время wallrun.
## Обычный wall-jump (без wallrun) и общий счётчик прыжков от стены остаются в Player.handle_jump.

# Настройки механики Wallrun
@export var wallrun_min_speed: float = 5.0
@export var wallrun_speed: float = 11.0
@export var wallrun_max_duration: float = 1.2
@export var wallrun_jump_vertical_boost: float = 0.7
@export var wallrun_jump_horizontal_boost: float = 8.0

var is_wallrunning: bool = false
var wallrun_side: float = 0.0 # -1.0 = стена слева, 1.0 = стена справа
var wallrun_timer: float = 0.0
var wallrun_normal: Vector3 = Vector3.ZERO
var wallrun_cooldown: float = 0.0
var last_wallrun_normal: Vector3 = Vector3.ZERO
var wallrun_exhausted: bool = false

var player: Player
var left_wall_ray: RayCast3D
var right_wall_ray: RayCast3D

func setup(p: Player) -> void:
	player = p
	left_wall_ray = player.get_node_or_null("LeftWallRay")
	right_wall_ray = player.get_node_or_null("RightWallRay")
	is_wallrunning = false
	wallrun_side = 0.0
	wallrun_timer = 0.0
	wallrun_cooldown = 0.0
	last_wallrun_normal = Vector3.ZERO
	wallrun_exhausted = false

func tick_cooldown(delta: float) -> void:
	if wallrun_cooldown > 0.0:
		wallrun_cooldown -= delta

## Проверка входа в wallrun и принудительный выход при дэше/слэме.
## Вызывается из Player._physics_process до обработки приседа, гравитации и прыжка.
func update_entry_and_exit() -> void:
	var skills = player.skills
	# Проверка условий входа в wallrun
	if not player.is_on_floor() and not is_wallrunning and not skills.is_dashing and not skills.is_slamming and wallrun_cooldown <= 0.0:
		if player.current_horiz_speed >= wallrun_min_speed:
			var wall_info = check_wallrun_wall()
			if wall_info.found:
				var is_same_wall = wallrun_exhausted and (wall_info.normal.dot(last_wallrun_normal) > 0.7)
				if not is_same_wall:
					var vel_h = Vector3(player.velocity.x, 0, player.velocity.z).normalized()
					# Игрок движется в сторону стены или вдоль неё (не от неё)
					if vel_h.dot(wall_info.normal) < 0.2:
						start_wallrun(wall_info.normal, wall_info.side)

	# Если во время wallrun активирован дэш или слэм — выходим из wallrun
	if is_wallrunning and (skills.is_dashing or skills.is_slamming):
		end_wallrun()

## Сброс wallrun при приземлении на пол (вызывается после move_and_slide)
func on_landed() -> void:
	if is_wallrunning:
		end_wallrun()
	wallrun_exhausted = false
	last_wallrun_normal = Vector3.ZERO

func check_wallrun_wall() -> Dictionary:
	var result = { "found": false, "normal": Vector3.ZERO, "side": 0.0 }

	if left_wall_ray:
		left_wall_ray.force_raycast_update()
		if left_wall_ray.is_colliding():
			var n = left_wall_ray.get_collision_normal()
			if abs(n.y) < 0.25:
				result.found = true
				result.normal = n
				result.side = -1.0
				return result

	if right_wall_ray:
		right_wall_ray.force_raycast_update()
		if right_wall_ray.is_colliding():
			var n = right_wall_ray.get_collision_normal()
			if abs(n.y) < 0.25:
				result.found = true
				result.normal = n
				result.side = 1.0
				return result

	if player.is_on_wall():
		var n = player.get_wall_normal()
		if abs(n.y) < 0.25:
			var side_dot = (-n).dot(player.transform.basis.x)
			var side = 1.0 if side_dot > 0.0 else -1.0
			result.found = true
			result.normal = n
			result.side = side
			return result

	return result

func start_wallrun(normal: Vector3, side: float):
	is_wallrunning = true
	wallrun_side = side
	wallrun_normal = normal
	wallrun_timer = 0.0
	player.wall_jump_count = 0
	wallrun_exhausted = false
	player.coyote_timer = 0.0

	# Срезаем падение вниз при входе в wallrun
	if player.velocity.y < 0.0:
		player.velocity.y = 0.0
	elif player.velocity.y > 2.5:
		player.velocity.y = 2.5

func end_wallrun():
	if not is_wallrunning:
		return
	last_wallrun_normal = wallrun_normal
	wallrun_exhausted = true
	is_wallrunning = false
	wallrun_side = 0.0
	wallrun_timer = 0.0
	wallrun_cooldown = 0.2

func process_wallrun_physics(delta: float, input_dir: Vector2):
	wallrun_timer += delta

	# Если игрок жмет "назад" (S), прекращаем wallrun
	if input_dir.y > 0.5:
		end_wallrun()
		return

	# Проверяем, что стена всё ещё рядом или истекло максимальное время
	var wall_info = check_wallrun_wall()
	if not wall_info.found or wallrun_timer >= wallrun_max_duration:
		end_wallrun()
		return

	wallrun_normal = wall_info.normal
	wallrun_side = wall_info.side

	# Направление взгляда игрока в горизонтальной плоскости
	var forward = -player.transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.001:
		forward = forward.normalized()
	else:
		forward = -Vector3.FORWARD

	# Касательная к стене
	var wall_tangent = (forward - wallrun_normal * forward.dot(wallrun_normal)).normalized()

	# Если игрок отвернулся от стены слишком сильно (> 75 градусов)
	if wall_tangent.dot(forward) < 0.25:
		end_wallrun()
		return

	# Поддерживаем и разгоняем скорость вдоль стены вплоть до общего потолка скорости (14.5..25.0 м/с)
	var cur_horiz = Vector2(player.velocity.x, player.velocity.z).length()
	var max_cap = player.get_current_max_speed()
	var run_speed = clamp(max(cur_horiz, wallrun_speed) + delta * 2.0, wallrun_speed, max_cap)

	var move_vel = wall_tangent * run_speed

	# Небольшой прижим к стене (0.8 м/с), предотвращающий случайный отрыв
	player.velocity.x = move_vel.x - wallrun_normal.x * 0.8
	player.velocity.z = move_vel.z - wallrun_normal.z * 0.8

	# Постепенное медленное снижение по вертикали во время wallrun,
	# усиливающееся ближе к истечению времени (ощущение ослабевающего зацепа)
	var t_ratio = clamp(wallrun_timer / wallrun_max_duration, 0.0, 1.0)
	var slip_accel = lerp(player.gravity * 0.12, player.gravity * 1.5, t_ratio * t_ratio)
	player.velocity.y -= slip_accel * delta

## Пологий прыжок из состояния wallrun:
## умеренный вертикальный импульс + сохранение набранного импульса вперед + отталкивание от стены.
## Завершает wallrun и возвращает нормаль стены (для учёта повторного прыжка от той же стены).
func jump_off_wall(cap: float) -> Vector3:
	var forward = -player.transform.basis.z
	forward.y = 0.0
	var wall_tangent = (forward - wallrun_normal * forward.dot(wallrun_normal)).normalized()
	var cur_speed = Vector2(player.velocity.x, player.velocity.z).length()

	player.velocity.y = Player.JUMP_VELOCITY * wallrun_jump_vertical_boost
	var jump_horiz = (wallrun_normal * wallrun_jump_horizontal_boost) + (wall_tangent * max(cur_speed, wallrun_speed) * 1.05)
	var jump_h_len = jump_horiz.length()
	if jump_h_len > cap:
		jump_horiz = jump_horiz.normalized() * cap
	player.velocity.x = jump_horiz.x
	player.velocity.z = jump_horiz.z

	player.head.add_recoil(0.08, 0.0)
	end_wallrun()
	return wallrun_normal
