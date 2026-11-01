extends Node

## Глобальный менеджер процедурного звука (Autoload singleton).
## Воспроизводит процедурные звуковые эффекты через AudioStreamPlayer + AudioStreamGenerator.
## Поддерживает автоматическую замену на реальные аудиофайлы из папки res://audio/.

const MIX_RATE: float = 22050.0
const POOL_SIZE: int = 16

var players: Array[AudioStreamPlayer] = []

# Позиционный пул (play_sound_at): звуки врагов в мире
const POOL_SIZE_3D: int = 16
const POSITIONAL_UNIT_SIZE: float = 8.0 # до этого расстояния — полная громкость
const POSITIONAL_MAX_DISTANCE: float = 60.0
var players_3d: Array[AudioStreamPlayer3D] = []
var _voice3d_sound: Array[String] = []
var _voice3d_start_ms: Array[int] = []

var sound_buffers: Dictionary = {}
var sound_durations: Dictionary = {
	"revolver_shot": 0.16,
	"shotgun_shot": 0.28,
	"injector_shot": 0.14,
	"flask_throw": 0.18,
	"flask_splash": 0.32,
	"explosion": 0.45,
	"player_heal": 0.28,
	"melee_hit": 0.11,
	"melee_heavy_hit": 0.24,
	"dash": 0.16,
	"slam_impact": 0.25,
	"jump": 0.08,
	"footstep": 0.045,
	"enemy_hit": 0.07,
	"enemy_death": 0.35,
	"reload": 0.34,
	"slide": 1.5,
	"dry_fire": 0.08,
	"rail_shot": 0.32,
	"needle_shot": 0.06,
	"parry_deflect": 0.22,
	"shield_block": 0.22,
	"bomber_tick": 0.045,
	"hunter_awaken": 0.35,
	"stalker_reveal": 0.30,
	# Звуки врагов (в точке мира, play_sound_at). Телеграфы — восходящий тон в средней полосе:
	# выстрелы игрока, наоборот, падают по высоте, поэтому угроза не путается со своим оружием
	"melee_windup": 0.25,
	"swarm_windup": 0.15,
	"lunge_windup": 0.38,
	"lunge_dash": 0.2,
	"ranged_windup": 0.35,
	"ranged_shot": 0.22,
	"turret_windup": 0.35,
	"flyer_charge": 0.6,
	"flyer_laser": 0.45
}

var external_sounds: Dictionary = {}

# Против «пулемётного эффекта»: случайная высота ± доля на каждое воспроизведение частых звуков.
# Звуки вне списка (тиканье бомбера, гул охотника, UI-подобные) играют без вариаций.
const PITCH_VARIATION: Dictionary = {
	"revolver_shot": 0.04,
	"shotgun_shot": 0.04,
	"injector_shot": 0.06,
	"needle_shot": 0.08,
	"rail_shot": 0.03,
	"melee_hit": 0.06,
	"melee_heavy_hit": 0.04,
	"enemy_hit": 0.08,
	"enemy_death": 0.06,
	"explosion": 0.05,
	"footstep": 0.08,
	"jump": 0.05,
	"dash": 0.05,
	"slam_impact": 0.04,
	"shield_block": 0.06,
	"parry_deflect": 0.04,
	"dry_fire": 0.05,
	"melee_windup": 0.05,
	"swarm_windup": 0.08,
	"lunge_windup": 0.04,
	"lunge_dash": 0.05,
	"ranged_windup": 0.03,
	"ranged_shot": 0.05,
	"turret_windup": 0.02,
	"flyer_charge": 0.03,
	"flyer_laser": 0.04,
}
# Лимит одновременных копий одного звука: новый звук сверх лимита перезапускает самую старую копию,
# а не занимает ещё один плеер (рой из 30 попаданий за кадр — шум, а не информация)
const MAX_VOICES_PER_SOUND: int = 4
## Телеграфы атак — высший приоритет микса: когда свободных плееров нет, вытесняется самый старый
## не-телеграф (смерть, взрыв, тиканье), а телеграф — только если играют одни телеграфы
const PRIORITY_SOUNDS: Array[String] = [
	"melee_windup", "swarm_windup", "lunge_windup", "ranged_windup", "turret_windup", "flyer_charge",
	"bomber_tick", "stalker_reveal"
]
var _voice_sound: Array[String] = []
var _voice_start_ms: Array[int] = []

var slide_player: AudioStreamPlayer = null
var slide_tween: Tween = null
var is_slide_playing: bool = false
const SLIDE_TARGET_VOLUME_DB: float = -15.0
const SLIDE_FADE_IN_TIME: float = 0.12
const SLIDE_FADE_OUT_TIME: float = 0.22

# Петля низкого HP: тихий звон в ушах + тяжёлое дыхание (не сердце — сердцебиение в игре означает BPM)
var low_health_player: AudioStreamPlayer = null
var low_health_tween: Tween = null
var is_low_health_playing: bool = false
const LOW_HEALTH_TARGET_VOLUME_DB: float = -12.0
const LOW_HEALTH_FADE_IN_TIME: float = 0.4
const LOW_HEALTH_FADE_OUT_TIME: float = 0.6
const LOW_HEALTH_LOOP_TIME: float = 4.0 # два вдоха-выдоха по 2 с

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Создаем пул плееров для одновременного воспроизведения звуков
	for i in range(POOL_SIZE):
		var p = AudioStreamPlayer.new()
		p.name = "AudioPlayer_" + str(i)
		p.bus = "Master"
		add_child(p)
		players.append(p)
		_voice_sound.append("")
		_voice_start_ms.append(0)

	for i in range(POOL_SIZE_3D):
		var p3 = AudioStreamPlayer3D.new()
		p3.name = "AudioPlayer3D_" + str(i)
		p3.bus = "Master"
		p3.unit_size = POSITIONAL_UNIT_SIZE
		p3.max_distance = POSITIONAL_MAX_DISTANCE
		add_child(p3)
		players_3d.append(p3)
		_voice3d_sound.append("")
		_voice3d_start_ms.append(0)

	# Поиск реальных аудиофайлов в res://audio/
	_scan_external_audio()
	
	# Предварительная генерация всех процедурных звуковых буферов
	_generate_all_procedural_sounds()

	# Отдельный плеер для зацикленного звука скольжения (slide)
	slide_player = AudioStreamPlayer.new()
	slide_player.name = "AudioPlayer_SlideLoop"
	slide_player.bus = "Master"
	slide_player.volume_db = -80.0
	add_child(slide_player)
	_setup_slide_stream()

	# Отдельный плеер для петли низкого HP
	low_health_player = AudioStreamPlayer.new()
	low_health_player.name = "AudioPlayer_LowHealthLoop"
	low_health_player.bus = "Master"
	low_health_player.volume_db = -80.0
	low_health_player.stream = _gen_low_health_wav()
	add_child(low_health_player)

	GameTypes.debug_log(&"audio", "[AudioManager] Ready! Procedural sounds generated: %d, External files: %d" % [sound_buffers.size(), external_sounds.size()])

