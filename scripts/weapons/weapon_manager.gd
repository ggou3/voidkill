class_name WeaponManager
extends Node

## Менеджер оружия игрока (WeaponManager).
## Управляет переключением активного оружия, боезапасом (ammos), перезарядкой (активной и пассивной).
## Делегирует механику стрельбы экземплярам WeaponBase и оповещает внешние системы через сигналы.

signal weapon_switched(index: int, weapon: WeaponBase)
signal ammo_changed(weapon_index: int, current_ammo: int, max_ammo: int)
signal reload_started(weapon_index: int, duration: float)
signal reload_finished(weapon_index: int)

var current_weapon_index: int = 0
var is_reloading: bool = false
var active_reload_timer: float = 0.0
var passive_reload_timers: Array[float] = [0.0, 0.0, 0.0, 0.0]

var weapons: Array[WeaponBase] = []
var ammos: Array[int] = []
# Клик, вернувший захват курсора, не должен запускать автоогонь, пока ЛКМ не отпущена
var _autofire_blocked: bool = false

## Пул физических снарядов игрока (PlayerProjectile). Снаряды — дети текущей сцены (летят в мире, а не за
## игроком), не удаляются: погасший снаряд ждёт следующего выстрела. Больше PROJECTILE_POOL_MAX —
## переиспользуется следующий по кругу, даже если ещё летит.
const PROJECTILE_POOL_MAX: int = 160
var _projectiles: Array[PlayerProjectile] = []
var _projectile_cursor: int = 0
# Визуал по стилю: [Mesh, Material, вытяжка вдоль полёта, радиус попадания]. Создаётся один раз на стиль
var _projectile_visuals: Dictionary = {}
const PROJECTILE_STYLES: Dictionary = {
	&"needle": {"radius": 0.012, "length": 0.3, "color": Color(0.85, 0.92, 1.0), "energy": 3.0, "stretch": 1.6, "hit_radius": 0.12},
	&"pellet": {"radius": 0.03, "length": 0.07, "color": Color(1.0, 0.55, 0.15), "energy": 4.0, "stretch": 4.0, "hit_radius": 0.1},
	&"syringe": {"radius": 0.028, "length": 0.28, "color": Color(0.35, 1.0, 0.35), "energy": 3.0, "stretch": 1.2, "hit_radius": 0.14},
	&"needle_blood": {"radius": 0.016, "length": 0.32, "color": Color(1.0, 0.12, 0.08), "energy": 3.5, "stretch": 1.6, "hit_radius": 0.1},
}

var is_bursting: bool:
	get:
		if current_weapon_index >= 0 and current_weapon_index < weapons.size():
			return weapons[current_weapon_index].is_bursting
		return false

@onready var head = $"../Head"

func _ready() -> void:
	_init_weapons()
	_init_ammos()

## Выпустить физический снаряд игрока: траектория от камеры по direction со скоростью speed (+ inherit —
## добавочная скорость, например скорость игрока), визуал из дула. null — снаряд не создан (нет сцены)
func spawn_projectile(weapon: WeaponBase, direction: Vector3, speed: float, style: StringName, is_alt: bool = false,
		lifetime: float = 2.0, gravity: float = 0.0, inherit: Vector3 = Vector3.ZERO) -> PlayerProjectile:
	if not is_instance_valid(head) or not head.camera:
		return null
	var p: PlayerProjectile = _get_free_projectile()
	if not p:
		return null
	var visual: Array = _get_projectile_visual(style)
	var exclude: Array[RID] = []
	var player = get_parent()
	if player is CollisionObject3D:
		exclude.append(player.get_rid())
	var mask: int = head.raycast.collision_mask if head.raycast else 1
	p.launch(weapon, head.get_physics_camera_position(), direction.normalized() * speed + inherit, head.get_muzzle_position(),
		style, visual[0], visual[1], visual[2], lifetime, is_alt, exclude, mask, gravity, visual[3])
	return p

