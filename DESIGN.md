# VOIDKILL — Дизайн-документ

> Живой документ. Обновлять при каждом значимом решении по дизайну или реализации.
> Движок: Godot 4.7.2. Инструмент разработки: Antigravity CLI (agy), модель Gemini 3.8 Flash.

## Концепция

Динамичный ретро-бумер-шутер на скорость и очки. Ядро геймплея — **кровавый сёрф**:
непрерывное агрессивное движение + бой, где кровь врагов становится топливом для
скорости и способностей игрока. Цель — зачистка уровней на скорость с рейтингом лидеров
(Steam, в будущем).

---

## Оглавление

Дизайн и архитектура разбиты по темам — читай только нужное под задачу.

**Геймплей**
- [docs/movement.md](docs/movement.md) — движение (bhop, wallrun, слайд, фидбек) и кровавая система (лужи, сёрф, кровавый слэм)
- [docs/combat.md](docs/combat.md) — ближний удар и конусная волна, реакция врагов, слэм, хедшоты, синергии
- [docs/weapons.md](docs/weapons.md) — ростер оружия: Калибр-0, Швейная машина, Инъектор, Кровавая наковальня; пассивная перезарядка
- [docs/enemies.md](docs/enemies.md) — общий ИИ врагов: автомат состояний, Fear Chain, выпад
- [docs/enemy-types.md](docs/enemy-types.md) — девять типов врагов: дальник, летун, щитоносец, подрывник, охотник, турель, рой, соглядатай
- [docs/bpm.md](docs/bpm.md) — BPM-система, тиры, моментум, OVERDRIVE; очки и лидерборд
- [docs/redline.md](docs/redline.md) — REDLINE, выход за 200 BPM (запланировано)
- [docs/levels.md](docs/levels.md) — формат игры: линейные уровни из секторов, кровавые перегородки, чекпоинты, рейтинг (запланировано)

**Код**
- [docs/architecture.md](docs/architecture.md) — автозагрузки, class_name и типизация, debug_log, звук
- [docs/architecture-enemies.md](docs/architecture-enemies.md) — HealthComponent, StatusEffectComponent, EnemyHealthBar, EnemyBase/EnemyGround, спецвраги
- [docs/architecture-weapons.md](docs/architecture-weapons.md) — WeaponData, WeaponBase, классы оружия
- [docs/architecture-player.md](docs/architecture-player.md) — игрок и его компоненты, HUD

**Прочее**
- [docs/test-arena.md](docs/test-arena.md) — тестовая арена: зоны, лендмарки, энкаунтеры, навигация
- [docs/lessons.md](docs/lessons.md) — технические уроки (грабли, на которые уже наступали)
- [docs/roadmap.md](docs/roadmap.md) — roadmap
