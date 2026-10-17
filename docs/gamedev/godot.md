# Godot 4.7: практика

← [База знаний](README.md)

Грабли конкретного проекта — в `docs/lessons.md` и §6 `CLAUDE.md`. Здесь — общие практики движка.

## Что нового в последних версиях
- **4.4** — Jolt Physics встроен (экспериментально), 3D-интерполяция физики.
- **4.6** (январь 2026) — Jolt по умолчанию для новых проектов, у старых настройка сохраняется.
  Уникальные ID узлов в `.tscn` (`unique_id=…`): ссылки переживают переименование. Новая IK
  (`IKModifier3D`), переделанный SSR, тема редактора Modern, LibGodot.
- **4.7** (июнь 2026) — вывод HDR (Windows/macOS/Wayland; Forward+ или Mobile), `AreaLight3D`
  (прямоугольный источник света), новый Asset Store вместо Asset Library, смещение-трансформ у
  `Control` без поломки контейнеров, копирование секций инспектора, заготовка под трассировку лучей.

## Архитектура
- **Вызовы вниз, сигналы вверх.** Родитель зовёт методы детей, дети сообщают родителю
  сигналами. Соседи связываются через общего родителя или сигнал, а не через `get_node("../..")`.
- **Композиция узлами-компонентами** (`HealthComponent`, `PlayerWallrun`) вместо глубокого
  наследования. Наследование — для «является» (`EnemyGround` → `EnemyRanged`).
- **Автозагрузки** — только для действительно глобального (состояние игры, пулы, звук).
  Автозагрузке нельзя давать `class_name` (урок проекта).
- **Данные — в `Resource`** (`WeaponData`): баланс правится в инспекторе, ресурсы делятся
  между экземплярами. Изменяемое во время игры состояние — не в общем ресурсе
  (`resource_local_to_scene` или `duplicate()`).
- Ссылки на узлы: `@export var x: Node3D` (в рукописном `.tscn` — с `node_paths`), `%UniqueName`
  внутри сцены, группы — для «все такие-то».
- Дети готовы раньше родителя (`_ready` снизу вверх). Подписка на соседей — `call_deferred`.

## GDScript
- **Статическая типизация** — и безопасность, и скорость: типизированный код компилируется в
  оптимизированные опкоды.
- Предупреждения (Project Settings → Debug → GDScript, Advanced): `UNTYPED_DECLARATION`,
  `INFERRED_DECLARATION`, `UNSAFE_PROPERTY_ACCESS`, `UNSAFE_METHOD_ACCESS`, `UNSAFE_CAST`. Включать
  поэтапно: на старом коде их будут сотни.
- Типизированные коллекции: `Array[Enemy]`, `Dictionary[StringName, int]` (вложенные не поддерживаются).
- `x as T` при несовпадении **молча даёт `null`**. Для проверки — `is` или `assert()`.
- `StringName` (`&"name"`) для ключей и сравнений в горячем коде — сравнение по указателю.
- Тяжёлая математика на тысячах объектов — кандидат в GDExtension (C++/Rust) или серверы.

## Физика
- **Тик**: 60 по умолчанию. Понижать нельзя для игры с движением игрока (дрожание, задержка
  ввода). Повышать до 120 — меньше задержки, но дороже и с риском дрожания на мониторах, где
  частота не кратна.
- **Интерполяция физики** (Project Settings → Physics → Common → Physics Interpolation):
  - Решает дрожание при FPS ≠ тику (монитор 144 Гц при тике 60).
  - Всё движение — в `_physics_process` (включая твины и анимации, двигающие узлы).
  - Телепорт/спавн: задать трансформ → `reset_physics_interpolation()`. Для летящего снаряда
    после сброса сразу задать позицию на один тик вперёд, иначе будет «след».
  - Камера от первого лица: `top_level = true` (или отдельная ветка), интерполяцию камеры
    выключить (`physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF`), в `_process`
    ставить позицию из `body.get_global_transform_interpolated()`, поворот — сразу от мыши.
  - `get_global_transform_interpolated()` — для одного-двух особых случаев (камера), не для геймплея.
  - Проверка: временно поставить тик 10 — сразу видно, что дёргается и где нет сброса.
  - Цена — 1–2 тика визуальной задержки. Для твитч-шутера решать осознанно.
- **Jolt**: быстрее и стабильнее GodotPhysics в 3D, но поведение в мелочах иное:
  - видит ли `Area3D` статические тела — настройка `physics/jolt_physics_3d/simulation/areas_detect_static_bodies`;
  - `face_index` в результатах луча всегда `-1`, пока не включено Queries → Enable Ray Cast Face Index
    (+~25% памяти `ConcavePolygonShape3D`);
  - форма сжимается на collision margin, а не раздувается; странные нормали в шейп-запросах
    лечатся уменьшением Collision Margin Fraction;
  - `WorldBoundaryShape3D` конечного размера (Limits → World Boundary Shape Size);
  - спорные нормали на стыках («призрачные» столкновения) — Active Edge Threshold и
    Enhanced Internal Edge Removal.
- Простые формы коллизий (капсула, бокс, сфера) — дешевле `ConcavePolygonShape3D`.
- **Слои и маски** отсекают пары до проверки. Чем точнее маски, тем меньше работы.
- Физзапросы: переиспользовать `PhysicsRayQueryParameters3D`, `exclude` принимает и узлы, и RID.
  Шейпкаст/`intersect_shape` дороже луча.

