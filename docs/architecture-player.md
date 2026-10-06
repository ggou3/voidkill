# Архитектура: игрок и HUD

← [Оглавление: DESIGN.md](../DESIGN.md)

### Игрок (`player.gd` + компоненты `scripts/player/`) — разделение на движение, бой и здоровье ✅ Реализован (Шаг 5.2)
- **`player.gd`** (`class_name Player`, 548 строк, было 1274): движение — ходьба, слайд, bhop, обычный wall-jump, coyote/jump buffer, приземление, шаги, blood-состояния, ввод. Из BPM-методов остался только `get_current_max_speed()` (логика движения; доля BPM читается из `bpm_system`).
- **`PlayerWallrun`** (`res://scripts/player/player_wallrun.gd`, `class_name PlayerWallrun extends Node`, узел `PlayerWallrun` в `player.tscn`, 199 строк): состояние wallrun (`is_wallrunning`, `wallrun_side`, `wallrun_timer`, `wallrun_normal`, `wallrun_cooldown`, `last_wallrun_normal`, `wallrun_exhausted`), `@export`-параметры (`wallrun_min_speed`, `wallrun_speed`, `wallrun_max_duration`, `wallrun_jump_vertical_boost`, `wallrun_jump_horizontal_boost`), лучи `LeftWallRay`/`RightWallRay`, `check_wallrun_wall`, `start_wallrun`, `end_wallrun`, `process_wallrun_physics`, прыжок со стены `jump_off_wall(cap)`. Player вызывает компонент в прежних точках кадра: `tick_cooldown` → `update_entry_and_exit` (вход + выход при дэше/слэме, до приседа/гравитации/прыжка) → `process_wallrun_physics` (ветка движения) → `on_landed` (после `move_and_slide`). Общие для обычного wall-jump поля (`wall_jump_count`, `wall_jump_timer`, `last_wall_jump_normal`, `@export wall_jump_cooldown`) остались на Player. Длительность wallrun от BPM не зависит (`wallrun_max_duration = 1.2` постоянна) — «продлённая длительность wallrun» из тиров баффов (раздел 5) не реализована.
- **`PlayerHealth`** (`res://scripts/player/player_health.gd`, `class_name PlayerHealth extends Node`, узел `PlayerHealth` в `player.tscn`): `max_health`, `health`, `is_dead`, `take_damage` (со снижением урона от BPM и сбросом BPM), `heal` + всплывающий `+N HP`, `die`. Сигналы `health_changed(current, maximum)` и `died`. С Шага 5.4 о GameManager не знает: при смерти только эмитит `died`.
- **`PlayerCombat`** (`res://scripts/player/player_combat.gd`, `class_name PlayerCombat extends Node`, узел `PlayerCombat` в `player.tscn`): `perform_melee` (одиночный удар и конусная ударная волна), execute-добивание, парирование снарядов (`_check_and_deflect_projectiles`, `_spawn_deflect_flash`, `_spawn_deflect_feedback`), VFX конуса, все `@export`-параметры мили/конуса, кулдаун `melee_timer` и трекинг пиковой скорости `recent_peak_speed` (`tick_cooldown`, `track_peak_speed` вызываются из `Player._physics_process` в прежних точках кадра).
- **`BPMSystem`** (`res://scripts/player/bpm_system.gd`, `class_name BPMSystem extends Node`, узел `BPMSystem` в `player.tscn`) — ✅ Шаг 5.3, единственный владелец BPM: `bpm`, `MIN_BPM`/`MAX_BPM`, пассивный спад, `add_bpm`, `record_kill_bpm` (+бонус разнообразия, `last_kill_weapon`), `drop_bpm_on_damage`, `force_max_bpm`, `get_bpm_tier`, боевой моментум (`combat_momentum`, `add_combat_momentum`, непрерывные источники и спад), а также производные правила `get_bpm_ratio()`, `get_bpm_damage_reduction()` (0..30%), `has_infinite_ammo()` (OVERDRIVE). Формулы и пороги перенесены побуквенно. `SkillManager` (255 строк, было 393) содержит только дэш и слэм. Все потребители читают BPM через `player.bpm_system`: враги (`EnemyHunter` — сырое `bpm >= 140.0`, начисление BPM за убийство и хедшот в `EnemyBase`; Fear Chain и локдаун турели, тоже читавшие BPM, удалены), оружие (`WeaponBase` вакуумный след и стакинг множителей, `WeaponCaliber` гейт рейлгана — фоллбек `_get_bpm_tier()` удалён), `WeaponManager` (INF-патроны автоогня), `PlayerHealth`, шейдер `overdrive_factor` в `Player._process`, HUD.
- **Связь**: Player держит прямые ссылки на детей (`$PlayerHealth`, `$PlayerCombat`, `$PlayerWallrun`, `$BPMSystem`) и передаёт себя через `setup(self)` в `_ready()`; компоненты не ищут родителя по путям.
- **Обратная совместимость**: `health`, `max_health`, `is_dead` на Player — проксирующие свойства к `PlayerHealth`; `take_damage`, `heal` — делегирующие методы (`restart_game` на Player удалён на Шаге 5.4 — рестарт только через GameManager). Сигналы `health_changed`/`died` по-прежнему объявлены на Player и ретранслируются из компонента, поэтому HUD и внешний код (враги, снаряды, `StatusEffectComponent.heal`) не изменены. Сброс состояния движения при смерти выполняет Player в обработчике `died` — в том же порядке, что и раньше (HUD → сброс движения → `trigger_game_over`).
- View-model рук (в `head.gd`): правая рука держит активное оружие, левая — melee-анимация.
  Обе руки разведены по краям экрана (не в центре). Тени view-model отключены.