func play_sound(sound_name: String):
	# Обработка зацикленного звука скольжения
	if sound_name == "slide":
		start_slide()
		return

	# Приоритет: реальный аудиофайл из res://audio/ (в т.ч. добавленный на лету), иначе процедурный буфер
	if not _has_sound(sound_name):
		push_warning("[AudioManager] Unknown sound name: '%s'" % sound_name)
		return
	_start_on(_get_available_player(sound_name), sound_name)

## Звук в точке мира — враги: телеграфы атак, их выстрелы и рывки. Слышно направление и расстояние,
## поэтому атака за спиной читается на слух. Звуки самого игрока и интерфейса — play_sound (2D).
func play_sound_at(sound_name: String, world_pos: Vector3):
	if not _has_sound(sound_name):
		push_warning("[AudioManager] Unknown sound name: '%s'" % sound_name)
		return
	var p = _get_available_player_3d(sound_name)
	p.global_position = world_pos
	_start_on(p, sound_name)

func stop_sound(sound_name: String):
	if sound_name == "slide":
		stop_slide()

func set_slide_active(active: bool):
	if active:
		start_slide()
	else:
		stop_slide()

func start_slide():
	if not is_instance_valid(slide_player):
		return
		
	if is_slide_playing:
		return
	is_slide_playing = true
	
	if slide_tween and slide_tween.is_valid():
		slide_tween.kill()
		
	if not slide_player.playing:
		slide_player.volume_db = -45.0
		slide_player.play()
		
	slide_tween = create_tween()
	slide_tween.set_ease(Tween.EASE_OUT)
	slide_tween.set_trans(Tween.TRANS_SINE)
	slide_tween.tween_property(slide_player, "volume_db", SLIDE_TARGET_VOLUME_DB, SLIDE_FADE_IN_TIME)

func stop_slide():
	if not is_instance_valid(slide_player):
		return
		
	if not is_slide_playing:
		return
	is_slide_playing = false
	
	if slide_tween and slide_tween.is_valid():
		slide_tween.kill()
		
	slide_tween = create_tween()
	slide_tween.set_ease(Tween.EASE_IN)
	slide_tween.set_trans(Tween.TRANS_SINE)
	slide_tween.tween_property(slide_player, "volume_db", -45.0, SLIDE_FADE_OUT_TIME)
	slide_tween.tween_callback(func():
		if not is_slide_playing and is_instance_valid(slide_player):
			slide_player.stop()
	)

## Петля низкого HP: плавное включение/выключение (игрок зовёт каждый кадр — повтор ничего не делает)
func set_low_health_active(active: bool) -> void:
	if not is_instance_valid(low_health_player) or active == is_low_health_playing:
		return
	is_low_health_playing = active
	if low_health_tween and low_health_tween.is_valid():
		low_health_tween.kill()
	low_health_tween = create_tween()
	if active:
		if not low_health_player.playing:
			low_health_player.volume_db = -40.0
			low_health_player.play()
		low_health_tween.tween_property(low_health_player, "volume_db", LOW_HEALTH_TARGET_VOLUME_DB, LOW_HEALTH_FADE_IN_TIME)
	else:
		low_health_tween.tween_property(low_health_player, "volume_db", -40.0, LOW_HEALTH_FADE_OUT_TIME)
		low_health_tween.tween_callback(func():
			if not is_low_health_playing and is_instance_valid(low_health_player):
				low_health_player.stop()
		)

func _setup_slide_stream():
	if not is_instance_valid(slide_player):
		return
		
	# 1. Приоритет внешнему аудиофайлу
	if external_sounds.has("slide"):
		var ext_stream = external_sounds["slide"]
		if ext_stream is AudioStreamWAV:
			ext_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			ext_stream.loop_begin = 0
		elif ext_stream is AudioStreamOggVorbis:
			ext_stream.loop = true
		slide_player.stream = ext_stream
		return
		
	# 2. Процедурный зацикленный звук скольжения
	slide_player.stream = _gen_slide_wav()

## Выбор плеера в пуле: лимит копий одного звука (сверх лимита перезапускается самая старая копия),
## иначе свободный плеер, иначе самый давно запущенный
func _pick_voice(pool: Array, voice_sound: Array[String], voice_start: Array[int], sound_name: String) -> int:
	var same_count: int = 0
	var oldest_same: int = -1
	var free_idx: int = -1
	var oldest_any: int = 0
	var oldest_low: int = -1 # самый старый плеер с не-приоритетным звуком
	for i in range(pool.size()):
		if pool[i].playing:
			if voice_sound[i] == sound_name:
				same_count += 1
				if oldest_same < 0 or voice_start[i] < voice_start[oldest_same]:
					oldest_same = i
			if voice_start[i] < voice_start[oldest_any]:
				oldest_any = i
			if not PRIORITY_SOUNDS.has(voice_sound[i]) and (oldest_low < 0 or voice_start[i] < voice_start[oldest_low]):
				oldest_low = i
		elif free_idx < 0:
			free_idx = i
	var idx: int = oldest_low if oldest_low >= 0 else oldest_any
	if same_count >= MAX_VOICES_PER_SOUND:
		idx = oldest_same
	elif free_idx >= 0:
		idx = free_idx
	voice_sound[idx] = sound_name
	voice_start[idx] = Time.get_ticks_msec()
	pool[idx].stop()
	var variation: float = PITCH_VARIATION.get(sound_name, 0.0)
	pool[idx].pitch_scale = 1.0 + randf_range(-variation, variation)
	return idx

func _get_available_player(sound_name: String) -> AudioStreamPlayer:
	return players[_pick_voice(players, _voice_sound, _voice_start_ms, sound_name)]

