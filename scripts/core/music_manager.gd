extends Node

## Музыка (Autoload singleton): один зацикленный трек на шине Music.
## Темп и громкость следуют BPM сердца игрока: в оригинале (скорость 1.0, громкость 0 дБ) трек звучит
## на 200 BPM, к 50 BPM — медленнее и тише. Тон меняется вместе со скоростью (pitch_scale, как
## замедленная плёнка), без компенсации AudioEffectPitchShift — причина в docs/music.md.
## Сглаживание идёт по реальным часам: стоп-кадр (Engine.time_scale) музыку не замедляет.
## Без игрока (главное меню) трек играет как на 50 BPM. Пауза дерева (меню паузы, экран конца уровня)
## приглушает музыку; на Game Over трек «тонет» — проседает ниже минимума, пока игрок не возродится.

## Путь, не preload: константа-ресурс в автозагрузке держится до выхода и даёт утечку (lessons.md)
const TRACK_PATH: String = "res://music/Combat Loop.mp3"

## Скорость и тон на 50 BPM (0.8 — на ~4 полутона ниже, темп −20%); на 200 BPM — 1.0
const MIN_PITCH: float = 0.8
## Громкость трека на 50 BPM, дБ; на 200 BPM — 0 дБ
const MIN_VOLUME_DB: float = -9.0
## Game Over: трек оседает ниже минимума и затихает
const GAME_OVER_PITCH: float = 0.55
const GAME_OVER_VOLUME_DB: float = -24.0
## Пауза дерева: приглушение поверх кривой BPM, дБ
const PAUSE_DUCK_DB: float = -12.0
## Постоянные времени сглаживания, с: рост BPM слышен быстро, спад — плавным «торможением плёнки»
const RISE_TIME: float = 0.4
const FALL_TIME: float = 1.2
const DUCK_TIME: float = 0.25

var _player: AudioStreamPlayer = null
var _pitch: float = MIN_PITCH
var _volume_db: float = MIN_VOLUME_DB
var _duck_db: float = 0.0
var _last_usec: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	_player.stream = load(TRACK_PATH)
	_player.bus = &"Music"
	add_child(_player)
	_apply()
	_last_usec = Time.get_ticks_usec()
	# В --headless (проверки агента) звука нет, а играющий на выходе поток аудиодрайвер Dummy не освобождает:
	# каждый прогон показывал бы утечку трека и прятал настоящие (lessons.md). Сглаживание и кривая работают и так
	if DisplayServer.get_name() == "headless":
		return
	_player.play()

## Выход из игры: играющий поток освобождает аудиопоток движка на следующем микшировании, которого при выходе
## может уже не быть, — тогда в логе «leaked AudioStreamMP3». Остановка здесь делает это редкостью, но не исключает
func _exit_tree() -> void:
	_player.stop()
	_player.stream = null

func _process(_delta: float) -> void:
	# delta масштабирована Engine.time_scale — в стоп-кадре она почти нулевая; берём реальное время
	var now: int = Time.get_ticks_usec()
	var dt: float = float(now - _last_usec) / 1000000.0
	_last_usec = now

	var target_pitch: float
	var target_volume_db: float
	if GameManager.current_state == GameManager.State.GAME_OVER:
		target_pitch = GAME_OVER_PITCH
		target_volume_db = GAME_OVER_VOLUME_DB
	else:
		var t: float = _bpm_ratio()
		target_pitch = lerpf(MIN_PITCH, 1.0, t)
		target_volume_db = lerpf(MIN_VOLUME_DB, 0.0, t)
	var target_duck_db: float = PAUSE_DUCK_DB if get_tree().paused else 0.0

	_pitch = _approach(_pitch, target_pitch, dt)
	_volume_db = _approach(_volume_db, target_volume_db, dt)
	_duck_db = lerpf(_duck_db, target_duck_db, 1.0 - exp(-dt / DUCK_TIME))
	_apply()

## 0..1 от MIN_BPM до MAX_BPM; без игрока (меню) — 0
func _bpm_ratio() -> float:
	var p = GameManager.player
	if is_instance_valid(p) and "bpm_system" in p and is_instance_valid(p.bpm_system):
		return p.bpm_system.get_bpm_ratio()
	return 0.0

## Экспоненциальное сглаживание: вверх — RISE_TIME, вниз — FALL_TIME
func _approach(current: float, target: float, dt: float) -> float:
	var tau: float = RISE_TIME if target > current else FALL_TIME
	return lerpf(current, target, 1.0 - exp(-dt / tau))

func _apply() -> void:
	_player.pitch_scale = _pitch
	_player.volume_db = _volume_db + _duck_db
