# Архитектура: враги и компоненты

← [Оглавление: DESIGN.md](../DESIGN.md)

### Компонентная архитектура (HealthComponent) — ✅ Реализован (Шаг 3.1)
- **HealthComponent** (`res://scripts/components/health_component.gd`, `class_name HealthComponent`) — инкапсулирует расчёт и хранение здоровья, обработку урона, учёт глубин цепных реакций (`explosion_chain_depth`, `slam_chain_depth`), фиксацию флагов типа убийства (`was_killed_by_melee`, `was_killed_by_shockwave`, `last_damage_weapon`, `is_execute`).
- **Сигналы**:
  - `damaged(amount: int, is_crit: bool, hit_pos: Vector3)` — оповещение о нанесении урона (спавн всплывающих цифр урона и VFX брызг крови).
  - `died(info: Dictionary)` — словарь `info` передаёт `is_headshot`, `is_execute`, `hit_pos`, `knockback`, `source_chain_depth`.
  - **Единственный источник правды о способе убийства и глубинах цепей** — поля `was_killed_by_melee`, `was_killed_by_shockwave`, `last_damage_weapon`, `explosion_chain_depth`, `slam_chain_depth` на `HealthComponent`. Дубликаты на `EnemyBase` и в словаре `died` (оставленные на Шаге 3.1 ради совместимости) удалены; `EnemyBase`, `EnemyGround` (wall slam) и `StatusEffectComponent` читают и пишут только компонент.
  - **Убийство засчитывается источнику последнего удара**: вычисление источника вынесено в `HealthComponent.record_hit_source()`; его вызывает `take_damage()` и тик яда (`EnemyBase._on_status_requests_damage`), который идёт мимо `take_damage` ради своего визуала (зелёный номер, без звука удара и брызг). Раньше тик яда ставил только `last_damage_weapon = "injector"` и не сбрасывал флаг ударной волны — добивание ядом после конусной волны/слэма засчитывалось как ударная волна мили (+8.0 BPM) с мили-лечением от раздутого.
  - **Классификация ударной волны**: ударная волна с меткой оружия (`"slam"` — волна слэма, `"anvil"` — поршень Наковальни) засчитывается этому оружию как обычное убийство (+5.5 BPM, без мили-флага и мили-лечения от раздутого). Метка `"melee"` или пустая — мили-ударная волна; бонус ударной волны (+8.0 BPM) — только у неё (конусная волна мили).
  - **Удар о стену (wall slam)**: в момент толчка, открывающего окно wall slam, `EnemyGround` запоминает источник толчка (`wall_slam_source_weapon/_melee/_shockwave`) отдельно от `HealthComponent`. Сам удар о стену — последний удар: он записывает себя через `record_hit_source()` с этим источником, поэтому урон в полёте (тик яда) не перехватывает убийство.
  - **Игрок вне цепочки wall slam**: если врага впечатало в игрока, игрок урона не получает и цепочку не продолжает (сосед-игрок пропускается).
  - **Цепочка wall slam**: источник того, кто начал цепочку, передаётся соседу вместе с глубиной (`take_damage(..., next_depth, wall_slam_source_weapon)`) — толкнул первого поршнем, вся цепочка `"anvil"`; слэмом — `"slam"`; конусной волной мили — `"melee"` (+8.0).
  - `health_changed(current: int, maximum: int)` — реактивное обновление отладочного HP-бара.
- **Интеграция с Enemy**:
  - В `enemy.gd` метод `take_damage()` стал тонкой обёрткой: обрабатывает локальные физические реакции CharacterBody3D (отброс, сброс прыжков, прерывание выпада lunge, таймер соударения со стеной `wall_slam_timer`, агр из IDLE в CHASE) и делегирует урон в `health_component.take_damage(...)`.
  - Поля `health` и `max_health` на `Enemy` оформлены через геттеры/сеттеры к компоненту с сохранением полной обратной совместимости для внешних систем (`player.gd`, `weapon_manager.gd`, DoT яда, урон об стены).
  - Удалена мёртвая ветка `else` при проверке `player.skills.has_method("record_kill_bpm")` в `Enemy.die()`.

