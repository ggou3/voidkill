class_name WeaponSewing
extends WeaponBase

## Швейная машина (Слот 4): скорострельный игольник, механика «Нить» (ноябрь 2026).
## ЛКМ: физические иглы (6 HP, 10 выстр/с, NEEDLE_SPEED + скорость игрока). Игла застревает во враге
## (add_needle — синергии прежние) или в стене и остаётся там видимой STUCK_TIME. Враг с иглами умер — иглы
## из него разлетаются во все стороны (burst_from_host). Игла, убившая врага, пролетает сквозь него.
## Игла, попавшая в роевика со стеной за спиной (до PIN_RANGE), пришпиливает его к стене на PIN_TIME.
## ПКМ «Стежок» (кулдаун alt_cooldown): все застрявшие и летящие иглы возвращаются. Врага с иглами рвёт на
## игрока (урон alt_damage за иглу, рывок растёт с числом игл, окно удара о стену и о других врагов), иглы
## летят в дуло, прошивая всё на пути (урон RETURN_DAMAGE_SCALE от обычного). Патронов возврат не даёт.
## Параметры ПКМ (alt_cooldown, alt_damage) — в группе «Альт-огонь» ресурса sewing_machine.tres.

const NEEDLE_SPEED: float = 120.0
const NEEDLE_LIFETIME: float = 1.5
const STUCK_TIME: float = 6.0 # = время жизни метки иглы на враге (StatusEffectComponent)
const MAX_STUCK: int = 40 # застрявших игл одновременно (больше — гаснет самая старая)
const RETURN_SPEED: float = 70.0
const RETURN_LIFETIME: float = 2.5
const RETURN_DAMAGE_SCALE: float = 1.0
const YANK_BASE: float = 8.0 # рывок хозяина к игроку, м/с
const YANK_PER_NEEDLE: float = 3.0
const YANK_MAX: float = 22.0
const YANK_UP: float = 3.0
const YANK_SLAM_WINDOW: float = 0.6 # окно удара о стену/врагов после рывка (как у мили)
const PIN_RANGE: float = 2.5
const PIN_TIME: float = 2.0
## Разлёт игл из умершего врага (StatusEffectComponent.trigger_needle_burst → burst_from_host): застрявшие в нём
## иглы и недостающие до числа меток новые летят во все стороны, долетают примерно до радиуса разлёта ×1.25
const BURST_SPEED: float = 30.0
## Радиус попадания иглы разлёта — допуск прежних мгновенных лучей (NEEDLE_TOLERANCE 0.40 сверх тела):
## с радиусом обычной иглы (0.12) разлёт попадал заметно реже
const BURST_HIT_RADIUS: float = 0.40
## Направление разлёта: случайное по кругу, наклон по вертикали в этих пределах (до нормализации)
const BURST_DIR_Y_MIN: float = -0.15
const BURST_DIR_Y_MAX: float = 0.35
## Доводка: игла, чьё случайное направление отличается от направления на врага меньше конуса, летит в него
const BURST_AIM_CONE: float = 0.61 # рад (~35°)
const BURST_AIM_JITTER: float = 0.08
const BURST_AIM_HEIGHT: float = 0.3 # м над началом координат врага — между корпусом и головой
## Иглы, застрявшие во враге без меток (сами иглы разлёта): при его смерти летят как обычный разлёт
const BURST_FALLBACK_RADIUS: float = 4.0 # = обычный разлёт (StatusEffectComponent.trigger_needle_burst)
const BURST_FALLBACK_DAMAGE: int = 3

var _stuck: Array[PlayerProjectile] = []

func _init() -> void:
	if not data:
		data = preload("res://scripts/weapons/data/sewing_machine.tres")

## Основной огонь (ЛКМ): физическая игла
func fire() -> void:
	if not data:
		return
	fire_timer = data.fire_rate
	var head = _get_head()
	if head:
		head.add_recoil(data.cam_shake, data.weapon_kick)
		head.trigger_muzzle_flash(false)
	AudioManager.play_sound("needle_shot")
	var player := _get_player()
	var inherit: Vector3 = player.velocity if player else Vector3.ZERO
	_fire_projectile(_get_shot_direction(data.spread), NEEDLE_SPEED, false, NEEDLE_LIFETIME, 0.0, inherit)

