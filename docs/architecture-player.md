# Архитектура: игрок и HUD

← [Оглавление: DESIGN.md](../DESIGN.md)

### Игрок (`player.gd` + компоненты `scripts/player/`) — разделение на движение, бой и здоровье ✅ Реализован (Шаг 5.2)
- **`player.gd`** (`class_name Player`, 569 строк, было 1274): движение — ходьба, слайд, bhop, обычный wall-jump, coyote/jump buffer, приземление, шаги, blood-состояния, ввод. Из BPM-методов остался только `get_current_max_speed()` (логика движения; доля BPM читается из `bpm_system`).
- **`PlayerWallrun`** (`res://scripts/player/player_wallrun.gd`, `class_name PlayerWallrun extends Node`, узел `PlayerWallrun` в `player.tscn`, 198 строк): состояние wallrun (`is_wallrunning`, `wallrun_side`, `wallrun_timer`, `wallrun_normal`, `wallrun_cooldown`, `last_wallrun_normal`, `wallrun_exhausted`), `@export`-параметры (`wallrun_min_speed`, `wallrun_speed`, `wallrun_max_duration`, `wallrun_jump_vertical_boost`, `wallrun_jump_horizontal_boost`), лучи `LeftWallRay`/`RightWallRay`, `check_wallrun_wall`, `start_wallrun`, `end_wallrun`, `process_wallrun_physics`, прыжок со стены `jump_off_wall(cap)`. Player вызывает компонент в прежних точках кадра: `tick_cooldown` → `update_entry_and_exit` (вход + выход при дэше/слэме, до приседа/гравитации/прыжка) → `process_wallrun_physics` (ветка движения) → `on_landed` (после `move_and_slide`). Общие для обычного wall-jump поля (`wall_jump_count`, `wall_jump_timer`, `last_wall_jump_normal`, `@export wall_jump_cooldown`) остались на Player. Длительность wallrun от BPM не зависит (`wallrun_max_duration = 1.2` постоянна) — «продлённая длительность wallrun» из тиров баффов ([bpm.md](bpm.md)) не реализована.
- **`PlayerHealth`** (`res://scripts/player/player_health.gd`, `class_name PlayerHealth extends Node`, узел `PlayerHealth` в `player.tscn`): `max_health`, `health`, `is_dead`, `take_damage(amount, knockback, hit_pos, bpm_penalty = true)` (со снижением урона от BPM и сбросом BPM; `bpm_penalty = false` — без сброса, повторные тики одного залпа лазера летуна), `heal` + всплывающий `+N HP`, `die`. Сигналы `health_changed(current, maximum)`, `died` и `damaged(amount, from_dir)` (индикатор направления урона; ретранслируется на Player). С Шага 5.4 о GameManager не знает: при смерти только эмитит `died`.
- **`PlayerCombat`** (`res://scripts/player/player_combat.gd`, `class_name PlayerCombat extends Node`, узел `PlayerCombat` в `player.tscn`): `perform_melee` (одиночный удар и конусная ударная волна), execute-добивание, парирование снарядов (`_check_and_deflect_projectiles`, `_spawn_deflect_flash`, `_spawn_deflect_feedback`), VFX конуса, все `@export`-параметры мили/конуса, кулдаун `melee_timer` и трекинг пиковой скорости `recent_peak_speed` (`tick_cooldown`, `track_peak_speed` вызываются из `Player._physics_process` в прежних точках кадра).
- **`BPMSystem`** (`res://scripts/player/bpm_system.gd`, `class_name BPMSystem extends Node`, узел `BPMSystem` в `player.tscn`) — ✅ Шаг 5.3, единственный владелец BPM: `bpm`, `MIN_BPM`/`MAX_BPM`, пассивный спад, `add_bpm`, `record_kill_bpm` (+бонус разнообразия, `last_kill_weapon`), `drop_bpm_on_damage`, `force_max_bpm`, `get_bpm_tier`, боевой моментум (`combat_momentum`, `add_combat_momentum`, непрерывные источники и спад), а также производные правила `get_bpm_ratio()`, `get_bpm_damage_reduction()` (0..30%), `has_infinite_ammo()` (OVERDRIVE). Формулы и пороги перенесены побуквенно. `SkillManager` содержит только дэш и слэм (255 строк после Шага 5.3; сейчас 346 — после переделки слэма в контроль толпы и `reset_skills`). Все потребители читают BPM через `player.bpm_system`: враги (`EnemyHunter` — сырое `bpm >= 140.0`, начисление BPM за убийство и хедшот в `EnemyBase`; Fear Chain и локдаун турели, тоже читавшие BPM, удалены), оружие (`WeaponBase` вакуумный след и стакинг множителей, `WeaponCaliber` гейт рейлгана — фоллбек `_get_bpm_tier()` удалён), `WeaponManager` (INF-патроны автоогня), `PlayerHealth`, шейдер `overdrive_factor` в `Player._process`, HUD.
- **Связь**: Player держит прямые ссылки на детей (`$PlayerHealth`, `$PlayerCombat`, `$PlayerWallrun`, `$BPMSystem`) и передаёт себя через `setup(self)` в `_ready()`; компоненты не ищут родителя по путям.
- **Обратная совместимость**: `health`, `max_health`, `is_dead` на Player — проксирующие свойства к `PlayerHealth`; `take_damage`, `heal` — делегирующие методы (`restart_game` на Player удалён на Шаге 5.4 — рестарт только через GameManager). Сигналы `health_changed`/`died` по-прежнему объявлены на Player и ретранслируются из компонента, поэтому HUD и внешний код (враги, снаряды, `StatusEffectComponent.heal`) не изменены. Сброс состояния движения при смерти выполняет Player в обработчике `died`. Порядок после Шага 5.4: `PlayerHealth.die()` → `health_changed(0)` → `died` → `Player._on_health_died()` эмитит `Player.died` (первым подписан GameManager: `deaths`++, `trigger_game_over()` → `game_over_triggered` → экран Game Over в HUD; затем HUD мгновенно обнуляет HP-бар) → `_reset_movement_state()`. Взаимных зависимостей между шагами нет.
- **Ввод**: выбор оружия — действия `weapon_1`..`weapon_4` (клавиши 1–4) в InputMap. Esc (`ui_cancel`)
  освобождает курсор, игра при этом идёт; пока курсор свободен, ввод игрока игнорируется — и события
  `_input`, и опрос в физическом тике (`_has_input_focus()`, `_get_move_input()`: ходьба, прыжок, присед
  замирает в текущем состоянии), а клик по
  окну возвращает захват без выстрела (`WeaponManager.block_autofire_until_release()` не даёт
  автоогню стрелять, пока ЛКМ не отпущена). Меню паузы нет.