### Компонентная архитектура (StatusEffectComponent) — ✅ Реализован (Шаг 3.2)
- **StatusEffectComponent** (`res://scripts/components/status_effect_component.gd`, `class_name StatusEffectComponent`) — инкапсулирует логику статус-эффектов врага:
  - **Яд (Poison DoT)**: `apply_poison_dot()`, `_process_poison()`, `_apply_poison_tick()`, `poison_stacks`, `MAX_POISON_STACKS = 5`, чумное облако заражения при смерти `trigger_poison_contagion()` (радиус 2.5м, лимит цепи 3 поколения) с визуальным эффектом сферы `_spawn_poison_cloud_visual()`.
  - **Иглы (Needles)**: `add_needle()`, `_process_needles()`, `needle_count`, `needle_timers`, разлёт застрявших игл при смерти `trigger_needle_burst()` (радиус 4.0м / 6.0м при раздутии, урон 3 HP / 8 HP с затуханием 0.7^depth, сквозное пробивание при раздутии, трассировка `TracerPool.spawn_tracer(..., &"shrapnel")`).
  - **Раздутие (Inflation)**: `inflate()`, `is_inflated`, таймеры анимаций `inflation_tween` / `inflation_pulse_tween`, кровавая детонация раздутого врага при смерти `trigger_inflation_explosion()` (радиус 5.2м * mult, урон 85 HP * mult, исцеление игрока 35/15 HP * mult, потолок цепи на глубине 3) с ударной волной `_spawn_explosion_shockwave()` и разлётом крови `blood_splatter`.
  - **Замедление (Slow)**: `add_slow()`, `remove_slow()`, `slow_factor`, `slow_sources`.
- **Сигналы**:
  - `effect_applied(kind: StringName, stacks: int)`
  - `effect_expired(kind: StringName)`
  - `visuals_need_update(kind: StringName)`
  - `requests_damage(amount: int, kind: StringName)`
- **Интеграция с Enemy и наследниками**:
  - В `enemy.gd` свойства `needle_count`, `needle_timers`, `is_inflated`, `slow_factor`, `slow_sources`, `poison_stacks`, `inflation_tween`, `inflation_pulse_tween` оформлены через делегирующие геттеры/сеттеры с сохранением полной обратной совместимости с `player.gd`, `weapon_manager.gd`, `enemy_ranged.gd` и `enemy_stalker.gd`.
  - Носитель (`enemy.gd`) подписывается на сигналы компонента: `requests_damage` наносит урон через `HealthComponent` со спавном зелёных цифр урона и агром из `IDLE`; `visuals_need_update` вызывает обновление мешей и материалов (`_update_needle_visuals`, `_update_inflation_visuals`); замедление напрямую учитывается при расчёте целевой скорости (`move_speed * slow_factor`).
  - Удалены дублирующие циклы обработки таймеров яда и игл из `_physics_process` в `enemy.gd` и `enemy_stalker.gd`, устранён риск двойного покадрового тика эффектов.
  - В `enemy.tscn` добавлен узел `StatusEffectComponent` (дополнительно подстрахован автосозданием в `_get_or_create_status_effect_component()`).
  - В `enemy.gd` реализованы фасадные методы-делегаты и публичные алиасы для эффектов и их визуалов: `_spawn_explosion_shockwave()`, `spawn_explosion_shockwave()`, `_spawn_poison_cloud_visual()`, `spawn_poison_cloud_visual()`, `_trigger_inflation_explosion()`, `trigger_inflation_explosion()`, `_trigger_poison_contagion()`, `trigger_poison_contagion()`, `_trigger_needle_burst()`, `trigger_needle_burst()`, `add_needle(_is_blood_needle: bool = false)`. Благодаря этому специализированные наследники (`enemy_bomber.gd`, `enemy_stalker.gd`) не требуют переписывания и не зависят от деталей реализации компонентов.
  - В `StatusEffectComponent._spawn_explosion_shockwave()` анимация затухания ударной волны переведена на `sphere.create_tween()`, гарантируя корректное завершение эффекта и удаление сферы даже при мгновенном вызове `queue_free()` на враге-носителе (например, при взрыве Подрывника).

