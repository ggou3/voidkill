class_name LevelCatalog
extends RefCounted

## Список уровней для меню выбора — единственное место, куда добавляется новый уровень.
## Порядок массива — порядок кнопок в меню.

const LEVELS: Array[Dictionary] = [
	{
		"title": "Демо-уровень",
		"description": "Линейный уровень из секторов: перегородки, чекпоинты, рейтинг",
		"scene": "res://levels/demo_level.tscn",
	},
	{
		"title": "Город",
		"description": "Городской уровень",
		"scene": "res://levels/city_level.tscn",
	},
	{
		"title": "Тестовая арена",
		"description": "Песочница: все враги и зоны движения, без секторов",
		"scene": "res://test_arena.tscn",
	},
]