- **Полная система тела персонажа (Skeleton3D, ноги/торс с процедурной анимацией) была
  реализована и ОТКАЧЕНА** — блокировала обзор, ломала тени. Причина: попытка сделать всё
  сразу (скелет + анимация + view-model) одним шагом. **При повторной попытке в будущем —
  делать маленькими проверяемыми шагами** (сначала одна капсула-заглушка на правильной позиции,
  проверка, что не мешает обзору, и только потом наращивать сложность).

### Интерфейс (HUD) и отладка (Debug-HUD)
- **Единый HUD и декаплинг систем через сигналы (Шаг 5.1 ✅ Реализован)**: весь игровой интерфейс вынесен в выделенный контроллер `scripts/ui/hud.gd` (`class_name HUD extends CanvasLayer`). Игровые системы (`Player`, `WeaponManager`, `SkillManager`) полностью отвязаны от интерфейса и больше не содержат путей к `$HUD/*`. Вся коммуникация переведена на сигналы:
  - `Player`: `health_changed(current, maximum)`, `died`, `speed_updated(speed, bhop_chain)`, `blood_surf_status_changed(active)`.
  - `WeaponManager`: `ammo_changed(weapon_index, current_ammo, max_ammo)`, `weapon_switched(index, weapon)`, `reload_started(weapon_index, duration)`, `reload_finished(weapon_index)`.
  - `SkillManager`: `dash_charges_changed(count)`, `hud_popup_requested(text)` (BLOOD SLAM).
  - `BPMSystem` (с Шага 5.3): `bpm_changed(value)`, `tier_changed(tier)`, `momentum_changed(value)`, `hud_popup_requested(text)` (VARIETY). HUD подписан на `hud_popup_requested` обоих источников; BPM, тир и моментум HUD опрашивает в `_process` (`bpm_system.bpm`, `get_bpm_tier()`, `combat_momentum`) — на `bpm_changed`/`tier_changed`/`momentum_changed` подписчиков нет.
  Визуальные параметры, цвета, тайминги твинов, анимация HP-бара, форматирование тиров BPM, золотистый комбо-моментум с диммингом через 2 секунды, CS:GO-style стек оружия и экран Game Over перенесены полностью без визуальных изменений.
- **CS:GO-style Weapon HUD**: в правом нижнем углу расположен динамический вертикальный стек
  оружий. Активное оружие подсвечено золотисто-янтарной полосой слева и ярким текстом, неактивные
  слоты затемнены.
- **Индикатор пассивной перезарядки**: для спрятанного оружия в неполном боезапасе отображается
  процент и плавно заполняющаяся голубая полоска прогресса фоновой перезарядки
  (`passive_reload_timers[i] / reload_time`).
- **Отладочные HP-бары врагов**: по умолчанию выключены, клавиша **H** включает/выключает на всю сессию
  (`GameManager.show_enemy_health_bars`). Над врагом — квад-биллборд с шейдером заливки и числовой текст
  `HP / MaxHP`; подробности — [architecture-enemies.md](architecture-enemies.md).
- **HP-бар игрока (Player Health Bar)**: текстовый индикатор "HP: 100" заменён на анимированный прогресс-бар (`ProgressBar` со встроенным оверлеем числового значения `HP / MaxHP`). Размещён в левом нижнем углу между BPMLabel и DashLabel (Y: 534..568, X: 34..260). Динамическая цветовая дифференциация по порогам: зелёный (>50% HP), жёлтый (25%..50% HP), красный (<25% HP). Плавная интерполяция значения и цвета через Tween (0.25с) при получении урона и исцелении, мгновенный сброс в 0 при смерти.
- **Всплывающие цифры урона (Floating Damage Numbers)**: при нанесении урона из точки попадания
  вверх вылетает и плавно растворяется (за 0.65с) числовой индикатор урона с цветовой дифференциацией:
  жёлтый — обычный хит, голубой — воздушный хит (`AIR`), красный — крит/хедшот (`CRIT`).