### Компонентная архитектура (EnemyHealthBar) — ✅ Реализован (Шаг 3.3)
- **EnemyHealthBar** (`res://scripts/components/enemy_health_bar.gd`, `class_name EnemyHealthBar`, наследует `Node3D`) — унифицированный компонент рендеринга 3D-полоски здоровья над головой врагов.
- **Отладочная функция, по умолчанию выключена** (переделка «полоски HP и проверка пола»):
  - Клавиша **H** (действие `debug_toggle_hp_bars`, по аналогии с T для BPM) переключает
    `GameManager.show_enemy_health_bars`; состояние живёт в автозагрузке и держится всю сессию.
  - Выключено — компонент у врагов не создаётся вообще (узла `EnemyHealthBar` нет и в `enemy.tscn`).
    `EnemyBase._ready()` создаёт полоску через `_setup_health_bar()`, только если полоски включены, и
    подписан на `GameManager.enemy_health_bars_toggled`: включение создаёт полоску у всех живых врагов,
    выключение удаляет (`queue_free`). Новые враги смотрят на текущее состояние.
  - Цифры урона (`_spawn_damage_number`) от полосок не зависят и показываются всегда.
- **Содержимое и визуал**:
  - Квад-биллборд `MeshInstance3D` (`QuadMesh` 0.91×0.14 м — прежние 130×20 px при `pixel_size` 0.007)
    с шейдером `shaders/enemy_health_bar.gdshader`: unshaded, без теста глубины, фон
    `Color(0.08, 0.08, 0.08, 0.85)`, рамка 2 px `Color(0.35, 0.35, 0.35, 0.9)`, заливка цветом врага по доле HP.
    Меш и `ShaderMaterial` — общие на всех врагов (`static var`), доля HP и цвет — `instance uniform`
    (`set_instance_shader_parameter`). Скругления углов прежнего `StyleBoxFlat` нет. SubViewport на врага больше нет.
  - `Label3D` числовое значение здоровья (`BILLBOARD_ENABLED`, `no_depth_test = true`, `font_size = 18`, `outline_size = 4`, цвет контура чёрный).
- **Параметризация**:
  - Обычные враги (`Enemy`): вертикальный оффсет 1.15м (текст 1.32м), алый цвет полоски `Color(0.95, 0.15, 0.15)`.
  - Летающий враг (`EnemyFlyer`): вертикальный оффсет 0.95м (текст 1.12м), циановый цвет полоски `Color(0.15, 0.8, 0.95)`, оттенок текста `Color(0.9, 0.98, 1.0)`.
  - Рой (`EnemySwarm`): кастомный оффсет 0.65м (текст 0.80м), уменьшенный шрифт `font_size = 14`.
- **Реактивность и совместимость**:
  - Подписывается на `health_component.health_changed(current, max)`; публичные `update_health`,
    `set_bar_visible`, `set_bar_offset_y`, `set_label_font_size`.
  - Особенности типов — переопределения `_setup_health_bar()` (срабатывают и при включении полосок во
    время игры): летун — свои оффсет и цвета; рой — `super` + оффсет 0.65/0.80 м и шрифт 14; соглядатай —
    `super` + видимость по маскировке (полоска видна при `current_visibility > 0.65`, `set_visibility`
    переключает её у существующей полоски).
  - Прокси-поля `hp_viewport`, `hp_bar`, `hp_sprite`, `hp_label` на `EnemyBase` удалены: они создавали
    полоску при любом обращении. Доступ — через `health_bar` (может быть `null`) и его методы.