## Задержка ввода и плавность
- Мышь — в `_input`/`_unhandled_input`, поворот сразу. Ввод по умолчанию накапливается до кадра
  (`Input.set_use_accumulated_input`); для мыши в FPS это нормально — сумма относительных смещений.
- VSync: двойная буферизация (Swapchain Image Count = 2, Godot 4.3+) даёт меньшую задержку,
  если FPS стабильно держит частоту монитора. Mailbox — меньше задержки без разрывов (по
  отзывам сообщества, лучше всего с FreeSync/G-Sync).
- Ограничение FPS (`Engine.max_fps`) чуть ниже частоты монитора с VRR — стандартный приём
  против задержки VSync.

## Производительность
- **Сначала замер.** Профайлер Godot (включать вручную — сам замедляет), визуальный профайлер,
  мониторы (`Performance.get_monitor`), `Time.get_ticks_usec()` для ручных замеров, усреднение
  по 1000+ прогонам.
- Узкое место — CPU или GPU: кадр задаёт медленный. Проверка GPU: окно меньше → FPS вырос → упор в заливку.
- **Узлы стоят денег**: каждый `_process`/`_physics_process` — вызов. Тысячи узлов — заметно.
  Ненужное — `remove_child()`, а не прятать. Выключать обработку невидимого
  (`VisibleOnScreenNotifier3D`, `process_mode`).
- **MultiMesh** — тысячи одинаковых объектов за один вызов отрисовки (кровь, гильзы, мусор).
  Минус — культится целиком, делить по зонам.
- **Серверы** (`RenderingServer`, `PhysicsServer3D`) — объекты без узлов для массовых случаев.
- GPU: меньше уникальных материалов (одинаковые настройки `StandardMaterial3D` делят шейдер),
  меньше прозрачности (сортируется, нет Z-буфера), **тени выключать у мелких и короткоживущих
  источников** (вспышки дула, взрывы). Свет вспышки — переиспользовать один узел, а не спавнить.
- Частицы: `GPUParticles3D` для массовых, вершинное освещение в материале частиц.
- `Decal` стоит за пиксель — ограничивать число и размер.
- Occlusion culling — `OccluderInstance3D` с запеканием, для закрытых уровней с коридорами.
- `visibility_range` — дальность видимости и простые LOD для мелочи.
- **Пулы** (`TracerPool` в проекте) — против всплесков `instantiate`/`add_child`/`queue_free`.

## Навигация
- Навмеш запекать с параметрами агента; менять параметры только с перезапеканием (урок проекта).
- Избегание (RVO) — дорого, только агентам, которым нужно.
- Путь запрашивать по таймеру, а не каждый кадр.
- Нав-линки для прыжков; проверять, что `NavigationRegion3D` охватывает только нужное.

## Сохранение
- Настройки — `ConfigFile` в `user://settings.cfg`. Состояние игры — `FileAccess.store_var()`
  (бинарно, компактно) или JSON (читаемо, но без `Vector3` и `Color` без ручной конвертации).
- **Не загружать `.tres`/`.res` из непроверенного источника** (моды, присланные сохранения):
  ресурс может содержать скрипт, и загрузка исполнит код.
- Сохранять атомарно: запись во временный файл → переименование. Обрыв не испортит сохранение.

## Сборки
- Шаблоны экспорта той же версии, что редактор.
- `OS.is_debug_build()` и **feature tags** (`OS.has_feature("demo")`) — отладочные клавиши (T, H
  в проекте) и разделение демо/полной версии из одного кода.
- Один `.pck` внутри `.exe` (Embed PCK) — проще раздача.
- Steam Deck: Vulkan-сборка под Windows работает через Proton; нативная Linux-сборка — тоже вариант.
  Проверять на 1280×800 и 30–60 FPS.

## Применительно к VOIDKILL
- Jolt включён (`physics/3d/physics_engine="Jolt Physics"`), интерполяция физики выключена,
  тик по умолчанию 60. На мониторах 120/144 Гц движение может слегка дрожать — кандидат на
  включение интерполяции. Затронет камеру (`head.gd`), спавн снарядов, телепорт на чекпоинт.
- В `.tscn` уже есть `unique_id` узлов (формат 4.6+).

## Источники
- [Godot 4.6 released (GameFromScratch)](https://gamefromscratch.com/godot-4-6-released/)
- [Godot 4.6: Jolt, IK, Modern theme (i-programmer)](https://www.i-programmer.info/news/144-graphics-and-games/18652-godot-46-integrates-jolt-and-adds-new-editor-theme.html)
- [Godot 4.7 released (GameFromScratch)](https://gamefromscratch.com/godot-4-7-released/)
- [Godot 4.7 with HDR output (Phoronix)](https://www.phoronix.com/news/Godot-4.7-Released)
- [Physics interpolation: введение](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html)
- [Using physics interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/using_physics_interpolation.html)
- [Advanced physics interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/advanced_physics_interpolation.html)
- [Fixing jitter, stutter and input lag](https://docs.godotengine.org/en/stable/tutorials/rendering/jitter_stutter.html)
- [General optimization](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)
- [CPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html)
- [GPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html)
- [Optimization using MultiMeshes](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html)
- [Static typing in GDScript](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html)
- [Saving games](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html)
- [Using Jolt Physics](https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html)
- [Best practices (оглавление)](https://docs.godotengine.org/en/stable/tutorials/best_practices/index.html)
