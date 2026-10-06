# VOIDKILL — контекст для Claude

## 1. Что за проект
3D boomer-shooter на Godot 4.7, GDScript. Ядро — кровь (лужи, кровавый сёрф/слэм),
скорость (bhop, wallrun, slide) и BPM-система (сердцебиение 50–200, тиры
CALM/PUMPING/SURGING/OVERDRIVE). Источник истины по дизайну и архитектуре — `DESIGN.md`
(концепция и оглавление) и файлы `docs/` по темам: архитектура — `docs/architecture*.md`,
технические уроки — `docs/lessons.md`, roadmap — `docs/roadmap.md`. Тестовый уровень —
`test_arena.tscn`, главная сцена — `world.tscn`.

Autoload (project.godot): `GameTypes`, `GameManager`, `AudioManager`, `TracerPool`.
Скриптам-автозагрузкам `class_name` НЕ добавлять (конфликт с именем синглтона).

Раскладка — все скрипты в `scripts/` (перенесены редактором в `5760953`, `0f13848`):
- `core/` — game_types, tracer_pool (автозагрузки)
- `components/` — health_component, status_effect_component, enemy_health_bar
- `enemies/` — enemy_base, enemy_ground, enemy (ближний), enemy_ranged/bomber/shield/hunter/
  swarm/stalker/turret/flyer
- `player/` — player, head, skill_manager (дэш, слэм), bpm_system, player_health,
  player_combat, player_wallrun
- `weapons/` — weapon_manager, weapon_data, weapon_base, weapon_caliber/anvil/injector/sewing,
  projectile_enemy (вражеский снаряд), `data/*.tres`
- `effects/` — blood_pool, blood_splatter
- `ui/` — hud
- `levels/` — sector, blood_barrier, level_controller, level_exit (каркас уровней)
- корень `scripts/` — audio_manager, game_manager (автозагрузки)

Уровни — `levels/*.tscn` (сейчас `levels/demo_level.tscn`), новые шейдеры — `shaders/`
(`blood_barrier.gdshader`). В корне `res://` остались старые сцены (`*.tscn`), старые шейдеры
(`*.gdshader`), ресурсы навмеша (`navmesh.tres`, `test_arena_navmesh.tres`), `audio/`,
`project.godot` и документы.
Пути в `preload("res://...")` указывают на сцены в корне — при переносе сцен их править.

## 2. Архитектурный рефакторинг (ветка `Refactoring`)
Было четыре файла-бога: `enemy.gd` (1862), `weapon_manager.gd` (1645), `player.gd` (1357),
`skill_manager.gd` (489) — цифры на `dfe7da8`, до рефакторинга. Один коммит на шаг.
Цифры ниже — `git show <commit>:<file>`, полные строки.
Имена файлов без папки в разделах 2–3 — как они лежали на момент коммита (до переноса в
`scripts/` в `5760953`/`0f13848` — в корне). Для `git show <старый коммит>:<файл>` нужен
старый путь, например `git show dfe7da8:enemy.gd`.

**Этап 1 — GameTypes и типизация** (`1b40191`, `6213d10`, `17c3998`, `dc736e6`, `0cbbe5c`)
- `scripts/core/game_types.gd` (autoload): enum `BPMTier {CALM, PUMPING, SURGING, OVERDRIVE}`
  + `tier_to_string()`; маски слоёв `LAYER_WORLD/PROJECTILE/PLAYER/ENEMY/ENEMY_HITBOX`
  (и `[layer_names]` 1..5 в project.godot); `resolve_damageable(collider)`,
  `resolve_enemy(node)`; `debug_log(category, msg)` с `DEBUG_ENABLED = false`.
- Все строковые тиры BPM → enum. Все 64 `print()` → `debug_log` (каналы `audio/bpm/enemy/player/weapon`).
- `class_name` добавлен на 16 скриптах корня (Player, Head, SkillManager, WeaponManager,
  BloodPool, BloodSplatter, ProjectileEnemy, Enemy + 8 подтипов врагов).
  `has_method` → `is ClassName` там, где тип однозначен.