func _get_available_player_3d(sound_name: String) -> AudioStreamPlayer3D:
	return players_3d[_pick_voice(players_3d, _voice3d_sound, _voice3d_start_ms, sound_name)]

## Есть ли такой звук (внешний файл или процедурный буфер)
func _has_sound(sound_name: String) -> bool:
	return external_sounds.has(sound_name) or _check_single_external_file(sound_name) or sound_buffers.has(sound_name)

## Запуск звука на выбранном плеере (2D или 3D)
func _start_on(player: Node, sound_name: String) -> void:
	if external_sounds.has(sound_name):
		player.stream = external_sounds[sound_name]
		player.play()
		return
	var buffer: PackedVector2Array = sound_buffers[sound_name]
	_play_buffer(player, buffer, sound_durations.get(sound_name, 0.2))

func _play_buffer(player: Node, buffer: PackedVector2Array, duration: float):
	if buffer.is_empty():
		return

	# При пониженной высоте звук длится дольше — остановку сдвигаем на столько же
	duration /= player.pitch_scale

	var gen = AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = duration + 0.1

	player.stream = gen
	player.play()
	
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	if playback:
		var frames = playback.get_frames_available()
		var count = min(frames, buffer.size())
		if count > 0:
			playback.push_buffer(buffer.slice(0, count))
			
	# Остановка плеера по окончании воспроизведения буфера. Таймер в реальном времени: звук стоп-кадром
	# (Engine.time_scale) не замедляется, и голос не должен оставаться занятым дольше самого звука
	get_tree().create_timer(duration + 0.05, true, false, true).timeout.connect(func():
		if is_instance_valid(player) and player.stream == gen:
			player.stop()
	)

func _scan_external_audio():
	for s_name in sound_durations.keys():
		_check_single_external_file(s_name)

func _check_single_external_file(sound_name: String) -> bool:
	for ext in [".wav", ".ogg", ".mp3"]:
		var path = "res://audio/" + sound_name + ext
		if ResourceLoader.exists(path):
			var s = load(path)
			if s is AudioStream:
				external_sounds[sound_name] = s
				GameTypes.debug_log(&"audio", "[AudioManager] Using external audio for '%s': %s" % [sound_name, path])
				if sound_name == "slide" and is_instance_valid(slide_player):
					_setup_slide_stream()
				return true
	return false

# ==============================================================================
# ПРОЦЕДУРНЫЙ СИНТЕЗ ЗВУКОВ
# ==============================================================================

func _generate_all_procedural_sounds():
	sound_buffers["revolver_shot"] = _gen_revolver_shot()
	sound_buffers["shotgun_shot"] = _gen_shotgun_shot()
	sound_buffers["injector_shot"] = _gen_injector_shot()
	sound_buffers["flask_throw"] = _gen_flask_throw()
	sound_buffers["flask_splash"] = _gen_flask_splash()
	sound_buffers["explosion"] = _gen_explosion()
	sound_buffers["player_heal"] = _gen_player_heal()
	sound_buffers["melee_hit"] = _gen_melee_hit()
	sound_buffers["melee_heavy_hit"] = _gen_melee_heavy_hit()
	sound_buffers["dash"] = _gen_dash()
	sound_buffers["slam_impact"] = _gen_slam_impact()
	sound_buffers["jump"] = _gen_jump()
	sound_buffers["footstep"] = _gen_footstep()
	sound_buffers["enemy_hit"] = _gen_enemy_hit()
	sound_buffers["enemy_death"] = _gen_enemy_death()
	sound_buffers["reload"] = _gen_reload()
	sound_buffers["dry_fire"] = _gen_dry_fire()
	sound_buffers["rail_shot"] = _gen_rail_shot()
	sound_buffers["needle_shot"] = _gen_needle_shot()
	sound_buffers["parry_deflect"] = _gen_parry_deflect()
	sound_buffers["shield_block"] = _gen_shield_block()
	sound_buffers["bomber_tick"] = _gen_bomber_tick()
	sound_buffers["hunter_awaken"] = _gen_hunter_awaken()
	sound_buffers["stalker_reveal"] = _gen_stalker_reveal()
	sound_buffers["melee_windup"] = _gen_melee_windup("melee_windup", 140.0, 420.0)
	sound_buffers["swarm_windup"] = _gen_swarm_windup()
	sound_buffers["lunge_windup"] = _gen_melee_windup("lunge_windup", 90.0, 300.0)
	sound_buffers["lunge_dash"] = _gen_lunge_dash()
	sound_buffers["ranged_windup"] = _gen_charge_whine("ranged_windup", 220.0, 880.0, 9.0)
	sound_buffers["ranged_shot"] = _gen_ranged_shot()
	sound_buffers["turret_windup"] = _gen_turret_windup()
	sound_buffers["flyer_charge"] = _gen_charge_whine("flyer_charge", 300.0, 1500.0, 14.0)
	sound_buffers["flyer_laser"] = _gen_flyer_laser()

func _gen_dry_fire() -> PackedVector2Array:
	var dur = sound_durations["dry_fire"]
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var phase: float = 0.0
	for i in range(samples):
		var t = i * dt
		var freq = 1400.0 * exp(-t * 40.0) + 350.0
		phase += freq * dt * TAU
		var env = exp(-t * 55.0)
		var s = sin(phase) * env * 0.35
		arr[i] = Vector2(s, s)
	return arr

func _gen_needle_shot() -> PackedVector2Array:
	var dur = sound_durations["needle_shot"]
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var phase: float = 0.0
	for i in range(samples):
		var t = float(i) * dt
		var freq = 2600.0 * exp(-t * 90.0) + 400.0
		phase += TAU * freq * dt
		var click = sin(phase) * exp(-t * 75.0) * 0.42
		var noise = randf_range(-1.0, 1.0) * exp(-t * 95.0) * 0.32
		var s = clamp((click + noise) * 0.5, -1.0, 1.0)
		arr[i] = Vector2(s, s)
	return arr

