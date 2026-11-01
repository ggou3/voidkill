# Архитектура: основа

← [Оглавление: DESIGN.md](../DESIGN.md)

## Архитектура

### Autoload-синглтоны
- **GameManager** (`res://scripts/game_manager.gd`) — состояние игры (PLAYING/GAME_OVER),
  `trigger_game_over()`, `restart_game()`, рестарт по действию `restart` (R) в `_input`. ✅ Шаг 5.4: единственный владелец
  жизненного цикла игры. Игрок вызывает `register_player(self)` из `Player._ready()` (в т.ч. после
  перезагрузки сцены), GameManager подписывается на `Player.died` и сам решает о Game Over:
  `trigger_game_over()` переводит в `GAME_OVER`, освобождает курсор и эмитит `game_over_triggered`
  (на него подписан HUD — экран Game Over). Закомментированные заготовки (score, волны, пауза) удалены —
  вернуть при реализации соответствующих фич из roadmap.
  - **Уровни** (каркас уровней, см. [levels.md](levels.md)): `LevelController` регистрируется через
    `register_level()`. Тогда `restart_game()` (R / «Возродиться») — возрождение на последнем
    чекпоинте (`level.respawn_player`, сигнал `player_respawned`), а `restart_level()` — перезагрузка
    сцены. Состояние `LEVEL_COMPLETE`: `complete_level()` (из `LevelExit`, только при всех
    зачищенных секторах) ставит дерево на паузу и эмитит `level_completed(stats)`. Статистика
    уровня: `level_time`, `kills`, `damage_taken`, `overdrive_time`, `deaths`. Вне уровня (`level`
    не зарегистрирован) поведение прежнее — перезапуск сцены.
  - **Стоп-кадр** `hit_stop(duration)` — единственное место, где меняется `Engine.time_scale`
    (подробности — [combat.md](combat.md)). Токены атак врагов считаются в игровом времени
    (`_game_time`, замедляется стоп-кадром вместе с атаками), остановка звуков `AudioManager` — в
    реальном (звук стоп-кадр не замедляет).
  - **Отладочные клавиши** T (`debug_max_bpm`) и H (`debug_toggle_hp_bars`) работают только в
    отладочной сборке (`OS.is_debug_build()`: запуск из редактора), в релизном экспорте выключены.
  - **Интерполяция физики**: в `_ready` выключает её корню дерева — интерполируются только узлы, которые
    включают её себе сами (тело игрока, враги, вражеские снаряды), см. урок в [lessons.md](lessons.md).
  - ВАЖНО: скрипт НЕ должен иметь `class_name GameManager` — конфликтует с именем автозагрузки.
- **AudioManager** (`res://scripts/audio_manager.gd`) — процедурная генерация звуков через
  `AudioStreamGenerator` (без внешних аудиофайлов). `AudioManager.play_sound(sound_name: String)`,
  зацикленный слайд — `set_slide_active(active)`. Все звуки идут в шину `Master`.
  Реализованы (25): revolver_shot, shotgun_shot, injector_shot, flask_throw, flask_splash, explosion,
  player_heal, melee_hit, melee_heavy_hit, dash, slam_impact, jump, footstep, enemy_hit, enemy_death,
  reload, slide (зацикленный, тихий), dry_fire, rail_shot, needle_shot, parry_deflect, shield_block,
  bomber_tick, hunter_awaken, stalker_reveal.
  Пул из 16 плееров. Частые звуки (выстрелы, попадания, шаги, прыжок, дэш, смерти, взрывы) играют со
  случайной высотой ±3–8% (`PITCH_VARIATION`) против «пулемётного эффекта». Одного звука одновременно
  звучит не больше 4 копий (`MAX_VOICES_PER_SOUND`): сверх лимита перезапускается самая старая копия.
  Архитектура позволяет заменить процедурные звуки на настоящие файлы позже без переписывания
  вызовов `play_sound()`.
  - **Звук в точке мира** `play_sound_at(sound_name, world_pos)` — пул из 16 `AudioStreamPlayer3D`
    (`unit_size` 8 м, `max_distance` 60 м), тот же лимит копий и вариации высоты. Для угроз: телеграфы и
    атаки врагов (таблица — [enemies.md](enemies.md)). Звуки игрока и интерфейса — `play_sound` (2D).
  - **Приоритет телеграфов** (`PRIORITY_SOUNDS`): когда свободных плееров нет, вытесняется самый старый
    не-телеграф (смерть, взрыв), а телеграф — только если играют одни телеграфы. Сюда же входят
    `bomber_tick` и `stalker_reveal`.
  - Звуки врагов (9): melee_windup, swarm_windup, lunge_windup, lunge_dash, ranged_windup, ranged_shot,
    turret_windup, flyer_charge, flyer_laser. Телеграфы — восходящий тон в средней полосе (выстрелы игрока,
    наоборот, падают по высоте), выстрел дальника — мягкий низкий «туп» без щелчка.
  - Остановка плеера по концу буфера — таймер в реальном времени (стоп-кадр звук не замедляет).