## Застревание иглы во враге — только у летящих игл (иглы на возврате приходят с is_alt = true)
func _on_hit_target(target: Node, _hit_pos: Vector3, _is_headshot: bool, is_alt: bool) -> void:
	if not is_alt and target.has_method("add_needle"):
		target.add_needle()

func on_projectile_hit(projectile: PlayerProjectile, hit: Dictionary) -> bool:
	var dir: Vector3 = projectile.velocity.normalized()
	if projectile.mode == PlayerProjectile.Mode.HOMING:
		# Возврат: прошивает врагов (каждого один раз за иглу) и проходит сквозь стены
		var resolved: Array = _resolve_hit_target(hit.collider)
		var hit_target: Node = resolved[0]
		if is_instance_valid(hit_target):
			var seen: Dictionary = projectile.payload.get("seen", {})
			var key: int = hit_target.get_instance_id()
			if not seen.has(key):
				seen[key] = true
				projectile.payload["seen"] = seen
				_deal_hit(hit.collider, hit.position, dir, true, RETURN_DAMAGE_SCALE)
		return true
	if projectile.payload.get("burst", false):
		return _on_burst_needle_hit(projectile, hit, dir)
	var target: Node = _deal_hit(hit.collider, hit.position, dir, false)
	if is_instance_valid(target):
		if _is_dead(target):
			return true # убила — летит дальше сквозь труп (застрять в нём — повиснуть в воздухе)
		if target is EnemySwarm and _try_pin(target, hit.position, dir, projectile):
			return false
		_stick(projectile, target as Node3D, hit.position)
	else:
		_stick(projectile, null, hit.position)
	return false

## Разлёт игл из умершего врага host (зовёт StatusEffectComponent.trigger_needle_burst, пока host ещё в
## дереве): застрявшие в нём иглы вылетают из своих точек, недостающие до count — новые из origin. Летят
## во все стороны, доводка на врагов в радиусе — BURST_AIM_CONE. Урон и правила прежние: обычная игла —
## урон первому врагу и застревает в нём; из раздутого (pierce) — прошивает всех с глубиной цепи Инъектора
func burst_from_host(host: Node3D, origin: Vector3, count: int, radius: float, damage: int, pierce: bool, depth: int,
		exclude: Array[RID]) -> void:
	var from_host: Array[PlayerProjectile] = []
	_prune_stuck()
	for p in _stuck:
		if p.get_host() == host:
			from_host.append(p)
	var player := _get_player()
	if not weapon_manager or (player and player.is_dead):
		for p in from_host:
			p.deactivate()
		return
	var targets: Array[Vector3] = _collect_burst_targets(origin, radius, host)
	for i in range(maxi(count, from_host.size())):
		var start: Vector3 = from_host[i].global_position if i < from_host.size() else origin
		var dir: Vector3 = _burst_direction(start, targets)
		_launch_burst_needle(from_host[i] if i < from_host.size() else null, start, dir, radius, damage, pierce, depth, exclude)

## Хозяин застрявшей иглы умер, а разлёта не было (в нём были только иглы разлёта — меток они не ставят):
## игла вылетает как обычный разлёт
func on_projectile_host_died(projectile: PlayerProjectile) -> void:
	var player := _get_player()
	if not weapon_manager or (player and player.is_dead):
		projectile.deactivate()
		return
	var start: Vector3 = projectile.global_position
	var dir: Vector3 = _burst_direction(start, _collect_burst_targets(start, BURST_FALLBACK_RADIUS, null))
	_launch_burst_needle(projectile, start, dir, BURST_FALLBACK_RADIUS, BURST_FALLBACK_DAMAGE, false, -1, [])

## Игла разлёта: reuse — застрявшая игла, которая вылетает заново (null — новая из пула)
func _launch_burst_needle(reuse: PlayerProjectile, origin: Vector3, dir: Vector3, radius: float, damage: int, pierce: bool,
		depth: int, exclude: Array[RID]) -> void:
	var style: StringName = &"needle_blood" if pierce else &"needle"
	var lifetime: float = radius * 1.25 / BURST_SPEED
	var p: PlayerProjectile = reuse
	if p:
		weapon_manager.relaunch_projectile(p, self, origin, dir * BURST_SPEED, style, false, lifetime, 0.0, exclude, BURST_HIT_RADIUS)
	else:
		p = weapon_manager.spawn_projectile_from(self, origin, dir * BURST_SPEED, style, false, lifetime, 0.0, exclude, BURST_HIT_RADIUS)
	if p:
		p.payload = {"burst": true, "damage": damage, "pierce": pierce, "depth": depth, "seen": {}}

