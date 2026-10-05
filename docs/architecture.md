# Архитектура: основа

← [Оглавление: DESIGN.md](../DESIGN.md)

## 7. Архитектура

### Autoload-синглтоны
- **GameManager** (`res://scripts/game_manager.gd`) — состояние игры (PLAYING/GAME_OVER),
  `trigger_game_over()`, `restart_game()`, рестарт по R в `_input`. ✅ Шаг 5.4: единственный владелец
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
  - ВАЖНО: скрипт НЕ должен иметь `class_name GameManager` — конфликтует с именем автозагрузки.
- **AudioManager** (`res://scripts/audio_manager.gd`) — процедурная генерация звуков через
  `AudioStreamGenerator` (без внешних аудиофайлов). `AudioManager.play_sound(name: String)`.
  Реализованы: revolver_shot, shotgun_shot, melee_hit, melee_heavy_hit, dash, slam_impact, jump,
  footstep, enemy_hit, enemy_death, reload, slide (зацикленный, тихий).
  Архитектура позволяет заменить процедурные звуки на настоящие файлы позже без переписывания
  вызовов `play_sound()`.
- **GameTypes** (`res://scripts/core/game_types.gd`) — глобальные общие типы данных, enum `BPMTier` (`CALM`, `PUMPING`, `SURGING`, `OVERDRIVE`), функция `tier_to_string(tier)`, именованные битовые маски слоёв 3D-коллизий (`LAYER_WORLD`, `LAYER_PROJECTILE`, `LAYER_PLAYER`, `LAYER_ENEMY`, `LAYER_ENEMY_HITBOX`), методы `resolve_damageable(collider)` и `resolve_enemy(node)` для надёжного и унифицированного разрешения узлов целей с `take_damage` и проверкой принадлежности к врагам (включая дочерние хитбоксы `HeadHitbox` и метаданные `"enemy"`), а также функция централизованного отладочного логирования `debug_log(category, msg)` с флагом `DEBUG_ENABLED = false`. Методы объявлены как обычные методы экземпляра (без `static`), чтобы исключить предупреждения GDScript при вызове через автозагрузку-синглтон `GameTypes`.
  - ВАЖНО: скрипт НЕ должен иметь `class_name GameTypes` — конфликтует с именем автозагрузки.
  - В `project.godot` прописаны имена слоёв `[layer_names]` (3d_physics 1..5: `world`, `projectile`, `player`, `enemy`, `enemy_hitbox`).
  - Все сравнения тиров BPM в кодовой базе (`skill_manager.gd`, `weapon_manager.gd`, `player.gd`, `enemy*.gd`) переведены со строковых литералов на enum `GameTypes.BPMTier`. Преобразование в строку изолировано исключительно в точке отрисовки HUD через `GameTypes.tier_to_string()`.
- **TracerPool** (`res://scripts/core/tracer_pool.gd`) — циклический пул для рендеринга трейсеров выстрелов (`POOL_SIZE = 64`) и сопутствующих сфер попадания (`SPHERE_POOL_SIZE = 16`). Исключает динамические аллокации `SurfaceTool`, `ArrayMesh` и `StandardMaterial3D` во время боя. Поддерживает стили `&"bullet"`, `&"pellet"`, `&"syringe"`, `&"needle"`, `&"piston"`, `&"piston_self"`, `&"piercing"`, `&"inflate"`, `&"shrapnel"`, `&"shrapnel_blood"`. Материалы и меши предсоздаются один раз при инициализации; индивидуальное затухание каждого экземпляра реализуется через покадровый tween `transparency` на уровне `GeometryInstance3D`.
  - ВАЖНО: скрипт НЕ должен иметь `class_name TracerPool` — конфликтует с именем автозагрузки.
  - **Миграция вызовов (Шаг 2.2 ✅ Реализован)**: все 11 точек спавна трейсеров в `weapon_manager.gd` и `enemy.gd` переведены на `TracerPool.spawn_tracer(start, end, style, variant)`. Удалены все 7 дублирующих функций из `weapon_manager.gd` (net -456 строк) и функция `_spawn_needle_shrapnel_tracer` из `enemy.gd` (net -53 строки) — суммарно удалено 509 строк дублирующего кода.
  - Сопутствующие сферы попадания (piston, piercing) создаются исключительно через предвыделенный пул сфер `TracerPool`.
  - Физическая механика `apply_vacuum_wake()` сохранена независимой в `weapon_manager.gd`.

### Именование типов (class_name) и типизация
- **Глобальные имена классов (`class_name`)**: объявлены в PascalCase для всех 17 ключевых классов сущностей:
  - Сущности, компоненты и менеджеры: `Player`, `Head`, `SkillManager`, `WeaponManager`, `HealthComponent`, `StatusEffectComponent`, `EnemyHealthBar`.
  - Эффекты и снаряды: `BloodPool`, `BloodSplatter`, `ProjectileEnemy`.
  - Враги: базовые классы `EnemyBase`, `EnemyGround`, базовый ближний враг `Enemy` и специализированные подтипы `EnemyFlyer`, `EnemyRanged`, `EnemyTurret`, `EnemyBomber`, `EnemyShield`, `EnemyHunter`, `EnemySwarm`, `EnemyStalker`.
  - Autoload-синглтонам (`GameManager`, `AudioManager`, `GameTypes`) `class_name` категорически НЕ добавляется, чтобы исключить конфликты затенения глобальных синглтонов ("Class X hides an autoload singleton").
- **Проверки типов через `is ClassName`**: проверки объектов с однозначно известным конкретным типом переведены с утиной типизации (`has_method(...)`) на строгую проверку типа (`pool is BloodPool`, `skills is SkillManager`, `player_node is Player`, `proj is ProjectileEnemy`). Универсальная утиная типизация сохранена исключительно для полиморфных интерфейсов урона (`has_method("take_damage")`), групп и централизованных резолверов `GameTypes.resolve_damageable()` и `GameTypes.resolve_enemy()`.

### Централизованное отладочное логирование (GameTypes.debug_log)
- Все прямые вызовы `print(...)` по проекту (64 вызова) переведены на канальное логирование `GameTypes.debug_log(category: StringName, msg: String)`.
- **Категории логирования**: `&"audio"`, `&"bpm"`, `&"enemy"`, `&"player"`, `&"weapon"`.
- При выключенном флаге `GameTypes.DEBUG_ENABLED = false` консольный спам полностью устранён, при этом сохранена возможность точечного включения каналов отладки без модификации исходного кода. Единственный прямой вызов `print()` в проекте изолирован внутри реализации `GameTypes.debug_log()`.

### Звук
- Полноценные аудиофайлы пока не подключены (пользователь искал на Kenney.nl/Freesound.org,
  список нужных файлов был составлен, но решено пока обойтись процедурными звуками).