- **GameTypes** (`res://scripts/core/game_types.gd`) — глобальные общие типы данных, enum `BPMTier` (`CALM`, `PUMPING`, `SURGING`, `OVERDRIVE`), функция `tier_to_string(tier)`, именованные битовые маски слоёв 3D-коллизий (`LAYER_WORLD`, `LAYER_PROJECTILE`, `LAYER_PLAYER`, `LAYER_ENEMY`, `LAYER_ENEMY_HITBOX`), методы `resolve_damageable(collider)` и `resolve_enemy(node)` для надёжного и унифицированного разрешения узлов целей с `take_damage` и проверкой принадлежности к врагам (включая дочерние хитбоксы `HeadHitbox` и метаданные `"enemy"`), а также функция централизованного отладочного логирования `debug_log(category, msg)` с флагом `DEBUG_ENABLED = false`. Методы объявлены как обычные методы экземпляра (без `static`), чтобы исключить предупреждения GDScript при вызове через автозагрузку-синглтон `GameTypes`.
  - ВАЖНО: скрипт НЕ должен иметь `class_name GameTypes` — конфликтует с именем автозагрузки.
  - В `project.godot` прописаны имена слоёв `[layer_names]` (3d_physics 1..5: `world`, `projectile`, `player`, `enemy`, `enemy_hitbox`).
  - Все сравнения тиров BPM переведены со строковых литералов на enum `GameTypes.BPMTier` (сейчас — `bpm_system.gd`, `weapon_base.gd`, `weapon_caliber.gd`, `game_manager.gd`). Охотник сравнивает сырое значение BPM с порогом `surging_threshold = 140.0`. Строка тира — только через `GameTypes.tier_to_string()`: в HUD и в отладочном логе `BPMSystem`.
- **TracerPool** (`res://scripts/core/tracer_pool.gd`) — циклический пул для рендеринга трейсеров выстрелов (`POOL_SIZE = 64`) и сопутствующих сфер попадания (`SPHERE_POOL_SIZE = 16`). Исключает динамические аллокации `SurfaceTool`, `ArrayMesh` и `StandardMaterial3D` во время боя. Поддерживает стили `&"bullet"`, `&"pellet"`, `&"syringe"`, `&"needle"`, `&"piston"`, `&"piston_self"`, `&"piercing"`, `&"inflate"`, `&"shrapnel"`, `&"shrapnel_blood"`. Материалы и меши предсоздаются один раз при инициализации; индивидуальное затухание каждого экземпляра реализуется через покадровый tween `transparency` на уровне `GeometryInstance3D`.
  - ВАЖНО: скрипт НЕ должен иметь `class_name TracerPool` — конфликтует с именем автозагрузки.
  - **Миграция вызовов (Шаг 2.2 ✅ Реализован)**: все 11 точек спавна трейсеров тогдашних `weapon_manager.gd` и `enemy.gd` переведены на `TracerPool.spawn_tracer(start, end, style, variant)`; удалено 509 строк дублирующего кода. Сейчас вызовы `spawn_tracer` — в классах оружия `scripts/weapons/weapon_*.gd` и в `scripts/components/status_effect_component.gd` (разлёт игл).
  - Сопутствующие сферы попадания (piston, piercing) создаются исключительно через предвыделенный пул сфер `TracerPool`.
  - Физическая механика вакуумного следа — `WeaponBase._apply_vacuum_wake()` (`scripts/weapons/weapon_base.gd`), независимо от пула.

### Именование типов (class_name) и типизация
- **Глобальные имена классов (`class_name`)**: объявлены в PascalCase у всех скриптов, кроме автозагрузок (37 классов):
  - Игрок и HUD: `Player`, `Head`, `SkillManager`, `BPMSystem`, `PlayerHealth`, `PlayerCombat`, `PlayerWallrun`, `HUD`.
  - Оружие: `WeaponManager`, `WeaponData`, `WeaponBase`, `WeaponCaliber`, `WeaponAnvil`, `WeaponInjector`, `WeaponSewing`.
  - Компоненты: `HealthComponent`, `StatusEffectComponent`, `EnemyHealthBar`.
  - Эффекты и снаряды: `BloodPool`, `BloodSplatter`, `EnemySpawnEffect`, `ProjectileEnemy`.
  - Уровни: `LevelController`, `Sector`, `BloodBarrier`, `LevelExit`.
  - Враги: базовые классы `EnemyBase`, `EnemyGround`, базовый ближний враг `Enemy` и специализированные подтипы `EnemyFlyer`, `EnemyRanged`, `EnemyTurret`, `EnemyBomber`, `EnemyShield`, `EnemyHunter`, `EnemySwarm`, `EnemyStalker`.
  - Autoload-синглтонам (`GameManager`, `AudioManager`, `GameTypes`, `TracerPool`) `class_name` категорически НЕ добавляется, чтобы исключить конфликты затенения глобальных синглтонов ("Class X hides an autoload singleton").
- **Проверки типов через `is ClassName`**: проверки объектов с однозначно известным конкретным типом переведены с утиной типизации (`has_method(...)`) на строгую проверку типа (`pool is BloodPool`, `skills is SkillManager`, `player_node is Player`, `proj is ProjectileEnemy`). Универсальная утиная типизация сохранена исключительно для полиморфных интерфейсов урона (`has_method("take_damage")`), групп и централизованных резолверов `GameTypes.resolve_damageable()` и `GameTypes.resolve_enemy()`.

### Централизованное отладочное логирование (GameTypes.debug_log)
- Все прямые вызовы `print(...)` по проекту (64 вызова на момент миграции) переведены на канальное логирование `GameTypes.debug_log(category: StringName, msg: String)`.
- **Категории логирования**: `&"audio"`, `&"bpm"`, `&"enemy"`, `&"player"`, `&"weapon"`.
- При выключенном флаге `GameTypes.DEBUG_ENABLED = false` консольный спам полностью устранён, при этом сохранена возможность точечного включения каналов отладки без модификации исходного кода. Единственный прямой вызов `print()` в проекте изолирован внутри реализации `GameTypes.debug_log()`.

### Звук
- Полноценные аудиофайлы пока не подключены (пользователь искал на Kenney.nl/Freesound.org,
  список нужных файлов был составлен, но решено пока обойтись процедурными звуками).