**Этап 2 — TracerPool** (`94ddbaa`, `3223c0a`)
- `scripts/core/tracer_pool.gd` (autoload, 264 строки): кольцевой пул 64 трейсера + 16 сфер,
  стили `&"bullet"`, `&"pellet"`, `&"syringe"`, `&"needle"`, `&"piston"`, `&"piercing"`,
  `&"shrapnel"` и др. API: `TracerPool.spawn_tracer(start, end, style, variant)`.
- Удалено 8 дублированных функций трейсеров (7 в weapon_manager, 1 в enemy).
  weapon_manager.gd 1630 → 1174, enemy.gd 1873 → 1821.

**Этап 3 — компоненты и иерархия врагов** (`ab57289` … `3b2c682`)
- 3.1 `HealthComponent` (сигналы `damaged`, `died(info)`, `health_changed`).
- 3.2 `StatusEffectComponent` — яд, иглы, раздутие, замедление, детонации/цепи при смерти.
- 3.3 `EnemyHealthBar` — единая 3D-полоска HP (SubViewport + Sprite3D + Label3D).
- 3.4 `enemy.gd` разделён: `scripts/enemies/enemy_base.gd` (FSM, перцепция, урон/смерть,
  фасад компонентов, без гравитации и move_and_slide) + `enemy_ground.gd` (навигация,
  nav-link прыжки, lunge, wall_slam, гравитация). enemy.gd 1873 → 109.
- 3.5 Все девять типов перевешены: Enemy, Ranged, Bomber, Shield, Hunter, Swarm, Stalker →
  `extends EnemyGround`; Flyer → `extends EnemyBase` (935 → 483); Turret → `extends EnemyRanged`
  (337 → 307). Хуки `_process_telegraph`, `_process_firing`, `_get_projectile_spawn_position`,
  `_play_attack_flash`. Состояния `TELEGRAPH`/`FIRING` подняты в `EnemyBase.State`.
- Фиксы по ходу: сигнатура `die()` (`3703f2e`), вызовы статусов в наследниках (`d68dbda`),
  сигнатуры телеграфа (`f186344`), табы в турели (`b600e94`), твин/eyes_material турели
  (`6636c36`), рекурсия set_state ↔ _end_firing у летуна (`3b2c682`).

**Этап 4 — оружие** (`9ebd6f1`, `6937bc0`, `b965177`)
- 4.1 `WeaponData extends Resource` + `scripts/weapons/data/{caliber_0,anvil,injector,sewing_machine}.tres`
  вместо словарей. weapon_manager 1174 → 1113.
- 4.2 `WeaponBase` с общим `_apply_hit()` (трейсер, хедшот, airborne, стакинг множителей,
  вакуумный след, хук `_on_hit_target`).
- 4.3 `WeaponCaliber`, `WeaponAnvil`, `WeaponInjector`, `WeaponSewing`. Менеджер делегирует
  `w.fire()` / `w.alt_fire()`. weapon_manager 1113 → 306.

## 3. Этап 5 — ЗАКРЫТ. План рефакторинга выполнен целиком

**Итог рефакторинга.** Было четыре файла-бога: enemy.gd 1862, weapon_manager.gd 1645,
player.gd 1357, skill_manager.gd 489. Стало: enemy.gd 109, weapon_manager.gd 145,
player.gd 548 (после выноса wallrun), skill_manager.gd 255. Логика разнесена по компонентам (`scripts/components/`,
`scripts/player/`), базовым классам (`EnemyBase`/`EnemyGround`, `WeaponBase` + 4 оружия,
`WeaponData`), HUD (`scripts/ui/hud.gd`) и автозагрузкам (`GameTypes`, `TracerPool`, `GameManager`).

**5.1 Единый HUD — СДЕЛАНО** (`b966a92`, на момент написания последний коммит ветки).
`scripts/ui/hud.gd` (`class_name HUD extends CanvasLayer`, 436 строк) висит на узле `HUD`
в player.tscn, подключается к системам через `call_deferred("_connect_systems")`.
Сигналы: Player — `health_changed`, `died`, `speed_updated`, `blood_surf_status_changed`;
WeaponManager — `ammo_changed`, `weapon_switched`, `reload_started`, `reload_finished`;
SkillManager — `bpm_changed`, `tier_changed`, `momentum_changed`, `dash_charges_changed`,
`hud_popup_requested`. Путей `../HUD/*` в системах больше нет (проверено grep).
Строки: player.gd 1362 → 1274, weapon_manager.gd 306 → 146, skill_manager.gd 490 → 393.
Ручная проверка в игре после 5.1 мне неизвестна — уточнить у пользователя.

