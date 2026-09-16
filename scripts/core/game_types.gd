extends Node

## Базовый модуль общих типов данных, глобальных перечислений и утилит коллизий/логирования (Autoload singleton).
## ВАЖНО: Не должен содержать class_name во избежание конфликта с именем автозагрузки GameTypes.

# Перечисление тиров BPM-системы
enum BPMTier {
	CALM,
	PUMPING,
	SURGING,
	OVERDRIVE
}

## Преобразует enum BPMTier в строковое представление
static func tier_to_string(tier: BPMTier) -> String:
	match tier:
		BPMTier.CALM:
			return "CALM"
		BPMTier.PUMPING:
			return "PUMPING"
		BPMTier.SURGING:
			return "SURGING"
		BPMTier.OVERDRIVE:
			return "OVERDRIVE"
		_:
			return "CALM"


# Именованные битовые маски слоёв 3D-коллизий (3D Physics Layers)
# Фактическое состояние в сценах проекта:
# - Слой 1 (бит 0, знач. 1): Геометрия мира, дефолтный слой для тел игрока, врагов и хитбоксов
# - Слой 2 (бит 1, знач. 2): Вражеские снаряды (projectile_enemy.tscn)
# Слои 3-5 зарезервированы под планируемое разделение сущностей:
const LAYER_WORLD: int = 1 << 0          # Слой 1 (значение 1) - геометрия мира и базовые коллизии
const LAYER_PROJECTILE: int = 1 << 1     # Слой 2 (значение 2) - снаряды
const LAYER_PLAYER: int = 1 << 2         # Слой 3 (значение 4) - игрок
const LAYER_ENEMY: int = 1 << 3          # Слой 4 (значение 8) - тело врага
const LAYER_ENEMY_HITBOX: int = 1 << 4   # Слой 5 (значение 16) - зоны уязвимости (голова)

# Флаг централизованной отладочной печати
const DEBUG_ENABLED: bool = false

## Разрешает узел, способный принимать урон (метод take_damage).
## Проверяет сначала сам коллайдер, затем его непосредственного родителя (например, Area3D HeadHitbox у врага).
## Возвращает найденный Node с методом take_damage либо null.
static func resolve_damageable(collider: Node) -> Node:
	if not is_instance_valid(collider):
		return null
	if collider.has_method("take_damage"):
		return collider
	var parent: Node = collider.get_parent()
	if is_instance_valid(parent) and parent.has_method("take_damage"):
		return parent
	return null

## Централизованное отладочное логирование вместо прямого print().
## Выводит сообщения в консоль только при активном флаге DEBUG_ENABLED.
static func debug_log(category: StringName, msg: String) -> void:
	if DEBUG_ENABLED:
		print("[%s] %s" % [category, msg])