### Иерархия классов врагов (EnemyBase и EnemyGround) — ✅ Реализован (Шаг 3.4)
- **EnemyBase** (`res://scripts/enemies/enemy_base.gd`, `class_name EnemyBase extends CharacterBody3D`, 789 строк) — базовый абстрактный класс для всех типов врагов (наземных и летающих):
  - FSM-машина: `enum State { IDLE, CHASE, ATTACK, LUNGE, TELEGRAPH, FIRING, DEAD }` (`FLEE` удалён вместе с Fear Chain), диспетчер состояний в `_physics_process(delta)`, централизованный `set_state(new_state)`.
  - Перцепция и целеуказание: `target_player`, `start_chase(player)`, `detection_range`, `reaction_delay`, `_has_line_of_sight_to(target)`, реакция `_on_detection_area_body_entered`.
  - Владение компонентами: жизненный цикл и ленивое создание `HealthComponent`, `StatusEffectComponent`; `EnemyHealthBar` — только при включённых отладочных полосках (H).
  - Полный фасад свойств и методов: `slow_factor`, `poison_stacks`, `needle_count`, `is_inflated`, `add_slow`, `apply_poison_dot`, `add_needle`, `inflate`, триггеры детонаций (`trigger_inflation_explosion`, `trigger_poison_contagion`, `trigger_needle_burst`), спавн эффектов ударных волн и ядовитых облаков.
  - Урон, смерть и VFX: `take_damage(...)`, `die(death_info)`, всплывающие цифры урона `_spawn_damage_number`, генерация брызг крови `_spawn_hit_blood_splatter`, спавн лужи крови `BloodPool`, физика гравипула `apply_vacuum_pull`.
  - Полное отсутствие привязок к 2D/наземной навигации (`NavigationAgent3D` и проверка пола отсутствуют).
- **EnemyGround** (`res://scripts/enemies/enemy_ground.gd`, `class_name EnemyGround extends EnemyBase`, 772 строки) — базовый класс для всех наземных врагов:
  - Наземная навигация: `NavigationAgent3D`, инициализация с физическим кадром синхронизации `_setup_navigation()`, периодический пересчёт пути `path_update_timer` (`PATH_UPDATE_INTERVAL = 0.35с`), избегание препятствий `_on_velocity_computed` с мёртвой зоной `avoidance_deadzone = 0.5м`, предохранитель застревания `unreachable_timer >= 3.5с` с откатом в `IDLE` на `REPATH_COOLDOWN = 2.0с`.
  - Прыжки по навигационным линкам (NavigationLink3D): перехват `_on_link_reached(details)`, баллистический расчёт параболы `_start_link_jump(target_pos)` с высотой апекса `h_apex` и эффективной гравитацией `eff_gravity = gravity * 2.0`, таймер защиты `jump_grace_timer = 0.25с`.
  - Система атаки-выпада (Lunge Attack): расчёт 3D-вектора наведения с вертикальным лимитом 38° `_calculate_lunge_vector_and_distance()`, проверка пола в точке приземления `_has_floor_at_destination()` (луч вниз; враги лучу не мешают — попав во врага, луч исключает именно его и повторяется, до `FLOOR_PROBE_MAX_ENEMY_HITS = 8` раз; раньше в исключения заранее шла вся группа `"enemy"`, и цена росла квадратично с числом врагов), фаза 1 (телеграф 0.38с со сжатием модели и янтарными глазами), фаза 2 (рывок 25 м/с на 6.5–7.5м с дэш-звуком и нанесением 20 HP урона), фаза 3 (баллистическое падение по инерции до касания пола).
  - Система соударения со стенами (Wall Slam): отслеживание удара `-pre_move_velocity.dot(n) >= 16.0` в окне `wall_slam_timer`, асимптотический урон с насыщением `wall_slam_max_damage = 55 HP`, цепной сплэш по другим врагам `collateral_slam` с затуханием (60% -> 35% -> 20%), разлёт крови и восполнение дэша игроку при фатальном ударе.
    - Регрессия Шага 3.1 исправлена: после выноса урона в `HealthComponent` wall slam читал `slam_chain_depth` со старого поля `EnemyBase`, которое при жизни никто не заполнял (всегда 0) — затухание цепи не работало (себе всегда 100%, соседу всегда 60%), а сброс `explosion_chain_depth` при смертельном ударе о стену не доходил до компонента. Теперь глубины читаются и сбрасываются в `HealthComponent`.
  - Гравитация `velocity.y -= gravity * 2.0 * delta`, инерционное затухание отброса `knockback_velocity` и вызов `move_and_slide()`.
- **Enemy** (`res://enemy.gd`, `class_name Enemy extends EnemyGround`, 98 строк — сокращение на 94% с 1643 до 98 строк):
  - Специализация базового ближнего врага: атака в упор `perform_attack()` (15 урона, кулдаун 1.0с, радиус 2.0м, алая вспышка глаз `eyes_material`), логика состояний `_process_attack(delta)` и `_process_chase(delta)` с проверкой кулдауна выпада Lunge.
  - Наследников у класса больше нет: используется исключительно базовым ближним врагом (`enemy.tscn`).