**5.2 Разбор player.gd — СДЕЛАНО** (`875132f`).
- `scripts/player/player_combat.gd` (`class_name PlayerCombat extends Node`, 521 строка):
  `perform_melee` (одиночный удар + конусная волна), execute-добивание, парирование
  (`_check_and_deflect_projectiles`, `_spawn_deflect_flash`, `_spawn_deflect_feedback`),
  `spawn_cone_shockwave_vfx`, все `@export` мили/конуса, `melee_timer` и `recent_peak_speed`
  (`tick_cooldown`, `track_peak_speed` зовутся из `Player._physics_process` в прежних точках кадра).
- `scripts/player/player_health.gd` (`class_name PlayerHealth extends Node`, 109 строк):
  `max_health`, `health`, `is_dead`, `take_damage`, `heal`, `_spawn_heal_feedback`, `die`,
  связь с GameManager (`trigger_game_over`, `game_over_triggered`, `restart_game`).
- Связь: узлы `PlayerHealth` и `PlayerCombat` — дети Player в player.tscn; Player держит
  прямые ссылки (`$PlayerHealth`, `$PlayerCombat`) и в `_ready()` вызывает `setup(self)`.
  `health` / `max_health` / `is_dead` на Player — проксирующие свойства; `take_damage`, `heal`,
  `restart_game` — делегирующие методы. Сигналы `health_changed` / `died` объявлены на Player
  и ретранслируются из PlayerHealth — HUD и внешний код не правились. Сброс движения при
  смерти — в `Player._on_health_died` (порядок прежний: HUD → сброс → `trigger_game_over`).
- Строки: player.gd 1274 → 720, player_combat.gd 521, player_health.gd 109.
- Цель ≤ 600 строк НЕ достигнута: в player.gd осталось только движение. Дальше сокращать
  можно лишь выносом wallrun в отдельный файл — кандидат на отдельный шаг, 5.3 не блокирует.

**5.3 BPM в единственного владельца — СДЕЛАНО** (`8372fc4`).
- `scripts/player/bpm_system.gd` (`class_name BPMSystem extends Node`, 164 строки), узел
  `BPMSystem` — ребёнок Player в player.tscn, `setup(self)` из `Player._ready()`. Перенесено
  побуквенно из skill_manager.gd: `bpm`, `MIN_BPM`/`MAX_BPM`, `time_since_bpm_gain`, пассивный
  спад, `add_bpm`, `record_kill_bpm` (+`last_kill_weapon`, бонус VARIETY), `drop_bpm_on_damage`,
  `force_max_bpm`, `get_bpm_tier`, моментум (`combat_momentum`, `time_since_momentum_gain`,
  `add_combat_momentum`, непрерывные источники и спад), `activate_blood_buff`/`has_blood_buff`.
  Из player.gd: `get_bpm_ratio`, `get_bpm_damage_reduction`, `has_infinite_ammo` (прокси удалены).
  `get_current_max_speed` остался в player.gd (логика движения), читает `bpm_system.get_bpm_ratio()`.
- Фоллбек `_get_bpm_tier()` удалён из weapon_base.gd; оружие читает
  `_get_player().bpm_system.get_bpm_tier()`.
- Все потребители переведены на `player.bpm_system`: враги (EnemyBase Fear Chain и выход из
  FLEE, EnemyGround, EnemyRanged, EnemyTurret, EnemyHunter — сырое `bpm >= 140.0`, начисление
  за убийство/хедшот), оружие, WeaponManager (INF-патроны автоогня), PlayerHealth, шейдер
  `overdrive_factor`, HUD. SkillManager — только дэш и слэм (+ `hud_popup_requested` для BLOOD SLAM).
- Строки: skill_manager.gd 393 → 255, player.gd 720 → 712, bpm_system.gd 164,
  weapon_base.gd 222 → 211.