- **Голова и камера при интерполяции физики** (✅ ноябрь 2026, `head.gd`): `Head` — `top_level`, вне
  интерполяции. В `_process` ставится на интерполированный трансформ тела (`get_global_transform_interpolated`)
  + `eye_height` (0.6, присед слайда твинит `eye_height`, а не `position:y`); поворот — рысканье тела
  (мышь вращает `Player`) × тангаж `_pitch`, применяется сразу в `_input`. В физическом тике голова
  ставится в текущую физическую точку тела (лучи прицела из актуальной позиции). Визуал камеры и вьюмодели
  (`update_visuals`: покачивание, крен, тряска, отдача, FOV) считается в `_process` по данным, которые Player
  передаёт из физического тика (`set_visual_inputs`); сглаживания пересчитаны `_damp60(k, delta)` — как
  `lerp(..., k * delta)` при 60 Гц на любой частоте кадров. После смерти визуал замирает, как раньше;
  `reset_view()` при возрождении сбрасывает и застывшее: высоту глаз (умер в слайде — камера была на 0.6 м ниже),
  отдачу, тряску, крен, присед приземления, зум и FOV. Снаряды стартуют из `get_physics_camera_position()` —
  камера по физическому, а не интерполированному телу.
  `Player.respawn` — `reset_physics_interpolation()` и `head.reset_view()`.
- View-model рук (в `head.gd`): правая рука держит активное оружие, левая — melee-анимация.
  Модели всех 4 стволов — CSG-узлы под `Head/Camera3D` в `player.tscn` (`Revolver`, `Shotgun`, `Injector`,
  `SewingMachine`), у каждого `Muzzle` с `MuzzleLight` и `FlashMesh`. Швейная машина: корпус, нависающий
  верх, горизонтальная катушка, тонкая серебристая игла; до ноября 2026 модели не было — на слоте 4 рука пропадала.
  Обе руки разведены по краям экрана (не в центре). Тени view-model отключены.