## Точки прицела разлёта: живые враги в радиусе от center (кроме умершего хозяина)
func _collect_burst_targets(center: Vector3, radius: float, host: Node) -> Array[Vector3]:
	var targets: Array[Vector3] = []
	if not is_inside_tree():
		return targets
	var radius_sq: float = radius * radius
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == host or not (e is Node3D) or _is_dead(e):
			continue
		if "current_state" in e and e.current_state == e.State.DEAD:
			continue
		var aim: Vector3 = e.global_position + Vector3.UP * BURST_AIM_HEIGHT
		if center.distance_squared_to(aim) <= radius_sq:
			targets.append(aim)
	return targets

## Случайное направление по кругу (чуть вверх/вниз); попало в конус к врагу — доводится на него
func _burst_direction(start: Vector3, targets: Array[Vector3]) -> Vector3:
	var angle: float = randf() * TAU
	var dir := Vector3(cos(angle), randf_range(BURST_DIR_Y_MIN, BURST_DIR_Y_MAX), sin(angle)).normalized()
	var best_angle: float = BURST_AIM_CONE
	var best_dir := Vector3.ZERO
	for aim in targets:
		var to_aim: Vector3 = aim - start
		if to_aim.length_squared() < 0.01:
			continue
		var a: float = dir.angle_to(to_aim)
		if a < best_angle:
			best_angle = a
			best_dir = to_aim.normalized()
	if best_dir != Vector3.ZERO:
		var jitter := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * BURST_AIM_JITTER
		dir = (best_dir + jitter).normalized()
	return dir

func _on_burst_needle_hit(projectile: PlayerProjectile, hit: Dictionary, dir: Vector3) -> bool:
	var target: Node = _resolve_hit_target(hit.collider)[0]
	if is_instance_valid(target) and target.has_method("take_damage"):
		if _is_dead(target):
			return true
		var seen: Dictionary = projectile.payload["seen"]
		var key: int = target.get_instance_id()
		if seen.has(key):
			return true
		seen[key] = true
		var pierce: bool = projectile.payload["pierce"]
		var knock: Vector3 = dir * (2.5 if pierce else 1.5) + Vector3.UP * (0.8 if pierce else 0.5)
		var depth: int = projectile.payload["depth"] if pierce else -1
		target.take_damage(projectile.payload["damage"], knock, hit.position, false, false, false, false, depth, "sewing")
		if pierce or _is_dead(target):
			return true
		_stick(projectile, target as Node3D, hit.position)
		return false
	_stick(projectile, null, hit.position)
	return false

func _is_dead(target: Node) -> bool:
	return "health" in target and target.health <= 0

## Роевик со стеной за спиной: игла прибивает его к стене и застревает в стене
func _try_pin(swarm: Node, hit_pos: Vector3, dir: Vector3, projectile: PlayerProjectile) -> bool:
	if not swarm.has_method("pin_to") or _is_dead(swarm):
		return false
	var space: PhysicsDirectSpaceState3D = swarm.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(hit_pos, hit_pos + dir * PIN_RANGE)
	var exclude: Array[RID] = [swarm.get_rid()]
	var player := _get_player()
	if player:
		exclude.append(player.get_rid())
	query.exclude = exclude
	var wall: Dictionary = space.intersect_ray(query)
	if wall.is_empty() or GameTypes.resolve_enemy(wall.collider) != null:
		return false
	# Только стена: выстрел сверху вниз упирается лучом в пол — к полу рой не прибивается
	if absf(wall.normal.y) >= 0.5:
		return false
	var flat_dir := Vector3(dir.x, 0.0, dir.z).normalized()
	var pin_pos: Vector3 = wall.position - flat_dir * 0.35
	pin_pos.y = swarm.global_position.y
	swarm.pin_to(pin_pos, PIN_TIME)
	_stick(projectile, null, wall.position)
	return true

func _stick(projectile: PlayerProjectile, host: Node3D, pos: Vector3) -> void:
	projectile.stick(host, pos, STUCK_TIME)
	# Снаряд из пула мог погаснуть и застрять снова до очистки списка — второй записи не нужно
	if not _stuck.has(projectile):
		_stuck.append(projectile)
	_prune_stuck()
	while _stuck.size() > MAX_STUCK:
		_stuck.pop_front().deactivate()