- ВАЖНО: HUD НИКОГДА не был подписан на `bpm_changed` / `tier_changed` / `momentum_changed` —
  он каждый кадр читает `bpm_system.bpm`, `get_bpm_tier()`, `combat_momentum` в `_process`.
  Сигналы переехали в BPMSystem и подписчиков не имеют. Это не баг 5.1/5.3 — не «чинить»
  подписки, не разобравшись. HUD подписан только на `hud_popup_requested` обоих источников
  (VARIETY — BPMSystem, BLOOD SLAM — SkillManager).

**5.4 GameManager — СДЕЛАНО** (`b13ebeb` — очередь Инъектора, `49e6014` — GameManager).
- Схема: `Player._ready()` вызывает `GameManager.register_player(self)` (и после перезагрузки
  сцены); GameManager подписан на `Player.died` и сам решает о Game Over — `trigger_game_over()`
  переводит в `GAME_OVER`, освобождает курсор, эмитит `game_over_triggered` (HUD показывает экран).
  `PlayerHealth` о GameManager не знает — при смерти только эмитит `died`. Рестарт —
  `GameManager.restart_game()` (R в `GameManager._input` и кнопка HUD); `Player.restart_game()`
  удалён. Закомментированные заготовки (счёт, волны, пауза) и заглушки
  `activate_blood_buff`/`has_blood_buff` удалены.
- Строки: game_manager.gd 64 → 45, player_health.gd 109 → 86, bpm_system.gd 164 → 157,
  player.gd 712 → 713.
- Порядок при смерти внутри кадра сместился: теперь Game Over → HUD обнуляет HP → сброс
  движения (было: HUD → сброс → Game Over). Взаимных зависимостей нет.
- Попутные фиксы смерти (вне плана): автоогонь WeaponManager (`6761223`) и очередь
  Инъектора (`b13ebeb`) проверяют `is_dead`. Других отложенных по таймеру выстрелов нет.

**После плана — вынос wallrun — СДЕЛАНО** (`cc46074`).
- `scripts/player/player_wallrun.gd` (`class_name PlayerWallrun extends Node`, 199 строк), узел
  `PlayerWallrun`, `setup(self)`. Player зовёт его в прежних точках кадра: `tick_cooldown` →
  `update_entry_and_exit` → `process_wallrun_physics` → `on_landed`; прыжок со стены —
  `jump_off_wall(cap)`. Поля обычного wall-jump (`wall_jump_count/timer`, `last_wall_jump_normal`,
  `wall_jump_cooldown`) остались на Player.
- Строки: player.gd 710 → 548 (цель ≤ 600 достигнута), player_wallrun.gd 199.

**Каркас уровней — СДЕЛАНО** (`db15d7e` компоненты, `9b35090` чекпоинты, `ba4eb41` статистика и
экран конца, `19cf34f` демо-уровень). Описание и формула рейтинга — `docs/levels.md`.
- Враги секторов — точки спавна: сектор снимает их со сцены в `_enter_tree` (шаблоны) и создаёт при
  активации/новой волне через `EnemySpawnEffect` (враг появляется через 0.6 с). Механизм сна
  (`process_mode = DISABLED`) удалён. Без правок поведения врагов — не «чинить» врагов под сектор флагами.
- Охотник — необязательный: не входит в зачистку и счётчик «ВРАГИ» в HUD.
- Постоянный агр — признак `EnemyBase.persistent_aggro`, ставит сектор при спавне (не Охотнику); вне
  секторов `false`, поведение арены прежнее. Бюджет — около 160 живых врагов одновременно (замер в
  `docs/levels.md`), самая тяжёлая волна демо-уровня 60.
- Обнаружение игрока — проверка расстояния в коде (`EnemyBase._try_detect_player`, раз в 0.2 с со
  случайной фазой, условие `_can_detect_player`); сфер `DetectionArea` в сценах врагов нет — они давали
  квадратичную цену в физике. Не возвращать Area3D для «радиуса до игрока».
- Полоски HP врагов — отладка: клавиша H (`debug_toggle_hp_bars`), по умолчанию выключены, состояние —
  `GameManager.show_enemy_health_bars` на всю сессию. Выключены — `EnemyHealthBar` не создаётся вовсе
  (и не лежит в `enemy.tscn`). Полоска — квад-биллборд с шейдером `shaders/enemy_health_bar.gdshader`,
  общий материал, `instance uniform`. Особая полоска типа — через переопределение `_setup_health_bar()`;
  прокси `hp_sprite`/`hp_label`/`hp_bar`/`hp_viewport` на `EnemyBase` удалены, обращаться к `health_bar`
  (может быть `null`).
