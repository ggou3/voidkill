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

var is_bursting: bool:
	get:
		if current_weapon_index >= 0 and current_weapon_index < weapons.size():
			return weapons[current_weapon_index].is_bursting
		return false

@onready var head = $"../Head"
@onready var skill_manager = get_node_or_null("../SkillManager")

func _ready() -> void:
	_init_weapons()
	_init_ammos()

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

	# Автоматическая стрельба при удержании ЛКМ
	if current_weapon_index < weapons.size() and weapons[current_weapon_index].data and weapons[current_weapon_index].data.is_automatic:
		if Input.is_action_pressed("shoot") and not is_reloading and weapons[current_weapon_index].can_fire():
			var inf = false
			if player_node is Player:
				inf = player_node.has_infinite_ammo()
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