func _gen_rail_shot() -> PackedVector2Array:
	var dur = sound_durations["rail_shot"]
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var phase1: float = 0.0
	var phase2: float = 0.0
	for i in range(samples):
		var t = float(i) * dt
		# Сверхзвуковой электрический треск: экспоненциальное падение частоты от 3200 до 120 Гц
		var f1 = 120.0 + 3080.0 * exp(-42.0 * t)
		phase1 += TAU * f1 * dt
		var tone = sin(phase1) * 0.45
		
		# Резонирующий металлический/энергетический гул 480 Гц
		phase2 += TAU * 480.0 * dt
		var hum = sin(phase2) * exp(-14.0 * t) * 0.25
		
		# Резкий взрывной шум разряда
		var noise = randf_range(-1.0, 1.0) * exp(-35.0 * t) * 0.6
		
		# Тяжёлый саб-басовый удар 65 Гц
		var sub = sin(TAU * 65.0 * t) * exp(-9.0 * t) * 0.55
		
		var sample = clamp((tone + hum + noise + sub) * 0.55, -1.0, 1.0)
		arr[i] = Vector2(sample, sample)
	return arr

# 1. "revolver_shot" — короткий резкий высокочастотный щелчок/хлопок
func _gen_revolver_shot() -> PackedVector2Array:
	var dur = sound_durations["revolver_shot"]
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var phase: float = 0.0
	
	for i in range(samples):
		var t = float(i) * dt
		# Высокочастотный экспоненциальный спад от 2200 до 160 Гц
		var freq = 160.0 + 2040.0 * exp(-55.0 * t)
		phase += TAU * freq * dt
		var tone = sin(phase) * 0.55
		
		# Резкий шумовой хлопок
		var noise = randf_range(-1.0, 1.0) * exp(-40.0 * t) * 0.55
		
		# Низкий толчок крупного калибра
		var thump = sin(TAU * 95.0 * t) * exp(-16.0 * t) * 0.5
		
		var s = (tone + noise + thump) * exp(-20.0 * t)
		s = clamp(s * 1.3, -0.95, 0.95)
		arr[i] = Vector2(s, s)
		
	return arr

# 2. "shotgun_shot" — более низкий, "толстый" звук с шумовой составляющей
func _gen_shotgun_shot() -> PackedVector2Array:
	var dur = sound_durations["shotgun_shot"]
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var phase_bass: float = 0.0
	var phase_mid: float = 0.0
	var noise_filtered: float = 0.0
	
	for i in range(samples):
		var t = float(i) * dt
		# Низкий бас от 180 до 40 Гц
		var f_bass = 40.0 + 140.0 * exp(-14.0 * t)
		phase_bass += TAU * f_bass * dt
		var s_bass = sin(phase_bass) * 0.75
		
		# Среднечастотный перегруз
		var f_mid = 70.0 + 150.0 * exp(-20.0 * t)
		phase_mid += TAU * f_mid * dt
		var s_mid = (sin(phase_mid) + 0.4 * sign(sin(phase_mid * 2.0))) * 0.35 * exp(-18.0 * t)
		
		# Плотный шум выстрела с фильтром
		var raw_noise = randf_range(-1.0, 1.0)
		noise_filtered = lerp(noise_filtered, raw_noise, 0.45)
		var s_noise = noise_filtered * exp(-13.0 * t) * 0.65
		
		var s = (s_bass + s_mid + s_noise) * exp(-10.0 * t)
		s = clamp(s * 1.4, -0.95, 0.95)
		arr[i] = Vector2(s, s)
		
	return arr

# 3. "melee_hit" — короткий глухой удар
func _gen_melee_hit() -> PackedVector2Array:
	var dur = sound_durations["melee_hit"]
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var phase: float = 0.0
	
	for i in range(samples):
		var t = float(i) * dt
		var freq = 55.0 + 135.0 * exp(-35.0 * t)
		phase += TAU * freq * dt
		var tone = sin(phase) * 0.75
		
		var punch = 0.0
		if t < 0.012:
			punch = randf_range(-1.0, 1.0) * (1.0 - t / 0.012) * 0.4
			
		var s = (tone + punch) * exp(-26.0 * t)
		s = clamp(s * 1.2, -0.9, 0.9)
		arr[i] = Vector2(s, s)
		
	return arr

# 4. "melee_heavy_hit" — более громкий и низкий вариант для конусной атаки
func _gen_melee_heavy_hit() -> PackedVector2Array:
	var dur = sound_durations["melee_heavy_hit"]
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var phase: float = 0.0
	var phase_sub: float = 0.0
	
	for i in range(samples):
		var t = float(i) * dt
		# Глубокий саб-бас от 110 до 35 Гц
		var freq_sub = 35.0 + 75.0 * exp(-10.0 * t)
		phase_sub += TAU * freq_sub * dt
		var sub = sin(phase_sub) * 0.85
		
		# Кинетический кранч
		var freq = 50.0 + 100.0 * exp(-16.0 * t)
		phase += TAU * freq * dt
		var crunch = sign(sin(phase)) * 0.3 * exp(-18.0 * t)
		
		# Низкочастотная волна воздуха
		var air = randf_range(-1.0, 1.0) * exp(-14.0 * t) * 0.4
		
		var s = (sub + crunch + air) * exp(-9.0 * t)
		s = clamp(s * 1.4, -0.95, 0.95)
		arr[i] = Vector2(s, s)
		
	return arr

# 5. "dash" — короткий восходящий свист (растущая частота)
func _gen_dash() -> PackedVector2Array:
	var dur = sound_durations["dash"]
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var phase: float = 0.0
	var noise_filtered: float = 0.0
	
	for i in range(samples):
		var t = float(i) * dt
		var progress = t / dur
		# Восходящая частота свиста от 280 до 1200 Гц
		var freq = 280.0 + 920.0 * pow(progress, 1.4)
		phase += TAU * freq * dt
		var whistle = sin(phase) * 0.55
		
		# Нарастающий и спадающий воздушный поток
		noise_filtered = lerp(noise_filtered, randf_range(-1.0, 1.0), 0.3)
		var wind = noise_filtered * sin(PI * progress) * 0.45
		
		var env = sin(PI * progress) * (1.1 - 0.3 * progress)
		var s = (whistle + wind) * env
		s = clamp(s * 1.1, -0.9, 0.9)
		arr[i] = Vector2(s, s)
		
	return arr