- Доработка по плейтесту: перегородки не падали из-за отсутствия `node_paths` в `demo_level.tscn`;
  выпавшие за уровень враги убираются сектором; свет демо-уровня — светлое окружение под чёрные силуэты.
- Смерть на уровне — возрождение на чекпоинте (`GameManager.restart_game` → `LevelController.respawn_player`
  → `Player.respawn`), перезапуск уровня — `GameManager.restart_level`. Вне уровня — перезапуск сцены.
- Демо-уровень запекает навмеш в рантайме (`bake_navigation_on_ready`); перегородки вне `NavigationRegion3D`.

**Отложено — очередь работ после рефакторинга:**
- **Расхождения документации с кодом** (выявлены при разбиении DESIGN.md, при переносе НЕ правились):
  - `docs/movement.md`, кровавая система: моментум кровавого сёрфа +0.05/сек, в коде +0.04 —
    решить, что правда; пути `enemy.gd` (создание лужи, теперь `enemy_base`) и `skill_manager.gd`
    без `scripts/`.
  - `docs/enemies.md`, `docs/enemy-types.md`: автомат состояний и описания типов ссылаются на
    `enemy.gd`; враги наследуются от `EnemyGround` / `EnemyBase` / `EnemyRanged`.
  - `docs/bpm.md`: `get_bpm_tier() -> String` — возвращает enum; «Тиры баффов» — по коду не реализовано ничего, кроме
    снижения урона и bhop-множителя: ни восполнение дэша, ни длительность wallrun
    (`wallrun_max_duration` — константа 1.2), ни ёмкость барабана, ни пассивная перезарядка,
    ни бонус урона от BPM не зависят. Решить: реализовать или убрать из описания.
  - `docs/bpm.md`, очки и лидерборд: счёт не реализован.
  - `docs/architecture*.md`: путь `res://enemy.gd` (3 места); в «Игрок» —
    «порядок прежний: HUD → сброс → trigger_game_over», после шага 5.4 порядок другой.
  - `docs/test-arena.md`: «22 врага: 17 melee, 3 ranged, 2 flyer»; фактически в
    `test_arena.tscn` 64 врага (17 обычных, 3 дальника, 2 летуна, 4 щитоносца, 5 бомберов,
    5 охотников, 4 турели, 21 рой, 3 соглядатая).
  - `docs/lessons.md`: в уроке про NavigationRegion `unreachable_timer >= 2.0с`, в коде
    `UNREACHABLE_TIMEOUT = 3.5`; уроки про Gemini CLI и `k` в `/tasks agy` — инструменты
    прошлого агента.
  - `docs/roadmap.md`: п.22 «Слэм + кровь — если ещё актуально» (кровавый слэм реализован);
    п.23 «выбор оружия 1/2 хардкодом» — сейчас хардкод клавиш 1–4; п.31 (REDLINE) «спецификация ниже» —
    теперь в `docs/redline.md`.
  - Внутренние ссылки вида «см. раздел 2/3» в тексте `docs/` указывают на нумерацию старого
    DESIGN.md.
- ~~`enemy_base.gd` (определение оружия-убийцы в `die`) ищет узел `"Weapons"` вместо
  `WeaponManager`~~ — исправлено в `7a85047`. Затрагивало только убийства, где ни один источник
  урона не пометил оружие (фоллбек давал `"unknown"`); обычные убийства и VARIETY работали.
- Довести использование именованных масок слоёв — `GameTypes.LAYER_*` объявлены (этап 1), но
  нигде не используются: в коде числом задана маска в `scripts/enemies/enemy_bomber.gd` (`collision_mask = 1`),
  остальные маски/слои выставлены числами в `.tscn`.
- (Необязательно) Перенос сцен и шейдеров из корня в `scenes/` и `shaders/` — ТОЛЬКО через
  редактор Godot, агент сломает ссылки в `.tscn`. После переноса поправить строковые пути в
  `preload("res://*.tscn")` (enemy_base, enemy_ranged, skill_manager, status_effect_component).
