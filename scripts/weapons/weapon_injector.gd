class_name WeaponInjector
extends WeaponBase

## Инъектор (Слот 3): Шприцемёт / токсичное биооружие.
## ЛКМ: Очередь из 3 физических дротиков (интервал 0.07с) с наложением стакающегося яда DoT (3.0с, 3 тика).
## Дротики (ноябрь 2026): DART_SPEED плюс скорость игрока, лёгкая дуга (DART_GRAVITY). Дротик, упавший в лужу
## крови, отравляет её на POOL_POISON_TIME — лужа травит врагов в ней (BloodPool.poison).
## ПКМ: Раздутие врага кровью (inflate, кулдаун 4.5с), вызывающее мощный АОЕ-взрыв при гибели цели.

const ALT_COOLDOWN: float = 4.5
const BURST_COUNT: int = 3
const BURST_INTERVAL: float = 0.07
const DART_SPEED: float = 90.0
const DART_GRAVITY: float = 6.0
const DART_LIFETIME: float = 1.2
const POOL_POISON_TIME: float = 8.0

func _init() -> void:
	if not data:
		data = preload("res://scripts/weapons/data/injector.tres")

## Основной огонь (ЛКМ): очередь из 3 дротиков
func fire() -> void:
	if not data:
		return
		
	fire_timer = data.fire_rate
	_fire_injector_burst()

func _fire_injector_burst() -> void:
	is_bursting = true
	var head = _get_head()
	
	for i in range(BURST_COUNT):
		if not is_inside_tree():
			break
		if weapon_manager and weapon_manager.current_weapon_index != slot_index:
			break
		var player = _get_player()
		if player is Player and player.is_dead:
			break
		if head:
			head.add_recoil(data.cam_shake, data.weapon_kick)
			head.trigger_muzzle_flash(false)
		AudioManager.play_sound("injector_shot")
		
		var inherit: Vector3 = player.velocity if player is Player else Vector3.ZERO
		_fire_projectile(_get_shot_direction(0.045), DART_SPEED, false, DART_LIFETIME, DART_GRAVITY, inherit)
		
		if i < BURST_COUNT - 1:
			await get_tree().create_timer(BURST_INTERVAL).timeout
			
	is_bursting = false

## Попадание дротика: по врагу — урон и яд (общие правила), мимо — отравление лужи крови в точке падения
func on_projectile_hit(projectile: PlayerProjectile, hit: Dictionary) -> bool:
	var dir: Vector3 = projectile.velocity.normalized()
	var target: Node = _deal_hit(hit.collider, hit.position, dir, projectile.is_alt)
	if not is_instance_valid(target):
		TracerPool.spawn_tracer(hit.position - dir * 0.3, hit.position, projectile.style)
		for pool in get_tree().get_nodes_in_group("blood_pool"):
			if pool is BloodPool and pool.contains_point(hit.position):
				pool.poison(POOL_POISON_TIME)
	return false

## Наложение яда DoT при попадании дротика
func _on_hit_target(target: Node, _hit_pos: Vector3, _is_headshot: bool, _is_alt: bool) -> void:
	if target.has_method("apply_poison_dot"):
		target.apply_poison_dot(3.0, 3, 0.5)

## Альтернативный огонь (ПКМ): статусное раздутие врага
func alt_fire(_has_infinite_ammo: bool = false) -> void:
	if alt_timer > 0.0:
		return
	_fire_injector_inflate()

func _fire_injector_inflate() -> void:
	alt_timer = ALT_COOLDOWN
	var head = _get_head()
	if head:
		head.add_recoil(0.07, 0.26)
		head.trigger_muzzle_flash(false)
	AudioManager.play_sound("injector_shot")
	
	var start_pos = _get_muzzle_position()
	var ray = head.get_aim_raycast(0.0) if head else null
	var hit_pos = ray.to_global(ray.target_position) if ray else Vector3.ZERO
	
	if ray and ray.is_colliding():
		hit_pos = ray.get_collision_point()
		var hit = ray.get_collider()
		if hit != null:
			var target: Node = null
			if hit.is_in_group("enemy_head") or hit.name == "HeadHitbox":
				if hit.has_meta("enemy"):
					target = hit.get_meta("enemy")
				elif hit.get_parent():
					target = hit.get_parent()
			else:
				target = GameTypes.resolve_damageable(hit)
				
			if target != null and target.has_method("inflate"):
				target.inflate()
				
	TracerPool.spawn_tracer(start_pos, hit_pos, &"inflate")

func get_alt_hud_suffix(_has_infinite_ammo: bool = false) -> String:
	if alt_timer > 0.0:
		return " (RMB %.1fs)" % alt_timer
	return ""

func get_alt_charge() -> float:
	return 1.0 - clampf(alt_timer / ALT_COOLDOWN, 0.0, 1.0)