# 6. "slam_impact" — низкий "бум" с быстрым затуханием
func _gen_slam_impact() -> PackedVector2Array:
	var dur = sound_durations["slam_impact"]
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var phase: float = 0.0
	
	for i in range(samples):
		var t = float(i) * dt
		var freq = 30.0 + 130.0 * exp(-18.0 * t)
		phase += TAU * freq * dt
		var boom = sin(phase) * 0.9
		var crunch = randf_range(-1.0, 1.0) * exp(-24.0 * t) * 0.45
		
		var s = (boom + crunch) * exp(-12.0 * t)
		s = clamp(s * 1.3, -0.95, 0.95)
		arr[i] = Vector2(s, s)
		
	return arr

# 7. "jump" — короткий лёгкий звук
func _gen_jump() -> PackedVector2Array:
	var dur = sound_durations["jump"]
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var phase: float = 0.0
	
	for i in range(samples):
		var t = float(i) * dt
		var progress = t / dur
		# Короткий лёгкий восходящий чирп 220 -> 460 Гц
		var freq = 220.0 + 240.0 * progress
		phase += TAU * freq * dt
		var s = sin(phase) * 0.45 * (1.0 - progress)
		arr[i] = Vector2(s, s)
		
	return arr

# 8. "footstep" — тихий короткий щелчок/стук
func _gen_footstep() -> PackedVector2Array:
	var dur = sound_durations["footstep"]
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var phase: float = 0.0
	
	for i in range(samples):
		var t = float(i) * dt
		phase += TAU * 85.0 * dt
		var thud = sin(phase) * 0.22 * exp(-60.0 * t)
		var tap = randf_range(-1.0, 1.0) * 0.18 * exp(-110.0 * t)
		var s = clamp(thud + tap, -0.3, 0.3)
		arr[i] = Vector2(s, s)
		
	return arr

# 9. "enemy_hit" — короткий резкий звук попадания
func _gen_enemy_hit() -> PackedVector2Array:
	var dur = sound_durations["enemy_hit"]
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var phase: float = 0.0
	
	for i in range(samples):
		var t = float(i) * dt
		# Резкий спад от 950 до 420 Гц (звучный хит-маркер)
		var freq = 420.0 + 530.0 * exp(-45.0 * t)
		phase += TAU * freq * dt
		var tone = (sin(phase) + 0.35 * sign(sin(phase))) * 0.55
		var s = tone * exp(-38.0 * t)
		s = clamp(s * 1.1, -0.85, 0.85)
		arr[i] = Vector2(s, s)
		
	return arr

# 10. "enemy_death" — более протяжный низкий звук
func _gen_enemy_death() -> PackedVector2Array:
	var dur = sound_durations["enemy_death"]
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var phase: float = 0.0
	
	for i in range(samples):
		var t = float(i) * dt
		# Нисходящий тон смерти от 210 до 45 Гц
		var freq = 45.0 + 165.0 * exp(-6.5 * t)
		phase += TAU * freq * dt
		var tone = (sin(phase) + 0.3 * sin(2.0 * phase)) * 0.65
		var rumble = randf_range(-1.0, 1.0) * exp(-7.0 * t) * 0.25
		var s = (tone + rumble) * exp(-6.5 * t)
		s = clamp(s * 1.2, -0.9, 0.9)
		arr[i] = Vector2(s, s)
		
	return arr

# 11. "reload" — серия из 2-3 коротких кликов подряд
func _gen_reload() -> PackedVector2Array:
	var dur = sound_durations["reload"]
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	
	# Три механических клика
	# Клик 1: 0.00 - 0.04 (открытие барабана)
	# Клик 2: 0.12 - 0.16 (вставка патронов)
	# Клик 3: 0.24 - 0.30 (защелкивание барабана)
	for i in range(samples):
		var t = float(i) * dt
		var s: float = 0.0
		
		if t >= 0.0 and t < 0.04:
			var t1 = t
			var f1 = 300.0 + 500.0 * exp(-60.0 * t1)
			s = (sin(TAU * f1 * t1) * 0.5 + randf_range(-1.0, 1.0) * 0.3) * exp(-70.0 * t1)
		elif t >= 0.12 and t < 0.16:
			var t2 = t - 0.12
			var f2 = 500.0 + 400.0 * exp(-60.0 * t2)
			s = (sin(TAU * f2 * t2) * 0.55 + randf_range(-1.0, 1.0) * 0.25) * exp(-70.0 * t2)
		elif t >= 0.24 and t < 0.30:
			var t3 = t - 0.24
			var f3 = 250.0 + 850.0 * exp(-50.0 * t3)
			s = (sin(TAU * f3 * t3) * 0.7 + randf_range(-1.0, 1.0) * 0.35) * exp(-55.0 * t3)
			
		s = clamp(s * 1.2, -0.85, 0.85)
		arr[i] = Vector2(s, s)
		
	return arr

# 12. "slide" — тихий шипящий/трущийся зацикленный звук скольжения
func _gen_slide_wav() -> AudioStreamWAV:
	var dur = sound_durations.get("slide", 1.5)
	var samples = int(dur * MIX_RATE)
	var dt = 1.0 / MIX_RATE
	
	# Создаем запас для бесшовного кроссфейда между концом и началом
	var crossfade_len = int(0.12 * MIX_RATE)
	var total_gen = samples + crossfade_len
	var raw = PackedFloat32Array()
	raw.resize(total_gen)
	
	var lp1 = 0.0
	var hp_slow = 0.0
	var phase_rumble = 0.0
	
	for i in range(total_gen):
		var t = float(i) * dt
		
		# 1. Мягкий шум трения подошвы/коленей о поверхность (полосовой фильтр)
		var n = randf_range(-1.0, 1.0)
		lp1 = lerp(lp1, n, 0.22)
		hp_slow = lerp(hp_slow, lp1, 0.04)
		var hiss = lp1 - hp_slow
		
		# 2. Неравномерная шероховатость трения
		var mod = 0.75 + 0.16 * sin(TAU * 11.7 * t) + 0.09 * sin(TAU * 23.4 * t)
		var friction = hiss * mod
		
		# 3. Тонкий глухой фоновый гул скольжения массы тела
		phase_rumble += TAU * 70.0 * dt
		var rumble = sin(phase_rumble) * 0.12
		
		raw[i] = friction * 0.42 + rumble * 0.14
		
	# 4. Бесшовное сведение кольца для идеального лупа без щелчков
	var final_floats = PackedFloat32Array()
	final_floats.resize(samples)
	for i in range(samples):
		if i < crossfade_len:
			var w = float(i) / float(crossfade_len)
			var tail_sample = raw[samples + i]
			var head_sample = raw[i]
			final_floats[i] = lerp(tail_sample, head_sample, w)
		else:
			final_floats[i] = raw[i]
			
	# 5. Упаковка в 16-битный PCM Stereo PackedByteArray
	var byte_data = PackedByteArray()
	byte_data.resize(samples * 4)
	for i in range(samples):
		var s = clampf(final_floats[i], -0.95, 0.95)
		var val_16 = clampi(int(s * 32767.0), -32768, 32767)
		var offset = i * 4
		byte_data.encode_s16(offset, val_16)
		byte_data.encode_s16(offset + 2, val_16)
		
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(MIX_RATE)
	wav.stereo = true
	wav.data = byte_data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = samples
	return wav