- Параметры ПКМ других оружий в коде мимо WeaponData (ПКМ Швейной уже в группе «Альт-огонь»).
  Решить, что выносить: часть — внутреннее устройство оружия и должна остаться в коде
  (геометрия веера, радиусы коллизий, длина луча), в ресурс — только настройки баланса.
  - Наковальня: `ALT_COOLDOWN` 1.2с, `PISTON_RANGE` 5.0м, `ENEMY_COL_RADIUS` 0.38, толчок 42 м/с,
    `FLOOR_SPLASH_RADIUS` 2.0м, цепочка самоподброса 1.0 → 0.6 → 0.35 (+ ~60 литералов в файле).
  - Инъектор: `ALT_COOLDOWN` 4.5с (раздутие). ЛКМ-параметры в коде: `BURST_COUNT` 3,
    `BURST_INTERVAL` 0.07с, яд 3.0с / 3 тика / 0.5с.
  - Калибр-0: свой кулдаун ПКМ не задан — `data.fire_rate` (фоллбек 0.45), гейт OVERDRIVE,
    расход всего барабана, `MAX_BEAM_DIST` 120м.
  - Швейная (остаток залпа): отдача 0.06/0.22, геометрия веера 0.34/±0.03/±0.16, отброс 1.5/0.5.

## 4. Правила работы
1. Поведение игры не меняется. Баланс, урон, скорости, тайминги, визуал — нетронуты.
   Константы переносятся побуквенно. Заметил баг — не правь, выпиши в отчёт.
2. Не перемещай существующие файлы между папками. Новые создавай сразу в нужной.
3. Не добавляй абстракций «на будущее».
4. Никаких `print()` — только `GameTypes.debug_log()`.
5. Один шаг = один коммит. В конце: компилируется, документация (`docs/`) обновлена, коммит сделан.
6. Строгий скоуп: только то, что описано в задаче.
7. Отчёт: файлы созданы/изменены/удалены; строк было → стало; что не удалось чисто;
   что заметил, но не тронул; конкретный чеклист ручной проверки в игре.
8. Технические решения принимаю сам: структура классов, способ реализации, порядок шагов,
   имена. Останавливаюсь и спрашиваю, только когда решение меняет то, как игра ощущается для
   игрока, и в задаче это не определено. Большую задачу делю на несколько коммитов по
   логическим этапам — после каждого компиляция проходит. Отчёт — в конце всей задачи, общим
   чеклистом проверки.

Ведение документации и коммитов (правила перенесены из удалённого GEMINI.md):
- Перед задачей читать DESIGN.md (оглавление) и файлы `docs/`, относящиеся к задаче — это
  источник истины о состоянии проекта.
- После задачи, меняющей механику/систему/архитектуру, обновить релевантный файл `docs/`:
  перенос фич из TODO/roadmap в «✅ Реализован» с финальными параметрами, новые уроки — в
  `docs/lessons.md` (и строкой в §6 ниже), обновить `docs/roadmap.md`. Править только
  релевантные разделы, не переписывать файл. Новый тематический файл в `docs/` — добавить
  строку в оглавление DESIGN.md.
- Сообщения коммитов — на английском, осмысленные (стиль ветки: `refactor:`, `feat:`, `fix:`, `chore:`).
- Баг-фиксы/правки баланса можно не коммитить каждый раз, но обязательно закоммитить
  ПЕРЕД началом крупной новой фичи (точка отката).