## Выпустить снаряд из произвольной точки мира (не из камеры): разлёт игл из умершего врага и т.п.
## exclude — что снаряд не задевает (игрок исключён всегда), hit_radius < 0 — радиус попадания стиля
func spawn_projectile_from(weapon: WeaponBase, origin: Vector3, velocity: Vector3, style: StringName, is_alt: bool = false,
		lifetime: float = 2.0, gravity: float = 0.0, exclude: Array[RID] = [], hit_radius: float = -1.0) -> PlayerProjectile:
	var p: PlayerProjectile = _get_free_projectile()
	if not p:
		return null
	var visual: Array = _get_projectile_visual(style)
	var all_exclude: Array[RID] = exclude.duplicate()
	var player = get_parent()
	if player is CollisionObject3D:
		all_exclude.append(player.get_rid())
	var mask: int = head.raycast.collision_mask if is_instance_valid(head) and head.raycast else 1
	p.launch(weapon, origin, velocity, origin, style, visual[0], visual[1], visual[2], lifetime, is_alt, all_exclude, mask, gravity,
		hit_radius if hit_radius >= 0.0 else visual[3])
	return p

## Оружие слота по классу-проверке (например, Швейная для разлёта игл)
func get_sewing() -> WeaponSewing:
	for w in weapons:
		if w is WeaponSewing:
			return w
	return null

## Все летящие снаряды (для механик, которым нужен обход, например возврат игл)
func get_active_projectiles() -> Array[PlayerProjectile]:
	var result: Array[PlayerProjectile] = []
	for p in _projectiles:
		if is_instance_valid(p) and p.active:
			result.append(p)
	return result

## Погасить все снаряды игрока (летящие, застрявшие, возвращающиеся): после смерти игрока они не наносят
## урона и не начисляют BPM за убийства
func deactivate_all_projectiles() -> void:
	for p in _projectiles:
		if is_instance_valid(p) and p.active:
			p.deactivate()

func _get_free_projectile() -> PlayerProjectile:
	# Снаряды — дети сцены: перезапуск сцены их освобождает (filter вернул бы нетипизированный Array)
	for i in range(_projectiles.size() - 1, -1, -1):
		if not is_instance_valid(_projectiles[i]):
			_projectiles.remove_at(i)
	for p in _projectiles:
		if not p.active:
			return p
	if _projectiles.size() < PROJECTILE_POOL_MAX:
		var scene_root: Node = get_tree().current_scene if get_tree().current_scene else get_parent().get_parent()
		if not scene_root:
			return null
		var p := PlayerProjectile.new()
		p.name = "PlayerProjectile"
		scene_root.add_child(p)
		_projectiles.append(p)
		return p
	# Пул полон — следующий по кругу, кроме снаряда, чьё попадание сейчас обрабатывается (его состояние
	# после возврата из оружия ещё читается)
	for _i in range(_projectiles.size()):
		_projectile_cursor = (_projectile_cursor + 1) % _projectiles.size()
		var reused: PlayerProjectile = _projectiles[_projectile_cursor]
		if not reused.in_hit_callback:
			reused.deactivate()
			return reused
	return null

func _get_projectile_visual(style: StringName) -> Array:
	if _projectile_visuals.has(style):
		return _projectile_visuals[style]
	var cfg: Dictionary = PROJECTILE_STYLES.get(style, PROJECTILE_STYLES[&"pellet"])
	var mesh := CylinderMesh.new()
	mesh.top_radius = cfg["radius"]
	mesh.bottom_radius = cfg["radius"]
	mesh.height = cfg["length"]
	mesh.radial_segments = 6
	mesh.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = cfg["color"]
	mat.emission_enabled = true
	mat.emission = cfg["color"]
	mat.emission_energy_multiplier = cfg["energy"]
	var visual: Array = [mesh, mat, cfg["stretch"], cfg.get("hit_radius", 0.0)]
	_projectile_visuals[style] = visual
	return visual

## Не стрелять автоогнём до отпускания ЛКМ (клик вернул захват курсора)
func block_autofire_until_release() -> void:
	_autofire_blocked = true

func _init_weapons() -> void:
	if weapons.is_empty():
		weapons = [
			WeaponCaliber.new(),
			WeaponAnvil.new(),
			WeaponInjector.new(),
			WeaponSewing.new()
		]
		var weapon_names = [&"WeaponCaliber", &"WeaponAnvil", &"WeaponInjector", &"WeaponSewing"]
		for i in range(weapons.size()):
			var w = weapons[i]
			w.name = weapon_names[i]
			w.weapon_manager = self
			w.slot_index = i
			add_child(w)
	else:
		for i in range(weapons.size()):
			var w = weapons[i]
			w.weapon_manager = self
			w.slot_index = i
			if not w.is_inside_tree():
				add_child(w)