# 12. "injector_shot" — пневматический выстрел иглы шприца (щелчок + свист)
func _gen_injector_shot() -> PackedVector2Array:
	var dur = sound_durations["injector_shot"]
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var phase: float = 0.0
	
	for i in range(samples):
		var t = float(i) * dt
		var freq = 350.0 + 1600.0 * exp(-45.0 * t)
		phase += TAU * freq * dt
		var tone = sin(phase) * 0.45
		var hiss = randf_range(-1.0, 1.0) * exp(-28.0 * t) * 0.40
		var s = (tone + hiss) * exp(-12.0 * t) * 0.75
		arr[i] = Vector2(s, s)
	return arr

# 13. "flask_throw" — свист рассекаемого воздуха при броске колбы
func _gen_flask_throw() -> PackedVector2Array:
	var dur = sound_durations["flask_throw"]
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	
	for i in range(samples):
		var t = float(i) * dt
		var env = sin((t / dur) * PI)
		var noise = randf_range(-1.0, 1.0) * env * 0.45
		arr[i] = Vector2(noise, noise)
	return arr

# 14. "flask_splash" — звон разбитого стекла + хлюпающий всплеск жидкости
func _gen_flask_splash() -> PackedVector2Array:
	var dur = sound_durations["flask_splash"]
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var glass_phase: float = 0.0
	
	for i in range(samples):
		var t = float(i) * dt
		# Звон стекла (высокая частота ~2800 Гц с быстрой реверберацией)
		glass_phase += TAU * (2800.0 + sin(t * 120.0) * 400.0) * dt
		var glass = sin(glass_phase) * exp(-35.0 * t) * 0.55
		# Хлюпанье жидкости (низкочастотный шум + всплеск)
		var splash_env = clamp((t - 0.02) * 15.0, 0.0, 1.0) * exp(-10.0 * t)
		var splash = randf_range(-1.0, 1.0) * splash_env * 0.5
		var s = clampf(glass + splash, -0.9, 0.9)
		arr[i] = Vector2(s, s)
	return arr

# 15. "explosion" — мощный раскатистый взрыв с глухим саб-басом и треском
func _gen_explosion() -> PackedVector2Array:
	var dur = sound_durations["explosion"]
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var sub_phase: float = 0.0
	
	for i in range(samples):
		var t = float(i) * dt
		# Глухой басовый удар (130 -> 35 Гц)
		var freq = 35.0 + 95.0 * exp(-14.0 * t)
		sub_phase += TAU * freq * dt
		var bass = sin(sub_phase) * exp(-6.5 * t) * 0.8
		# Взрывной раскат шума
		var blast = randf_range(-1.0, 1.0) * exp(-9.0 * t) * 0.7
		var s = clampf(bass + blast, -0.95, 0.95)
		arr[i] = Vector2(s, s)
	return arr

# 16. "player_heal" — чистый звонкий восходящий кристаллический аккорд исцеления
func _gen_player_heal() -> PackedVector2Array:
	var dur = sound_durations["player_heal"]
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var p1: float = 0.0
	var p2: float = 0.0
	
	for i in range(samples):
		var t = float(i) * dt
		# Восходящие тона (520 -> 780 Гц и 1040 Гц)
		var f1 = 520.0 + 260.0 * (t / dur)
		var f2 = f1 * 1.5
		p1 += TAU * f1 * dt
		p2 += TAU * f2 * dt
		var env = exp(-7.0 * t)
		var s = (sin(p1) * 0.45 + sin(p2) * 0.35) * env
		arr[i] = Vector2(s, s)
	return arr

# 17. "parry_deflect" — звонкий металлический клэнг/рикошет парирования
func _gen_parry_deflect() -> PackedVector2Array:
	var dur = sound_durations.get("parry_deflect", 0.22)
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var p1: float = 0.0
	var p2: float = 0.0
	var p3: float = 0.0
	
	for i in range(samples):
		var t = float(i) * dt
		# Яркий металлический звон: 1850 Гц + 3700 Гц
		p1 += TAU * 1850.0 * dt
		p2 += TAU * 3700.0 * dt
		# Низкочастотный ударный щелчок
		p3 += TAU * 160.0 * exp(-35.0 * t) * dt
		var ping = (sin(p1) * 0.6 + sin(p2) * 0.35) * exp(-16.0 * t)
		var punch = sin(p3) * 0.7 * exp(-28.0 * t)
		var spark = randf_range(-1.0, 1.0) * 0.25 * exp(-45.0 * t)
		var s = clampf((ping + punch + spark) * 1.2, -0.95, 0.95)
		arr[i] = Vector2(s, s)
	return arr

# 18. "shield_block" — тяжёлый металлический лязг и глухой удар рикошета в щит
func _gen_shield_block() -> PackedVector2Array:
	var dur = sound_durations.get("shield_block", 0.22)
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var p1: float = 0.0
	var p2: float = 0.0
	var p3: float = 0.0
	
	for i in range(samples):
		var t = float(i) * dt
		# Тяжёлый металлический звон: 950 Гц + 1420 Гц с быстрым затуханием
		p1 += TAU * 950.0 * dt
		p2 += TAU * 1420.0 * dt
		# Низкочастотный глухой удар в стальную плиту (220 -> 55 Гц)
		var freq = 55.0 + 165.0 * exp(-20.0 * t)
		p3 += TAU * freq * dt
		var metallic = (sin(p1) * 0.5 + sin(p2) * 0.3) * exp(-14.0 * t)
		var thud = sin(p3) * 0.8 * exp(-18.0 * t)
		var spark = randf_range(-1.0, 1.0) * 0.3 * exp(-35.0 * t)
		var s = clampf((metallic + thud + spark) * 1.1, -0.95, 0.95)
		arr[i] = Vector2(s, s)
	return arr

