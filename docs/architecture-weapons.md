# Архитектура: оружие

← [Оглавление: DESIGN.md](../DESIGN.md)

### Ресурсы конфигурации оружия (WeaponData) — ✅ Реализован (Шаг 4.1)
- **WeaponData** (`res://scripts/weapons/weapon_data.gd`, `class_name WeaponData extends Resource`) — единый строго типизированный ресурс данных конфигурации оружия, заменивший неконсистентные словари `Dictionary` в `weapon_manager.gd`.
- **Поля ресурса**:
  - `weapon_id: StringName`: уникальный строковый идентификатор оружия (`&"caliber_0"`, `&"anvil"`, `&"injector"`, `&"sewing_machine"`).
  - `name: String`: отображаемое название оружия в HUD (`"КАЛИБР-0"`, `"КРОВАВАЯ НАКОВАЛЬНЯ"`, `"ИНЪЕКТОР"`, `"ШВЕЙНАЯ МАШИНА"`).
  - `max_ammo: int`: ёмкость магазина (4, 2, 6, 40).
  - `damage: int`: базовый прямой урон одного снаряда / дробинки (70, 12, 10, 6).
  - `pellets: int`: количество снарядов за выстрел (1 для обычных, 8 для дробовика).
  - `spread: float`: конусный разброс (0.0, 0.085, 0.045, 0.02).
  - `fire_rate: float`: темп стрельбы / интервал между выстрелами в секундах (1.0, 0.5, 0.28, 0.1).
  - `reload_time: float`: время полной перезарядки магазина в секундах (1.1, 1.5, 1.4, 2.0).
  - `cam_shake: float`: интенсивность тряски камеры при выстреле (0.09, 0.12, 0.025, 0.025).
  - `weapon_kick: float`: отдача view-model оружия (0.35, 0.4, 0.08, 0.08).
  - `knockback: float`: горизонтальный отброс цели от пули (4.5, 6.0, 1.5, 1.0).
  - `upward_kick: float`: вертикальный подброс цели в воздух (0.0, 7.0, 0.0, 0.0).
  - `headshot_multiplier: float`: множитель урона при попадании в голову (2.2 для Калибр-0, 1.5 для остальных).
  - `air_multiplier: float`: множитель урона по воздушным целям (2.0 для Калибр-0, 1.0 для остальных).
  - `has_vacuum: bool`, `vacuum_radius: float`, `vacuum_force: float`: параметры гравитационного следа пули (2.5м радиус, 25.6 сила для Калибр-0).
  - `is_automatic: bool`: флаг автоматической непрерывной стрельбы при удержании ЛКМ (true для Швейной машины).
  - Группа `@export_group("Альт-огонь")` (0 = поле не используется оружием): `alt_cooldown: float`, `alt_ammo_cost: int`, `alt_projectile_count: int`, `alt_damage: int`. Сейчас заполнена только у Швейной машины (1.5с, 10 игл, 12 игл, 4 HP) — константы `ALT_COOLDOWN`, `BARRAGE_AMMO_COST`, `NEEDLE_COUNT`, `NEEDLE_DAMAGE` удалены из `weapon_sewing.gd`; хедшот залпа берёт `headshot_multiplier` (1.5) вместо литерала. Параметры ПКМ Наковальни, Инъектора и Калибр-0 пока в коде.
- **Файлы ресурсов (`res://scripts/weapons/data/`)**:
  - `caliber_0.tres`, `anvil.tres`, `injector.tres`, `sewing_machine.tres` с побуквенно перенесёнными параметрами и исчерпывающими комментариями.
- **Интеграция с WeaponManager**:
  - Массив `weapons: Array[WeaponData]` инициализируется предзагруженными ресурсами.
  - Массив текущих патронов `ammos: Array[int]` инициализируется динамически из `w.max_ammo`, устранён дубликат `var ammos = [4, 2, 6, 40]`.
  - Все обращения через `w["key"]` и `w.get("key", default)` переведены на прямое обращение к полям `w.property`.