func _init_ammos() -> void:
	ammos.clear()
	for i in range(weapons.size()):
		var w = weapons[i]
		var max_a = w.data.max_ammo if (w and w.data) else 0
		ammos.append(max_a)
		ammo_changed.emit(i, max_a, max_a)

## Полный боезапас и сброс перезарядок и кулдаунов (возрождение на чекпоинте)
func refill_all() -> void:
	if is_reloading:
		is_reloading = false
		active_reload_timer = 0.0
		reload_finished.emit(current_weapon_index)
	for i in range(passive_reload_timers.size()):
		passive_reload_timers[i] = 0.0
	for w in weapons:
		w.fire_timer = 0.0
		w.alt_timer = 0.0
	_init_ammos()

func _process(delta: float) -> void:
	var player_node = get_parent()

	# Активная перезарядка удерживаемого оружия
	if is_reloading:
		active_reload_timer -= delta
		if active_reload_timer <= 0.0:
			var active_w = weapons[current_weapon_index]
			var max_a = active_w.data.max_ammo if active_w.data else 0
			ammos[current_weapon_index] = max_a
			is_reloading = false
			active_reload_timer = 0.0
			ammo_changed.emit(current_weapon_index, max_a, max_a)
			reload_finished.emit(current_weapon_index)

	# Автоматическая стрельба при удержании ЛКМ (только с захваченным курсором)
	if _autofire_blocked and not Input.is_action_pressed("shoot"):
		_autofire_blocked = false
	if not _autofire_blocked and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED \
			and current_weapon_index < weapons.size() and weapons[current_weapon_index].data and weapons[current_weapon_index].data.is_automatic:
		if Input.is_action_pressed("shoot") and not is_reloading and weapons[current_weapon_index].can_fire() and not (player_node is Player and player_node.is_dead):
			var inf = false
			if player_node is Player:
				inf = player_node.bpm_system.has_infinite_ammo()
			shoot(inf)

	# Пассивная перезарядка неактивного оружия в фоне
	for i in range(weapons.size()):
		if i != current_weapon_index:
			var w_data = weapons[i].data
			if not w_data:
				continue
			if ammos[i] < w_data.max_ammo:
				passive_reload_timers[i] += delta
				if passive_reload_timers[i] >= w_data.reload_time:
					ammos[i] = w_data.max_ammo
					passive_reload_timers[i] = 0.0
					ammo_changed.emit(i, w_data.max_ammo, w_data.max_ammo)
			else:
				passive_reload_timers[i] = 0.0

func switch_weapon(index: int) -> void:
	if is_bursting or index == current_weapon_index or index < 0 or index >= weapons.size():
		return
	# Прерываем активную перезарядку в руках — неактивное оружие дозарядится пассивно в фоне
	if is_reloading:
		is_reloading = false
		active_reload_timer = 0.0
		reload_finished.emit(current_weapon_index)
	current_weapon_index = index
	if head:
		head.switch_weapon_visual(index)
	if index < weapons.size():
		weapon_switched.emit(index, weapons[index])

func shoot(has_infinite_ammo: bool) -> void:
	if is_reloading or is_bursting:
		return
	var w = weapons[current_weapon_index]
	if not w.can_fire():
		return
	if ammos[current_weapon_index] <= 0:
		reload()
		return
	if not has_infinite_ammo:
		ammos[current_weapon_index] -= 1
		ammo_changed.emit(current_weapon_index, ammos[current_weapon_index], w.data.max_ammo if w.data else 0)
	w.fire()

func alt_shoot(has_infinite_ammo: bool = false) -> void:
	if is_bursting:
		return
	var w = weapons[current_weapon_index]
	w.alt_fire(has_infinite_ammo)

func reload() -> void:
	var w = weapons[current_weapon_index]
	if not w.data:
		return
	if ammos[current_weapon_index] == w.data.max_ammo or is_reloading or is_bursting:
		return
	is_reloading = true
	active_reload_timer = w.data.reload_time
	AudioManager.play_sound("reload")
	reload_started.emit(current_weapon_index, w.data.reload_time)