# 19. "bomber_tick" — резкий высокочастотный электронный тик/сигнал таймера детонации
func _gen_bomber_tick() -> PackedVector2Array:
	var dur = sound_durations.get("bomber_tick", 0.045)
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var p: float = 0.0
	
	for i in range(samples):
		var t = float(i) * dt
		# Высокий пронзительный щелчок (1800 -> 1200 Гц)
		var freq = 1200.0 + 600.0 * exp(-60.0 * t)
		p += TAU * freq * dt
		var tone = sin(p) * exp(-45.0 * t)
		var click = randf_range(-1.0, 1.0) * exp(-120.0 * t) * 0.4
		var s = clampf((tone + click) * 0.9, -0.95, 0.95)
		arr[i] = Vector2(s, s)
	return arr

# 20. "hunter_awaken" — зловещий низкий металлический гул пробуждения Охотника
func _gen_hunter_awaken() -> PackedVector2Array:
	var dur = sound_durations.get("hunter_awaken", 0.35)
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var p1: float = 0.0
	var p2: float = 0.0
	var p3: float = 0.0
	
	for i in range(samples):
		var t = float(i) * dt
		# Восходящий металлический резонанс от 95 до 220 Гц с суб-басом
		var f1 = 95.0 + 125.0 * (t / dur)
		var f2 = f1 * 2.5
		p1 += TAU * f1 * dt
		p2 += TAU * f2 * dt
		p3 += TAU * 48.0 * dt
		var bass = sin(p3) * 0.55
		var mid = (sin(p1) * 0.45 + sin(p2) * 0.25)
		var env = sin((t / dur) * PI) * exp(-1.2 * t)
		var s = clampf((bass + mid) * env * 1.3, -0.95, 0.95)
		arr[i] = Vector2(s, s)
	return arr

# 21. "stalker_reveal" — призрачный фазовый шелест/свист демаскировки Соглядатая
func _gen_stalker_reveal() -> PackedVector2Array:
	var dur = sound_durations.get("stalker_reveal", 0.30)
	var samples = int(dur * MIX_RATE)
	var arr = PackedVector2Array()
	arr.resize(samples)
	var dt = 1.0 / MIX_RATE
	var p1: float = 0.0
	var p2: float = 0.0
	
	for i in range(samples):
		var t = float(i) * dt
		var f1 = 280.0 + 580.0 * pow(t / dur, 1.5)
		var f2 = f1 * 1.5 + sin(t * 45.0) * 35.0
		p1 += TAU * f1 * dt
		p2 += TAU * f2 * dt
		var osc = (sin(p1) * 0.55 + sin(p2) * 0.45)
		var env = sin((t / dur) * PI) * (0.8 + 0.2 * sin(t * 60.0))
		var s = clampf(osc * env * 0.75, -0.95, 0.95)
		arr[i] = Vector2(s, s)
	return arr

# ==============================================================================
# ЗВУКИ ВРАГОВ (телеграфы атак и выстрелы, играются в точке мира)
# ==============================================================================

# "melee_windup" / "lunge_windup" — нарастающий хриплый рык замаха: тон растёт от f_start к f_end,
# громкость нарастает к концу (удар приходит на пике)
func _gen_melee_windup(sound_name: String, f_start: float, f_end: float) -> PackedVector2Array:
	var dur: float = sound_durations[sound_name]
	var samples: int = int(dur * MIX_RATE)
	var arr := PackedVector2Array()
	arr.resize(samples)
	var dt: float = 1.0 / MIX_RATE
	var phase: float = 0.0
	var rasp: float = 0.0
	for i in range(samples):
		var t: float = float(i) * dt
		var k: float = t / dur
		var freq: float = lerpf(f_start, f_end, k * k)
		phase += TAU * freq * dt
		# Пилообразный тон (рык) + отфильтрованный шум (хрип)
		var saw: float = fposmod(phase / TAU, 1.0) * 2.0 - 1.0
		rasp = lerpf(rasp, randf_range(-1.0, 1.0), 0.3)
		var env: float = (0.25 + 0.75 * k) * minf(1.0, (dur - t) / 0.03)
		var s: float = clampf((saw * 0.45 + rasp * 0.5) * env * 0.8, -0.9, 0.9)
		arr[i] = Vector2(s, s)
	return arr

# "swarm_windup" — короткий стрекот роя: высокий восходящий тон с быстрой модуляцией 55 Гц
func _gen_swarm_windup() -> PackedVector2Array:
	var dur: float = sound_durations["swarm_windup"]
	var samples: int = int(dur * MIX_RATE)
	var arr := PackedVector2Array()
	arr.resize(samples)
	var dt: float = 1.0 / MIX_RATE
	var phase: float = 0.0
	for i in range(samples):
		var t: float = float(i) * dt
		var k: float = t / dur
		var freq: float = lerpf(700.0, 1300.0, k)
		phase += TAU * freq * dt
		var chitter: float = 0.5 + 0.5 * signf(sin(TAU * 55.0 * t))
		var env: float = (0.4 + 0.6 * k) * minf(1.0, (dur - t) / 0.02)
		var s: float = clampf(sin(phase) * chitter * env * 0.5, -0.9, 0.9)
		arr[i] = Vector2(s, s)
	return arr

# "lunge_dash" — свист рывка врага: полоса шума, частота фильтра растёт и падает
func _gen_lunge_dash() -> PackedVector2Array:
	var dur: float = sound_durations["lunge_dash"]
	var samples: int = int(dur * MIX_RATE)
	var arr := PackedVector2Array()
	arr.resize(samples)
	var dt: float = 1.0 / MIX_RATE
	var low: float = 0.0
	var band: float = 0.0
	for i in range(samples):
		var t: float = float(i) * dt
		var k: float = t / dur
		var cutoff: float = 0.08 + 0.25 * sin(k * PI)
		var raw: float = randf_range(-1.0, 1.0)
		low = lerpf(low, raw, cutoff)
		band = lerpf(band, low, 0.5)
		var env: float = sin(k * PI)
		var s: float = clampf((low - band) * env * 2.2, -0.9, 0.9)
		arr[i] = Vector2(s, s)
	return arr