### Базовый класс оружия (WeaponBase) — ✅ Реализован (Шаг 4.2)
- **WeaponBase** (`res://scripts/weapons/weapon_base.gd`, `class_name WeaponBase extends Node`) — абстрактный базовый класс оружия игрока.
- **Интерфейс контракта**:
  - `data: WeaponData`: ссылка на ресурс конфигурации оружия.
  - `fire() -> void`, `alt_fire(has_infinite_ammo: bool) -> void`: методы основного и альтернативного огня.
  - `can_fire() -> bool`: проверка готовности оружия к выстрелу.
  - `_apply_hit(collider: Node, hit_pos: Vector3, dir: Vector3, is_alt: bool) -> void`: централизованная обработка попадания.
- **Пайплайн `_apply_hit`**:
  - Спавн трейсера через `TracerPool.spawn_tracer()` с дульной позиции `_get_muzzle_position()`.
  - Разрешение цели и детекция хедшота через `collider.is_in_group("enemy_head")` / `collider.name == "HeadHitbox"` и `GameTypes.resolve_damageable()`.
  - Определение нахождения в воздухе `is_airborne` через `target_body.is_on_floor()`.
  - Расчёт импульса отброса с горизонтальным вектором и вертикальным подбросом: `flat_dir * data.knockback`, `y = data.upward_kick`.
  - Применение множителей `headshot_multiplier` и `air_multiplier` с сохранением режимов стакинга: `MULTIPLICATIVE` в тире `OVERDRIVE`, `ADDITIVE` в остальных тирах.
  - Нанесение урона `target.take_damage()` с правильными флагами и строковым ключом оружия.
  - Вакуумный след `_apply_vacuum_wake()` для гравитационного оружия (Калибр-0 в OVERDRIVE).
  - Виртуальный хук `_on_hit_target()` для специфичных эффектов специализированных классов (яд, иглы, синергия дроби).

### Специализированные классы оружия и тонкий менеджер — ✅ Реализован (Шаг 4.3)
- **Выделенные классы в `res://scripts/weapons/`**:
  - `weapon_caliber.gd` (`class_name WeaponCaliber extends WeaponBase`): ЛКМ — одиночный точный хитскан через `_apply_hit`; ПКМ — пробивной рейлган-выстрел `_fire_caliber_piercing_shot` (BPM-гейт: OVERDRIVE; сквозной луч через врагов, единый вакуумный вихрь на весь луч, автоперезарядка).
  - `weapon_anvil.gd` (`class_name WeaponAnvil extends WeaponBase`): ЛКМ — дробь 8 дробин через `_apply_hit` с синергией застрявших игл (`_get_damage_multiplier` даёт +4% за иглу до +60%); ПКМ — пневмопоршень `_fire_anvil_piston` (sphere-cast AoE, 0 прямого урона, запуск в ноги 21 м/с или 3D-толчок 42 м/с, floor-splash, направленный `self-launch` игрока с цепочкой антиспама 100% → 60% → 35%).
  - `weapon_injector.gd` (`class_name WeaponInjector extends WeaponBase`): ЛКМ — очередь из 3 дротиков с паузой 0.07с, наложение стакающегося яда `apply_poison_dot` через `_on_hit_target`; ПКМ — статусное раздутие врага `inflate` (кулдаун 4.5с).
  - `weapon_sewing.gd` (`class_name WeaponSewing extends WeaponBase`): ЛКМ — автоматическая стрельба иглами (10 выстр/с), застревание игл `add_needle` через `_on_hit_target`; ПКМ — заградительный веерный залп 12 игл `_fire_sewing_barrage` (конус 35-40°, расход 10 игл, кулдаун 1.5с).
- **Декомпозиция `weapon_manager.gd`**:
  - Размер сокращён с 1114 до 306 строк (из которых ~140 строк — логика менеджера, остальное — временный HUD до Шага 5).
  - Полностью устранены цепочки проверок `if weapon_idx == N` и специфичные таймеры/переменные.
  - Делегирование стрельбы: `shoot()` вызывает `w.fire()`, `alt_shoot()` вызывает `w.alt_fire(has_infinite_ammo)`.
  - Динамические HUD-суффиксы реализованы полиморфно через `w.get_alt_hud_suffix(has_infinite_ammo)`.