## 5. Проверка
Компиляция всего проекта — единственная надёжная команда:
```
cmd.exe /c "godot.windows.opt.tools.64.exe --headless -e --quit --path E:\Project\voidkill 2>&1"
```
(бинарник в PATH: `E:\SteamLibrary\steamapps\common\Godot Engine\`)
- `-e` запускает редактор → полное сканирование и компиляция ВСЕХ скриптов. Без него
  парсятся только скрипты из загруженной сцены и её зависимостей (враги вне world.tscn
  не проверятся).
- `cmd.exe /c ... 2>&1` обязательно: GUI-бинарник (`SUBSYSTEM:WINDOWS`) не отдаёт
  stdout/stderr в PowerShell напрямую. Без обёртки вывод пустой — легко отчитаться
  «0 ошибок» на сломанном проекте.
- `--check-only` НЕ использовать: проверяет файлы по отдельности и не ловит несовпадение
  сигнатур между базой и наследниками.

Рантайм-ошибки (10 секунд арены):
```
cmd.exe /c "godot.windows.opt.tools.64.exe --headless -d --quit-after 600 test_arena.tscn --path E:\Project\voidkill 2>&1"
```

Запреты:
- Не писать собственные headless-тесты, инстанцирующие сцены — виснут вне игрового цикла
  (проверено дважды).
- Не выполнять `git push` / `pull` / `clone` — интерактивные, просят авторизацию в браузере,
  агент зависает.

## 6. Грабли, на которые уже наступали
Короткий список-правило. Подробности — в [docs/lessons.md](docs/lessons.md), урок указан в «кавычках».
- Сигнатуры переопределений совпадают побуквенно у всех наследников; после правки базы — grep по
  наследникам и компиляция `-e` («Сигнатуры переопределяемых методов (GDScript override)…»).
- Хук очистки FSM гасит визуал и таймеры, но НЕ меняет состояние («Разрыв циклических
  зависимостей при смене состояний FSM…»).
- Отступы только табами («Отступы только табами»).
- `.uid` файлы коммитятся («`.uid` файлы коммитятся»).
- Вынося метод в компонент — grep всех вызывающих, фасад на базовом классе («Делегирование
  методов базового класса при выносе в компоненты…»).
- Состояние уехало в компонент — поле на владельце делается прокси-свойством («Проксирующие свойства»).
- Строковые проверки (`"x" in obj`, `has_method`) молчат при переезде — искать по строковым
  именам («Утиная типизация не ловится компилятором при переносе полей»).
- При переносе поля проверять ВСЕ чтения, не только запись («Чтение со старого места после
  переноса поля в компонент»).
- `exclude` в физ-запросах принимает и узлы, и RID — не «чинить» («`exclude` в физ-запросах»).
- Дети готовы раньше родителя; подписка на соседей — через `call_deferred` («Декаплинг HUD от
  игровых систем и порядок инициализации…»).
- Вынося тики в компонент, удалять их и у наследников без `super._physics_process` («Вынос
  компонентной логики с таймерами и наследники…»).
- Tween создавать до проверок опциональных узлов («Порядок создания Tween…»).
- `.tscn` без `#`-комментариев; `.gd`/`.tscn` не писать через PowerShell here-string («Синтаксис
  файлов сцен Godot…», «PowerShell срезает внутренние двойные кавычки…»).
- Тернарник `StringName` vs `String` — приводить `String(node.name)`; неиспользуемые параметры
  сигнатур — с `_` («Предупреждения компилятора GDScript…»).
- Автозагрузкам — без `class_name` («Автозагрузки и `class_name`»).
- `global_position` снаряда — только после `add_child()` («Спавн снарядов и `global_position`
  до `add_child()`»).
- Наследник не может переобъявить `enum` базы («Переопределение `enum` в наследниках GDScript»).
- Состояния enum никогда не сравниваются с числами — только значение enum; из компонента,
  которым владеет класс, — через экземпляр (`actor.State.X`), не через имя класса: иначе цикл
  зависимостей скриптов и утечки при выходе («Состояния enum никогда не сравниваются с числами»).
- Параметры навмеша менять только с перезапеканием («Параметры baking navmesh»).
- Экспорт узла в рукописном `.tscn` — только с `node_paths=PackedStringArray("имя")` в заголовке узла,
  иначе молча `null` («Экспорт узла в рукописном `.tscn` требует `node_paths`»).
- Рантайм-навмеш отдавать региону копией после первой итерации карты, иначе карта пуста («Рантайм-
  запекание навмеша и асинхронные итерации…»).
- `overlaps_body` после телепорта устаревает на шаг физики («Перекрытие `Area3D` после телепорта…»).
- Униформы шейдера твинить через `set_shader_parameter`, не `shader_parameter/…` («Свойства
  `shader_parameter/<имя>`…»).
- Визуальная проверка — Movie Maker (`--write-movie`), временную сцену после удалить («Movie Maker…»).

## 7. Git
Работаем прямо в `main` (ветка `Refactoring` влита fast-forward, отдельные ветки для мелких
независимых задач не нужны). Репозиторий: https://github.com/ggou3/voidkill
