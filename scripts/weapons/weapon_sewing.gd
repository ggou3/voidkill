class_name WeaponSewing
extends WeaponBase

## Швейная машина (Слот 4): скорострельный игольник, механика «Нить» (ноябрь 2026).
## ЛКМ: физические иглы (6 HP, 10 выстр/с, NEEDLE_SPEED + скорость игрока). Игла застревает во враге
## (add_needle — синергии и разлёт при смерти прежние) или в стене и остаётся там видимой STUCK_TIME.
## Игла, попавшая в роевика со стеной за спиной (до PIN_RANGE), пришпиливает его к стене на PIN_TIME.
## ПКМ «Стежок» (кулдаун alt_cooldown): все застрявшие иглы выдёргиваются. Врага с иглами рвёт на игрока
## (урон alt_damage за иглу, рывок растёт с числом игл, окно удара о стену и о других врагов), иглы летят
## к игроку, прошивая всё на пути (урон RETURN_DAMAGE_SCALE от обычного), и возвращаются в магазин.
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
	var target: Node = _deal_hit(hit.collider, hit.position, dir, false)
	if is_instance_valid(target):
		if target is EnemySwarm and _try_pin(target, hit.position, dir, projectile):
			return false
		_stick(projectile, target as Node3D, hit.position)
	else:
		_stick(projectile, null, hit.position)
	return false

## Роевик со стеной за спиной: игла прибивает его к стене и застревает в стене
func _try_pin(swarm: Node, hit_pos: Vector3, dir: Vector3, projectile: PlayerProjectile) -> bool:
	if not swarm.has_method("pin_to") or ("health" in swarm and swarm.health <= 0):
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
	var flat_dir := Vector3(dir.x, 0.0, dir.z).normalized()
	var pin_pos: Vector3 = wall.position - flat_dir * 0.35
	pin_pos.y = swarm.global_position.y
	swarm.pin_to(pin_pos, PIN_TIME)
	_stick(projectile, null, wall.position)
	return true

func _stick(projectile: PlayerProjectile, host: Node3D, pos: Vector3) -> void:
	projectile.stick(host, pos, STUCK_TIME)
	_stuck.append(projectile)
	_prune_stuck()
	while _stuck.size() > MAX_STUCK:
		_stuck.pop_front().deactivate()

func _prune_stuck() -> void:
	for i in range(_stuck.size() - 1, -1, -1):
		var p: PlayerProjectile = _stuck[i]
		if not is_instance_valid(p) or not p.is_stuck() or p.weapon != self:
			_stuck.remove_at(i)

## Альтернативный огонь (ПКМ): «Стежок» — выдернуть все застрявшие иглы
func alt_fire(_has_infinite_ammo: bool = false) -> void:
	if alt_timer > 0.0:
		return
	_prune_stuck()
	if _stuck.is_empty():
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

	# Хозяева игл: сколько игл в каждом
	var hosts: Dictionary = {} # instance_id -> [враг, число игл]
	for p in _stuck:
		var host: Node3D = p.get_host()
		if host:
			var key: int = host.get_instance_id()
			if hosts.has(key):
				hosts[key][1] += 1
			else:
				hosts[key] = [host, 1]
	for entry in hosts.values():
		_yank_host(entry[0], entry[1], player)

	var count: int = _stuck.size()
	for p in _stuck:
		p.home_to(player, RETURN_SPEED, RETURN_LIFETIME)
	_stuck.clear()
	GameTypes.debug_log(&"weapon", "[SEWING MACHINE] Stitch! Needles recalled: %d | Hosts yanked: %d" % [count, hosts.size()])

## Рывок врага с иглами к игроку: урон за каждую иглу, толчок к игроку, окно удара о стену и о врагов
func _yank_host(host: Node3D, needles: int, player: Player) -> void:
	if not is_instance_valid(host) or not host.has_method("take_damage") or ("health" in host and host.health <= 0):
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

## Игла вернулась — патрон обратно в магазин
func on_projectile_homed(_projectile: PlayerProjectile) -> void:
	if not weapon_manager or not data:
		return
	weapon_manager.ammos[slot_index] = mini(weapon_manager.ammos[slot_index] + 1, data.max_ammo)
	weapon_manager.ammo_changed.emit(slot_index, weapon_manager.ammos[slot_index], data.max_ammo)

func get_alt_hud_suffix(_has_infinite_ammo: bool = false) -> String:
	if alt_timer > 0.0:
		return " (RMB %.1fs)" % alt_timer
	_prune_stuck()
	if not _stuck.is_empty():
		return " (STITCH %d)" % _stuck.size()
	return ""