- **Полная система тела персонажа (Skeleton3D, ноги/торс с процедурной анимацией) была
  реализована и ОТКАЧЕНА** — блокировала обзор, ломала тени. Причина: попытка сделать всё
  сразу (скелет + анимация + view-model) одним шагом. **При повторной попытке в будущем —
  делать маленькими проверяемыми шагами** (сначала одна капсула-заглушка на правильной позиции,
  проверка, что не мешает обзору, и только потом наращивать сложность).

### Интерфейс (HUD) и отладка (Debug-HUD)
- **Единый HUD и декаплинг систем через сигналы (Шаг 5.1 ✅ Реализован)**: весь игровой интерфейс вынесен в выделенный контроллер `scripts/ui/hud.gd` (`class_name HUD extends CanvasLayer`). Игровые системы (`Player`, `WeaponManager`, `SkillManager`) полностью отвязаны от интерфейса и больше не содержат путей к `$HUD/*`. Вся коммуникация переведена на сигналы:
  - `Player`: `health_changed(current, maximum)`, `died`, `speed_updated(speed, bhop_chain)`, `blood_surf_status_changed(active)`.
  - `WeaponManager`: `ammo_changed(weapon_index, current_ammo, max_ammo)`, `weapon_switched(index, weapon)`, `reload_started(weapon_index, duration)`, `reload_finished(weapon_index)` — объявлены и эмитятся, но **подписчиков нет**: HUD опрашивает `WeaponManager` (`weapons`, `ammos`, перезарядки) в `_process`.
  - `SkillManager`: `dash_charges_changed(count)` (подписчиков нет, заряды дэша HUD опрашивает в `_process`), `hud_popup_requested(text)` (BLOOD SLAM).
  - `BPMSystem` (с Шага 5.3): `bpm_changed(value)`, `tier_changed(tier)`, `momentum_changed(value)`, `hud_popup_requested(text)` (VARIETY). HUD подписан на `hud_popup_requested` обоих источников; BPM, тир и моментум HUD опрашивает в `_process` (`bpm_system.bpm`, `get_bpm_tier()`, `combat_momentum`) — на `bpm_changed`/`tier_changed`/`momentum_changed` подписчиков нет.
  Визуальные параметры, цвета, тайминги твинов, анимация HP-бара, форматирование тиров BPM, золотистый комбо-моментум с диммингом через 2 секунды, CS:GO-style стек оружия и экран Game Over перенесены полностью без визуальных изменений.
- **CS:GO-style Weapon HUD**: в правом нижнем углу расположен динамический вертикальный стек
  оружий. Активное оружие подсвечено золотисто-янтарной полосой слева и ярким текстом, неактивные
  слоты затемнены.
- **Индикатор пассивной перезарядки**: для спрятанного оружия в неполном боезапасе отображается
  процент и плавно заполняющаяся голубая полоска прогресса фоновой перезарядки
  (`passive_reload_timers[i] / reload_time`).
- **Покачивание HUD (✅ ноябрь 2026)**: панели по углам — HP, BPM, моментум, дэш, скорость, блад-сёрф, список
  оружия, счётчик врагов — лежат в общем узле `SwayRoot` (на весь экран, переносятся туда в `_setup_sway_root`
  без пересчёта якорей; панели, созданные кодом, добавляются через `_panels_parent()`). Прицел, подсказка BPM,
  попап комбо, индикатор урона и экраны смерти/конца уровня не двигаются — прицел остаётся точным.
  - Смещение — пружина (жёсткость 140, затухание 16) к цели: отставание от поворота камеры 2.5 px на рад/с,
    от скорости вбок 0.5 px на м/с, от вертикальной скорости 0.35 px на м/с; не больше 26 px. Крен — 0.0012 рад
    на px по горизонтали.
  - Толчки в скорость пружины (не больше 700 px/с): отдача камеры (выстрел любым оружием, жёсткое приземление —
    `Head.camera_recoil`) — вниз 6000 px/с на рад; приземление — вниз 22 px/с на м/с падения сверх 5;
    урон — в сторону от удара 14 px/с на HP.
  - Сила — `@export sway_strength` на узле `HUD` в `player.tscn` (0 — выключено). Мёртвый игрок или
    свободный курсор — HUD возвращается на место.
