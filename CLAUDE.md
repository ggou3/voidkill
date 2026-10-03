# VOIDKILL — контекст для Claude

## 1. Что за проект
3D boomer-shooter на Godot 4.7, GDScript. Ядро — кровь (лужи, кровавый сёрф/слэм),
скорость (bhop, wallrun, slide) и BPM-система (сердцебиение 50–200, тиры
CALM/PUMPING/SURGING/OVERDRIVE). Источник истины по дизайну и архитектуре — `DESIGN.md`
(раздел 7 «Архитектура», 8 «Технические уроки», 9 «Roadmap»). Тестовый уровень —
`test_arena.tscn`, главная сцена — `world.tscn`.

Autoload (project.godot): `GameTypes`, `GameManager`, `AudioManager`, `TracerPool`.
Скриптам-автозагрузкам `class_name` НЕ добавлять (конфликт с именем синглтона).

Раскладка: часть скриптов и все `.tscn` в корне `res://` (player.gd, weapon_manager.gd,
skill_manager.gd, head.gd, enemy*.gd, projectile_enemy.gd, blood_*.gd). Новое — в `scripts/`:
`core/` (game_types, tracer_pool), `components/` (health_component, status_effect_component,
enemy_health_bar), `enemies/` (enemy_base, enemy_ground), `weapons/` (weapon_data, weapon_base,
weapon_caliber/anvil/injector/sewing, `data/*.tres`), `ui/` (hud.gd), плюс
`audio_manager.gd`, `game_manager.gd`.

## 2. Архитектурный рефакторинг (ветка `Refactoring`)
Было четыре файла-бога: `enemy.gd` (1862), `weapon_manager.gd` (1645), `player.gd` (1357),
`skill_manager.gd` (489) — цифры на `dfe7da8`, до рефакторинга. Один коммит на шаг.
Цифры ниже — `git show <commit>:<file>`, полные строки.

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

## 3. Этап 5 — состояние и что осталось

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

**5.3 BPM в единственного владельца.** Вынести BPM из skill_manager.gd в
`scripts/player/bpm_system.gd`. Разбор «прокси» в player.gd:
- `has_infinite_ammo` — чистый прокси (тир == OVERDRIVE у SkillManager).
- `get_bpm_ratio` — логика BPM (нормализация `(bpm-50)/150`), место в BPM-системе.
- `get_current_max_speed` — логика движения (lerp `normal_max_speed`→`blood_buffed_max_speed`
  по ratio), остаётся в player.gd.
- `get_bpm_damage_reduction` — правило баланса, ближе к PlayerHealth или BPM-системе.

Фоллбек `_get_bpm_tier()` после этапа 4 живёт уже не в
weapon_manager, а в `scripts/weapons/weapon_base.gd` (ищет `../SkillManager`, затем `player.skills`).

**5.4 GameManager.** Перенести Game Over и рестарт из `scripts/player/player_health.gd`
(`die` → `gm.trigger_game_over()`, `_on_game_over_triggered`, `restart_game`), удалить закомментированные заготовки
в `scripts/game_manager.gd` (score, current_wave, enemies_alive, PAUSED, add_score,
start_next_wave, toggle_pause). Счёт не реализован (есть только в roadmap DESIGN.md) — это
будущая фича, не рефакторинг; в 5.4 его не трогаем.

**Отложено (не блокирует этап 5):**
- Часть скриптов и все `.tscn` в корне. Перемещать ТОЛЬКО через редактор Godot —
  агент сломает ссылки в `.tscn`.
- DESIGN.md разросся: 138 КБ на начало рефакторинга → ~190 КБ (дописывали после каждого
  шага) — стоит разбить.
- ПКМ Швейной машины захардкожен мимо WeaponData (`weapon_sewing.gd`: `ALT_COOLDOWN`,
  `BARRAGE_AMMO_COST`, `NEEDLE_COUNT`, `NEEDLE_DAMAGE`).
- `was_killed_by_melee` / `was_killed_by_shockwave` / `last_damage_weapon` дублируются:
  в `HealthComponent`, в словаре сигнала `died` и полями на `EnemyBase`.
- Баг (не правился по правилу 1): `exclude` в физ-запросах мили и парирования
  (`player_combat.gd`) получает узлы вместо `Array[RID]` — исключение не срабатывает;
  маскируется тем, что луч стартует внутри капсулы игрока. Правильно — `[player.get_rid()]`.
- Мёртвая переменная `_gained` в `PlayerHealth.heal()`.

## 4. Правила работы
1. Поведение игры не меняется. Баланс, урон, скорости, тайминги, визуал — нетронуты.
   Константы переносятся побуквенно. Заметил баг — не правь, выпиши в отчёт.
2. Не перемещай существующие файлы между папками. Новые создавай сразу в нужной.
3. Не добавляй абстракций «на будущее».
4. Никаких `print()` — только `GameTypes.debug_log()`.
5. Один шаг = один коммит. В конце: компилируется, DESIGN.md обновлён, коммит сделан.
6. Строгий скоуп: только то, что описано в задаче.
7. Отчёт: файлы созданы/изменены/удалены; строк было → стало; что не удалось чисто;
   что заметил, но не тронул; конкретный чеклист ручной проверки в игре.

Унаследовано из GEMINI.md (сохранять):
- Перед задачей читать DESIGN.md — это источник истины о состоянии проекта.
- После задачи, меняющей механику/систему/архитектуру, обновить релевантный раздел DESIGN.md:
  перенос фич из TODO/roadmap в «✅ Реализован» с финальными параметрами, новые уроки — в
  раздел 8, обновить roadmap. Править только релевантные разделы, не переписывать файл.
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
- **Сигнатуры переопределений** должны совпадать побуквенно у всех наследников (число, типы
  параметров, тип возврата). Ловилось трижды: `die()`, `_process_telegraph()`, `take_damage()`.
  После изменения базового метода — grep по наследникам и полная компиляция `-e`.
- **Рекурсия в FSM**: `set_state()` звал хук очистки, хук звал `set_state()` → stack overflow.
  Правило: хук очистки гасит визуал и таймеры, но НЕ меняет состояние; сначала
  `super.set_state()`, потом проверка `old_state`.
- **Отступы только табами** — пробелы ломают парсер.
- **`.uid` файлы коммитятся** — без них теряются связи.
- **Вынос метода в компонент** — grep всех вызывающих, включая наследников (ловилось на
  `_spawn_explosion_shockwave`, его звал бомбер). Оставлять фасад на базовом классе.
- **Проксирующие свойства**: когда состояние уезжает в компонент, поле на владельце
  оформляется свойством с get/set к компоненту — внешний код (`e.health`, `e.needle_count`,
  `"health" in e`) работает без правок. Сработало четыре раза.
- **Порядок `_ready()`**: дочерние узлы готовы раньше родителя; HUD подключается через
  `call_deferred`.
- **Таймеры компонентов**: при выносе тиков в компонент удалять циклы и у наследников без
  `super._physics_process` (stalker), иначе двойной тик.
- **Tween** создавать до проверок опциональных узлов (иначе null при отсутствии первого).
- **`.tscn`** не поддерживает `#`-комментарии; не писать `.gd`/`.tscn` через PowerShell
  here-string — режет кавычки. Только инструментами редактирования.
- **Тернарник** `StringName` vs `String` несовместим — приводить `String(node.name)`.
  Неиспользуемые параметры обязательных сигнатур — с `_`.

## 7. Git
Ветка `Refactoring` от `main` (merge-base `3223c0a` — этапы 1–2 уже есть и в main).
Репозиторий: https://github.com/ggou3/voidkill
