class_name LevelExit
extends Area3D

## Триггер конца уровня: игрок входит в зону после последнего сектора — уровень пройден.
## GameManager засчитывает проход, только если все секторы уровня зачищены.

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if not (body is Player):
		return
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.complete_level()