- **Обратная связь игроку (✅ ноябрь 2026)**:
  - **Индикатор направления урона** (`scripts/ui/damage_indicator.gd`, `class_name DamageIndicator`,
    создаётся HUD в `_setup_feedback_elements`): красная дуга вокруг прицела (радиус 96 px) в сторону
    источника и треугольник-указатель снаружи дуги — различим формой и положением, а не только цветом.
    Источник за спиной — дуга внизу; дуги поворачиваются вместе с игроком (направление хранится в мировых
    координатах). Показ 0.8 с, последние 0.4 с — затухание; ширина и длина дуги — от урона (10 HP слабая,
    30+ HP полная); удары с направлений ближе ~20° сливаются; до 8 дуг. Данные — сигнал
    `Player.damaged(amount, from_dir)` (ретранслируется из `PlayerHealth.damaged`). Направление на источник —
    против горизонтального толчка: все атаки врагов толкают игрока от себя; `hit_pos` у разных атак значит
    разное и используется только без толчка.
  - **Пост-шейдер экрана** (`player.gdshader` на `Player/CanvasLayer/ColorRect`, настройки — в Инспекторе
    материала этого узла в `player.tscn`): выпуклость, пикселизация, шум, обесцвечивание OVERDRIVE, спидлайны,
    виньетка. `resolution` — число пикселей по ширине экрана, по высоте — из пропорций экрана, пиксели
    квадратные (до ноября 2026 одно число на обе оси давало на 16:9 прямоугольники, вытянутые по ширине).
    `noise_amount` — сила шума (меняется каждый кадр, одно значение на пиксель). Сейчас в сцене 1100 и 0.075.
  - **Сигнал низкого HP** (`Player._update_low_health_feedback`): при HP ≤ 30% (`low_health_threshold`)
    пульсирующая красная виньетка пост-шейдера (`player.gdshader`, униформ `low_health` 0.4 → 1.0 к нулю HP,
    накладывается после обесцвечивания OVERDRIVE) и звуковая петля — тихий звон в ушах + дыхание
    (`AudioManager.set_low_health_active`, плавное включение 0.4 с / выключение 0.6 с). Не сердцебиение:
    сердце в игре означает BPM. Гаснет при смерти и на экране конца уровня. HP-бар по-прежнему красный ниже 25%.
  - **Подсказки BPM у прицела** (`scripts/ui/bpm_hint.gd`, `class_name BPMHint`): под прицелом (+64 px)
    строка «+N BPM» и причины — `KILL`, `SHOCKWAVE`, `HEADSHOT`, `VARIETY`, `MOMENTUM ×1.4`; потеря от
    урона — красным `−N BPM / HIT`. События одной серии (пауза меньше 0.7 с, один знак) объединяются:
    рой даёт одну строку `KILL ×7`, а не стопку. Показ 1.2 с + затухание 0.4 с. Данные — сигнал
    `BPMSystem.bpm_event(amount, reason, momentum)`. Плашка `★ VARIETY +N ★` у BPM осталась.
- **Отладочные HP-бары врагов**: по умолчанию выключены, клавиша **H** (только в отладочной сборке, подтверждение — плашка `HP BARS: ON/OFF`) включает/выключает на всю сессию
  (`GameManager.show_enemy_health_bars`). Над врагом — квад-биллборд с шейдером заливки и числовой текст
  `HP / MaxHP`; подробности — [architecture-enemies.md](architecture-enemies.md).
- **HP-бар игрока (Player Health Bar)**: текстовый индикатор "HP: 100" заменён на анимированный прогресс-бар (`ProgressBar` со встроенным оверлеем числового значения `HP / MaxHP`). Размещён в левом нижнем углу между BPMLabel и DashLabel (Y: 534..568, X: 34..260). Динамическая цветовая дифференциация по порогам: зелёный (>50% HP), жёлтый (25%..50% HP), красный (<25% HP). Плавная интерполяция значения и цвета через Tween (0.25с) при получении урона и исцелении, мгновенный сброс в 0 при смерти.
- **Всплывающие цифры урона (Floating Damage Numbers)**: при нанесении урона из точки попадания
  вверх вылетает и плавно растворяется (за 0.65с) числовой индикатор урона с цветовой дифференциацией:
  жёлтый — обычный хит, красный — крит/хедшот (`CRIT!`), голубой `AIR!` — любой удар от 140 урона (по величине урона, без проверки, в воздухе ли цель), зелёный — тики яда.