# "ranged_windup" / "flyer_charge" — заряд: восходящий тон с вибрато, громкость растёт к выстрелу
func _gen_charge_whine(sound_name: String, f_start: float, f_end: float, vibrato_hz: float) -> PackedVector2Array:
	var dur: float = sound_durations[sound_name]
	var samples: int = int(dur * MIX_RATE)
	var arr := PackedVector2Array()
	arr.resize(samples)
	var dt: float = 1.0 / MIX_RATE
	var phase: float = 0.0
	for i in range(samples):
		var t: float = float(i) * dt
		var k: float = t / dur
		var freq: float = lerpf(f_start, f_end, k) * (1.0 + 0.03 * sin(TAU * vibrato_hz * t))
		phase += TAU * freq * dt
		var tone: float = sin(phase) * 0.6 + sin(phase * 2.0) * 0.15
		var env: float = (0.15 + 0.85 * k * k) * minf(1.0, (dur - t) / 0.02)
		var s: float = clampf(tone * env * 0.7, -0.9, 0.9)
		arr[i] = Vector2(s, s)
	return arr

# "ranged_shot" — плазменный «туп» выстрела дальника: мягкий низкий спад с колебанием, без щелчка
# (не путать с резким выстрелом Калибра)
func _gen_ranged_shot() -> PackedVector2Array:
	var dur: float = sound_durations["ranged_shot"]
	var samples: int = int(dur * MIX_RATE)
	var arr := PackedVector2Array()
	arr.resize(samples)
	var dt: float = 1.0 / MIX_RATE
	var phase: float = 0.0
	for i in range(samples):
		var t: float = float(i) * dt
		var freq: float = (180.0 + 420.0 * exp(-18.0 * t)) * (1.0 + 0.08 * sin(TAU * 32.0 * t))
		phase += TAU * freq * dt
		var attack: float = minf(1.0, t / 0.008)
		var s: float = clampf(sin(phase) * attack * exp(-11.0 * t) * 0.75, -0.9, 0.9)
		arr[i] = Vector2(s, s)
	return arr

# "turret_windup" — электронный писк наводки турели: три учащающихся сигнала 1250 Гц
func _gen_turret_windup() -> PackedVector2Array:
	var dur: float = sound_durations["turret_windup"]
	var samples: int = int(dur * MIX_RATE)
	var arr := PackedVector2Array()
	arr.resize(samples)
	var dt: float = 1.0 / MIX_RATE
	var beeps: Array[Vector2] = [Vector2(0.0, 0.07), Vector2(0.13, 0.2), Vector2(0.24, 0.34)]
	for i in range(samples):
		var t: float = float(i) * dt
		var on: float = 0.0
		for b in beeps:
			if t >= b.x and t < b.y:
				on = minf(1.0, minf(t - b.x, b.y - t) / 0.004)
		var sq: float = signf(sin(TAU * 1250.0 * t)) * 0.3 + sin(TAU * 2500.0 * t) * 0.15
		var s: float = clampf(sq * on * 0.8, -0.9, 0.9)
		arr[i] = Vector2(s, s)
	return arr

# "flyer_laser" — включение луча летуна: гудящая пила 110 Гц с гармониками и вспышкой шума
func _gen_flyer_laser() -> PackedVector2Array:
	var dur: float = sound_durations["flyer_laser"]
	var samples: int = int(dur * MIX_RATE)
	var arr := PackedVector2Array()
	arr.resize(samples)
	var dt: float = 1.0 / MIX_RATE
	var phase: float = 0.0
	for i in range(samples):
		var t: float = float(i) * dt
		phase += TAU * 110.0 * dt
		var saw: float = fposmod(phase / TAU, 1.0) * 2.0 - 1.0
		var buzz: float = saw * 0.35 + sin(phase * 3.0) * 0.2
		var burst: float = randf_range(-1.0, 1.0) * exp(-25.0 * t) * 0.45
		var env: float = minf(1.0, t / 0.01) * minf(1.0, (dur - t) / 0.12)
		var s: float = clampf((buzz + burst) * env * 0.8, -0.9, 0.9)
		arr[i] = Vector2(s, s)
	return arr

# Петля низкого HP (AudioStreamWAV, LOOP_FORWARD): звон 3 кГц с медленным колебанием громкости и
# дыхание — полосовой шум с огибающей вдоха и выдоха. Все периоды укладываются в петлю целое число раз,
# огибающая дыхания на краях петли нулевая — шов без щелчка.
func _gen_low_health_wav() -> AudioStreamWAV:
	var samples: int = int(LOW_HEALTH_LOOP_TIME * MIX_RATE)
	var dt: float = 1.0 / MIX_RATE
	var byte_data := PackedByteArray()
	byte_data.resize(samples * 4)
	var low: float = 0.0
	var band: float = 0.0
	for i in range(samples):
		var t: float = float(i) * dt
		# Звон в ушах: 3000 Гц × 4 с = целое число периодов; громкость плывёт с периодом 4 с
		var ring: float = sin(TAU * 3000.0 * t) * (0.05 + 0.025 * sin(TAU * 0.25 * t))
		# Дыхание: цикл 2 с — вдох 0.0–0.8 с (ярче), выдох 0.9–1.8 с (ниже и мягче)
		var cycle: float = fmod(t, 2.0)
		var breath_env: float = 0.0
		var cutoff: float = 0.12
		if cycle < 0.8:
			breath_env = sin(cycle / 0.8 * PI) * 0.55
			cutoff = 0.2
		elif cycle >= 0.9 and cycle < 1.8:
			breath_env = sin((cycle - 0.9) / 0.9 * PI) * 0.4
			cutoff = 0.1
		low = lerpf(low, randf_range(-1.0, 1.0), cutoff)
		band = lerpf(band, low, 0.08)
		var breath: float = (low - band) * breath_env
		var s: float = clampf(ring + breath, -0.95, 0.95)
		var val_16: int = clampi(int(s * 32767.0), -32768, 32767)
		byte_data.encode_s16(i * 4, val_16)
		byte_data.encode_s16(i * 4 + 2, val_16)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(MIX_RATE)
	wav.stereo = true
	wav.data = byte_data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = samples
	return wav