### Рефакторинг специализированных врагов, летуна и турели — ✅ Реализован (Шаг 3.5)
- **Перевод наземных врагов на EnemyGround**:
  - `enemy_ranged.gd`, `enemy_bomber.gd`, `enemy_shield.gd`, `enemy_hunter.gd`, `enemy_swarm.gd`, `enemy_stalker.gd` переведены с наследования `res://enemy.gd` на прямое наследование `extends EnemyGround`.
  - Устранена паразитная зависимость специализированных архетипов от параметров и методов ближней атаки базового моба `Enemy`: параметры атаки и методы `perform_attack` / `_process_attack` / `_process_chase` явно и изолированно определены в тех архетипах, где они требуются (`EnemyShield`, `EnemyHunter`, `EnemySwarm`).
  - Все сигнатуры виртуальных переопределений приведены к строгому соответствию базовым классам с явной статической типизацией параметров (`amount: int`, `knockback_vector: Vector3`, `hit_pos: Vector3`, и т.д.).
- **Рефакторинг и дедупликация летуна (`EnemyFlyer`, `enemy_flyer.gd`)**:
  - Переведён с обособленного `CharacterBody3D` на наследование `extends EnemyBase`.
  - Полностью удалены сотни строк дублированного бойлерплейта: урон и отброс (`take_damage`), смерть (`die`), все статус-эффекты (`apply_poison_dot`, `_apply_poison_tick`, `inflate`, `add_slow`, `remove_slow`, `add_needle`), гравипул (`apply_vacuum_pull`), спавн цифр урона (`_spawn_damage_number`), проверка прямой видимости (`_has_line_of_sight_to`) и процедурное создание полоски HP в SubViewport.
  - Подключен к `HealthComponent`, `StatusEffectComponent` и `EnemyHealthBar`.
  - Восстановлены все механики статус-эффектов:
    - **Иглы (Needles)**: накопление стаков игл Швейной машины, масштабирование модели от количества игл, шрапнельный разлёт игл при смерти (`trigger_needle_burst`).
    - **Яд (Poison DoT)**: тики урона от Инъектора с зелёными цифрами урона, чумное облако заражения при гибели (`trigger_poison_contagion`).
    - **Раздутие (Inflation)**: анимация раздутия с пульсацией глаз, разрушительная кровавая детонация при гибели (`trigger_inflation_explosion`).
    - **Замедление (Slow)**: множитель `slow_factor` с динамическим снижением скорости полёта при попадании колбы замедления.
  - Дедуплицированы процедуры построения геометрии лазера и секторов прицеливания (`_orient_cylinder_between`, `_cast_boundary_line`).
  - Задействованы виртуальные диспетчеры базового класса `_process_telegraph(delta)`, `_process_firing(delta)`.
  - Размер файла сокращён с 875 до 447 строк (сокращение на 49%, строго в пределах нормы <= 500 строк).
- **Рефакторинг турели (`EnemyTurret`, `enemy_turret.gd`)**:
  - Переведена с `res://enemy.gd` на наследование `extends EnemyRanged`.
  - Из `EnemyRanged` выделены виртуальные методы `_get_projectile_spawn_position()` и `_play_attack_flash()`, благодаря чему в `EnemyTurret` полностью удалены дублированный спавн снарядов, расчёт траекторий и звуки выстрела: турель переопределяет точки ствола и вызывает `super.perform_attack()`.
  - Сохранена полная стационарность (`_apply_movement` с `velocity = Vector3.ZERO`), фиксация базы (`base_mount.global_transform.basis = base_fixed_basis`). Защитный локдаун на OVERDRIVE удалён вместе с Fear Chain.
- **Интеграция лазерной атаки в EnemyBase**:
  - В `EnemyBase.State` добавлены общие состояния `TELEGRAPH` и `FIRING` вместе с виртуальными методами `_process_telegraph(_delta)` и `_process_firing(_delta)`, что исключило конфликт затенения enum `State` в GDScript и стандартизировало обработку подготовки/стрельбы в общем цикле `_physics_process`.

