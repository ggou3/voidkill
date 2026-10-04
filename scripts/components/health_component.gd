class_name HealthComponent
extends Node

## HealthComponent — компонент здоровья и обработки входящего урона.
## Инкапсулирует вычисление и хранение HP, цепочки взрывов/слэмов,
## флаги типа убийства (melee, shockwave, weapon_source) и сигналы повреждения/смерти.

signal damaged(amount: int, is_crit: bool, hit_pos: Vector3)
signal died(info: Dictionary)
signal health_changed(current: int, maximum: int)

@export var max_health: int = 100:
	set(value):
		max_health = value
		health = clamp(health, 0, max_health)
		health_changed.emit(health, max_health)

var health: int = 100:
	set(value):
		var prev = health
		health = clamp(value, 0, max_health)
		if health != prev:
			health_changed.emit(health, max_health)

var was_killed_by_melee: bool = false
var was_killed_by_shockwave: bool = false
var last_damage_weapon: String = ""
var explosion_chain_depth: int = 0
var slam_chain_depth: int = 0
var last_is_execute: bool = false

func _ready() -> void:
	health = max_health

func is_dead() -> bool:
	return health <= 0

func take_damage(amount: int, knockback: Vector3, hit_pos: Vector3, is_melee: bool = false, is_execute: bool = false, is_shockwave: bool = false, is_headshot: bool = false, source_chain_depth: int = -1, weapon_source: String = "") -> void:
	if is_dead():
		return

	record_hit_source(amount, is_melee, is_execute, is_shockwave, source_chain_depth, weapon_source)

	var prev_health = health
	health = max(0, health - amount)

	damaged.emit(amount, is_headshot, hit_pos)
	
	if health <= 0 and prev_health > 0:
		# Способ убийства (was_killed_by_*, last_damage_weapon) и глубины цепей
		# (explosion_chain_depth, slam_chain_depth) не дублируются в death_info —
		# потребители читают их из полей HealthComponent.
		var death_info: Dictionary = {
			"is_headshot": is_headshot,
			"is_execute": is_execute,
			"hit_pos": hit_pos,
			"knockback": knockback,
			"source_chain_depth": source_chain_depth
		}
		died.emit(death_info)

## Фиксирует источник удара: способ убийства (was_killed_by_*, last_damage_weapon) и глубины цепей.
## Вызывается из take_damage и из путей урона в обход него (тик яда), чтобы убийство
## всегда засчитывалось источнику последнего удара.
func record_hit_source(amount: int, is_melee: bool = false, is_execute: bool = false, is_shockwave: bool = false, source_chain_depth: int = -1, weapon_source: String = "") -> void:
	if source_chain_depth >= 0:
		explosion_chain_depth = source_chain_depth + 1
	else:
		explosion_chain_depth = 0

	if is_shockwave:
		slam_chain_depth = max(0, source_chain_depth)
		was_killed_by_shockwave = true
	elif amount > 0:
		was_killed_by_shockwave = false

	# Ударная волна оружия с собственной меткой (волна слэма "slam", поршень Наковальни "anvil")
	# работает как ударная волна по физике (wall slam, цепи, стан), но не мили:
	# убийство засчитывается этому оружию без мили-бонусов. Метка "melee" или её отсутствие —
	# мили-ударная волна (конусная волна мили, цепочка wall slam от мили).
	var credits_weapon = weapon_source != "" and weapon_source != "melee"
	was_killed_by_melee = is_melee or is_execute or (is_shockwave and not credits_weapon)
	last_is_execute = is_execute

	if credits_weapon and not is_melee and not is_execute:
		last_damage_weapon = weapon_source
	elif is_melee or is_shockwave or is_execute:
		last_damage_weapon = "melee"
	elif weapon_source != "":
		last_damage_weapon = weapon_source
