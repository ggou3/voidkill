class_name WeaponInjector
extends WeaponBase

## Инъектор (Слот 3): Шприцемёт / токсичное биооружие.
## ЛКМ: Очередь из 3 дротиков (интервал 0.07с) с наложением стакающегося яда DoT (3.0с, 3 тика).
## ПКМ: Раздутие врага кровью (inflate, кулдаун 4.5с), вызывающее мощный АОЕ-взрыв при гибели цели.

const ALT_COOLDOWN: float = 4.5
const BURST_COUNT: int = 3
const BURST_INTERVAL: float = 0.07

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
		if head:
			head.add_recoil(data.cam_shake, data.weapon_kick)
			head.trigger_muzzle_flash(false)
		AudioManager.play_sound("injector_shot")
		
		var aim_dir = head.get_aim_direction() if head else Vector3.FORWARD
		var ray = head.get_aim_raycast(0.045) if head else null
		var hit_pos = ray.to_global(ray.target_position) if ray else Vector3.ZERO
		var collider: Node = null
		if ray and ray.is_colliding():
			hit_pos = ray.get_collision_point()
			collider = ray.get_collider()
			
		_apply_hit(collider, hit_pos, aim_dir, false)
		
		if i < BURST_COUNT - 1:
			await get_tree().create_timer(BURST_INTERVAL).timeout
			
	is_bursting = false

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