func _prune_stuck() -> void:
	for i in range(_stuck.size() - 1, -1, -1):
		var p: PlayerProjectile = _stuck[i]
		if not is_instance_valid(p) or not p.is_stuck() or p.weapon != self:
			_stuck.remove_at(i)

## Иглы, которые «Стежок» вернёт: застрявшие и летящие (ЛКМ и разлёт), кроме уже возвращающихся
func _collect_recallable() -> Array[PlayerProjectile]:
	_prune_stuck()
	var result: Array[PlayerProjectile] = _stuck.duplicate()
	if weapon_manager:
		for p in weapon_manager.get_active_projectiles():
			if p.weapon == self and p.mode == PlayerProjectile.Mode.FLY:
				result.append(p)
	return result

## Альтернативный огонь (ПКМ): «Стежок» — вернуть все застрявшие и летящие иглы
func alt_fire(_has_infinite_ammo: bool = false) -> void:
	if alt_timer > 0.0:
		return
	var needles: Array[PlayerProjectile] = _collect_recallable()
	if needles.is_empty():
		AudioManager.play_sound("dry_fire")
		return
	var player := _get_player()
	if not player:
		return
	alt_timer = data.alt_cooldown
	var head = _get_head()
	if head:
		head.add_recoil(0.06, 0.22)
		head.add_trauma(0.25)
	AudioManager.play_sound("needle_shot")
	AudioManager.play_sound("dash")

	# Хозяева игл: сколько игл в каждом. Иглы разлёта не считаются: меток игл (add_needle) они не ставили
	var hosts: Dictionary = {} # instance_id -> [враг, число игл]
	for p in needles:
		if p.payload.get("burst", false):
			continue
		var host: Node3D = p.get_host()
		if host:
			var key: int = host.get_instance_id()
			if hosts.has(key):
				hosts[key][1] += 1
			else:
				hosts[key] = [host, 1]
	for entry in hosts.values():
		_yank_host(entry[0], entry[1], player)

	# Иглы летят в дуло Швейной (не в центр игрока — тогда они уходили над головой)
	var return_target: Node3D = player
	var return_offset: Vector3 = Vector3.UP * 0.6
	if head and head.smg_model and head.smg_model.get_node_or_null("Muzzle"):
		return_target = head.smg_model.get_node("Muzzle")
		return_offset = Vector3.ZERO
	for p in needles:
		if not p.active:
			continue
		p.payload = {}
		p.home_to(return_target, RETURN_SPEED, RETURN_LIFETIME, return_offset)
	_stuck.clear()
	GameTypes.debug_log(&"weapon", "[SEWING MACHINE] Stitch! Needles recalled: %d | Hosts yanked: %d" % [needles.size(), hosts.size()])

## Рывок врага с иглами к игроку: урон за каждую иглу, толчок к игроку, окно удара о стену и о врагов
func _yank_host(host: Node3D, needles: int, player: Player) -> void:
	if not is_instance_valid(host) or not host.has_method("take_damage") or _is_dead(host):
		return
	var to_player: Vector3 = player.global_position - host.global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.01:
		return
	var force: float = minf(YANK_BASE + YANK_PER_NEEDLE * float(needles), YANK_MAX)
	var knock: Vector3 = to_player.normalized() * force + Vector3.UP * YANK_UP
	if host.has_method("remove_needles"):
		host.remove_needles(needles)
	host.take_damage(data.alt_damage * needles, knock, host.global_position, false, false, false, false, -1, "sewing")
	if host is EnemyGround and host.health > 0:
		host.wall_slam_timer = YANK_SLAM_WINDOW
		host.velocity.x = knock.x
		host.velocity.z = knock.z
		host.wall_slam_source_weapon = "sewing"
		host.wall_slam_source_melee = false
		host.wall_slam_source_shockwave = false

func get_alt_hud_suffix(_has_infinite_ammo: bool = false) -> String:
	if alt_timer > 0.0:
		return " (RMB %.1fs)" % alt_timer
	var recallable: int = _collect_recallable().size()
	if recallable > 0:
		return " (STITCH %d)" % recallable
	return ""

func get_alt_charge() -> float:
	return 1.0 - clampf(alt_timer / maxf(data.alt_cooldown, 0.001), 0.0, 1.0)
