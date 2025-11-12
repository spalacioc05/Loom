import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:async';
import '../models/book.dart';
import '../models/voice.dart';
import '../services/tts_service.dart';
import '../models/play_progress.dart';
import '../models/playlist.dart';

/// Pantalla de reproducción de libro con controles básicos y selector de voz/velocidad.
class BookPlayerScreen extends StatefulWidget {
  final Book book;
  const BookPlayerScreen({super.key, required this.book});

  @override
  State<BookPlayerScreen> createState() => _BookPlayerScreenState();
}

class _BookPlayerScreenState extends State<BookPlayerScreen> {
  final AudioPlayer _player = AudioPlayer();
  List<Voice> _voices = [];
  Voice? _currentVoice;
  double _speed = 1.0; // velocidad de reproducción
  PlayProgress? _progress; // progreso cargado
  bool _loadingVoices = true;
  List<PlaylistItem> _playlist = [];
  int _currentIndex = 0;
  bool _loadingSegment = false;
  Timer? _autosaveTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Cargar voces mock
    final voices = await TtsService.instance.getVoices();
    // Seleccionar primera voz por defecto
    Voice current = voices.first;
    // Cargar progreso previo si existe
    final progress = await TtsService.instance.loadProgress(widget.book.id, current.id);
    setState(() {
      _voices = voices;
      _currentVoice = current;
      _progress = progress;
      _loadingVoices = false;
    });

    // Avanzar automáticamente al siguiente segmento cuando termine el actual
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _playNext();
      }
    });

    // Auto-save while playing: cuando empieza a reproducir, iniciar timer; cuando se pausa, guardar y cancelar
    _player.playingStream.listen((playing) {
      if (playing) {
        // iniciar timer si no existe
        _autosaveTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
          _saveProgress();
        });
      } else {
        // cancelar timer y guardar inmediatamente
        _autosaveTimer?.cancel();
        _autosaveTimer = null;
        _saveProgress();
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _togglePlay() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      // Si aún no tenemos playlist, usar quick-start para obtener el primer audio inmediatamente
      if (_playlist.isEmpty) {
        setState(() => _loadingSegment = true);
        try {
          // Quick-start: genera y espera el primer audio
          final firstAudioUrl = await TtsService.instance.quickStartBook(
            widget.book.intId,
            _currentVoice!.id,
          );
          
          // Crear playlist con el primer audio
          _playlist = [
            PlaylistItem(
              segmentId: 0,
              url: Uri.parse(firstAudioUrl),
              durationMs: null,
            ),
          ];
          _currentIndex = 0;
          
          // Reproducir inmediatamente
          await _loadAndPlay(0);
          
          // Cargar el resto de la playlist en background
          _ensurePlaylistLoaded();
          
        } catch (e) {
          print('Error en quick-start: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error cargando audio: $e')),
            );
          }
        } finally {
          setState(() => _loadingSegment = false);
        }
      } else {
        // Ya tenemos playlist, solo reproducir
        if (!_loadingSegment) {
          await _loadAndPlay(_currentIndex);
          // Continuar cargando más audios en background
          _schedulePlaylistRefresh();
        }
      }
    }
    // No necesitamos setState aquí, StreamBuilder se encarga
  }

  Future<void> _seekRelative(Duration delta) async {
    final pos = _player.position;
    final target = pos + delta;
    final total = _player.duration; // puede ser null si el stream aún no conoce la duración
    Duration seekTo;
    if (total != null) {
      // Limitar entre 0 y total cuando conocemos la duración real
      if (target < Duration.zero) {
        seekTo = Duration.zero;
      } else if (target > total) {
        seekTo = total;
      } else {
        seekTo = target;
      }
    } else {
      // Si no conocemos la duración, solo evitamos negativos y dejamos que el backend/decoder recorte el exceso
      seekTo = target < Duration.zero ? Duration.zero : target;
    }
    await _player.seek(seekTo);
  }

  Future<void> _onBackPressed() async {
    try {
      final pos = _player.position;
      // Si estamos cerca del inicio del segmento (ej. <3 segundos), ir al segmento anterior
      if (pos.inSeconds <= 3) {
        if (_currentIndex > 0) {
          await _loadAndPlay(_currentIndex - 1);
        } else {
          await _player.seek(Duration.zero);
        }
      } else {
        // De lo contrario, retroceder 20s
        await _seekRelative(const Duration(seconds: -20));
      }
    } catch (e) {
      print('Error handling back press: $e');
    }
  }

  void _changeSpeed(double newSpeed) async {
    _speed = newSpeed;
    await _player.setSpeed(_speed);
    setState(() {});
  }

  void _changeVoice(Voice voice) async {
    setState(() => _currentVoice = voice);
    // Reiniciar playlist con la nueva voz
    _playlist = [];
    _currentIndex = 0;
    await _player.stop();
    await _ensurePlaylistLoaded();
  }

  Future<void> _saveProgress() async {
    // Mock: guardar posición actual dentro de un segmento único.
    final pos = _player.position;
    final progress = PlayProgress(
      documentId: widget.book.id,
      voiceId: _currentVoice!.id,
      segmentId: 0, // mientras no hay segmentación real
      intraMs: pos.inMilliseconds,
      globalOffsetChar: null,
    );
    await TtsService.instance.saveProgress(progress);
    setState(() => _progress = progress);
  }

  Future<void> _ensurePlaylistLoaded() async {
    if (_currentVoice == null || _loadingSegment) return;
    setState(() => _loadingSegment = true);
    try {
      // Cargar todos los audios del libro con la voz seleccionada
      // autoGenerate: 10 para que genere los primeros segmentos inmediatamente
      final audioUrls = await TtsService.instance.getBookAudios(
        widget.book.intId,
        autoGenerate: 10,
        voiceId: _currentVoice!.id, // Pasar la voz seleccionada
      );
      
      // Convertir URLs a PlaylistItems
      final items = audioUrls.asMap().entries.map((entry) {
        return PlaylistItem(
          segmentId: entry.key,
          url: Uri.parse(entry.value),
          durationMs: null,
        );
      }).toList();
      
      setState(() {
        _playlist = items;
        // SIEMPRE empezar desde el primer audio (índice 0), no desde progreso anterior
        _currentIndex = 0;
      });

      // Siempre programar polling para actualizar cuando se generen más
      // (se detendrá automáticamente cuando tenga todos)
      _schedulePlaylistRefresh();
    } catch (e) {
      print('Error cargando playlist: $e');
      // Mostrar mensaje al usuario
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando audios: $e')),
        );
      }
    } finally {
      setState(() => _loadingSegment = false);
    }
  }

  /// Programa un refresh de la playlist para obtener nuevos audios generados
  void _schedulePlaylistRefresh() async {
    // Si hay pocos audios, consultar cada 2 segundos (más rápido al inicio para feedback inmediato)
    // Si ya hay varios, consultar cada 8 segundos
    final interval = _playlist.length < 5 
        ? const Duration(seconds: 2)  // Muy rápido al inicio
        : const Duration(seconds: 8); // Normal después
    
    await Future.delayed(interval);
    if (!mounted || _loadingSegment) return;
    
    try {
      final audioUrls = await TtsService.instance.getBookAudios(
        widget.book.intId,
        autoGenerate: 0, // No generar más, solo obtener los ya existentes
        voiceId: _currentVoice?.id, // Pasar la voz actual
      );
      
      if (audioUrls.length > _playlist.length) {
        // Hay nuevos audios, actualizar playlist
        final items = audioUrls.asMap().entries.map((entry) {
          return PlaylistItem(
            segmentId: entry.key,
            url: Uri.parse(entry.value),
            durationMs: null,
          );
        }).toList();
        
        setState(() => _playlist = items);
        print('Playlist actualizada: ${items.length} audios disponibles');
      }
      
      // Continuar polling hasta tener todos los 95 segmentos
      if (audioUrls.length < 95) {
        _schedulePlaylistRefresh();
      } else {
        print('✅ Todos los audios cargados (${audioUrls.length}/95)');
      }
    } catch (e) {
      print('Error actualizando playlist: $e');
      // Reintentar en caso de error
      _schedulePlaylistRefresh();
    }
  }

  Future<void> _loadAndPlay(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    setState(() => _loadingSegment = true);
    try {
      await _player.setSpeed(_speed);
      await _player.setUrl(_playlist[index].url.toString());
      // Guardar progreso (segmento actual, intra 0) inmediatamente para futuras sesiones
      final progress = PlayProgress(
        documentId: widget.book.id,
        voiceId: _currentVoice!.id,
        segmentId: _playlist[index].segmentId,
        intraMs: 0,
        globalOffsetChar: null,
      );
      await TtsService.instance.saveProgress(progress);
      await _player.play();
      setState(() => _currentIndex = index);
      // Prefetch n+1 y n+2
      await TtsService.instance.prefetchNext(_playlist, index);
    } finally {
      setState(() => _loadingSegment = false);
    }
  }

  Future<void> _playNext() async {
    final next = _currentIndex + 1;
    if (next < _playlist.length) {
      await _loadAndPlay(next);
    }
  }

  Stream<DurationState> get _durationStateStream => Rx.combineLatest3<Duration?, Duration, Duration, DurationState>(
        _player.durationStream,
        _player.positionStream,
        _player.bufferedPositionStream,
        (duration, position, buffered) => DurationState(
          progress: position,
          buffered: buffered,
          total: duration ?? const Duration(minutes: 1),
        ),
      );

  Widget _buildVoiceChip() {
    return InkWell(
      onTap: () => _showVoiceSelector(),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.record_voice_over,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _currentVoice?.voiceCode.split('-').last ?? 'Voz',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedChip() {
    return InkWell(
      onTap: () => _showSpeedSelector(),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.secondary.withOpacity(0.5),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.speed,
              size: 18,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 8),
            Text(
              '${_speed.toStringAsFixed(2)}x',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVoiceSelector() {
    // Agrupar voces por idioma/país
    final voicesByLang = <String, List<Voice>>{};
    for (var voice in _voices) {
      if (!voicesByLang.containsKey(voice.lang)) {
        voicesByLang[voice.lang] = [];
      }
      voicesByLang[voice.lang]!.add(voice);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  'Seleccionar Voz',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '${_voices.length} voces disponibles',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: voicesByLang.length,
                  itemBuilder: (context, index) {
                    final lang = voicesByLang.keys.elementAt(index);
                    final voices = voicesByLang[lang]!;
                    
                    // Nombre del país
                    final countryName = {
                      'es-MX': '🇲🇽 México',
                      'es-ES': '🇪🇸 España',
                      'es-CO': '🇨🇴 Colombia',
                      'es-AR': '🇦🇷 Argentina',
                      'es-CL': '🇨🇱 Chile',
                      'es-PE': '🇵🇪 Perú',
                      'es-VE': '🇻🇪 Venezuela',
                    }[lang] ?? lang;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                          child: Text(
                            countryName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ...voices.map((voice) {
                          // Extraer nombre corto (ej: "DaliaNeural" -> "Dalia")
                          final shortName = voice.voiceCode
                              .split('-')
                              .last
                              .replaceAll('Neural', '');
                          
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.record_voice_over,
                              color: _currentVoice?.id == voice.id
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            title: Text(shortName),
                            subtitle: Text(voice.voiceCode, style: const TextStyle(fontSize: 11)),
                            trailing: _currentVoice?.id == voice.id
                                ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                                : null,
                            onTap: () {
                              _changeVoice(voice);
                              Navigator.pop(context);
                            },
                          );
                        }),
                        const Divider(),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSpeedSelector() {
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  'Velocidad de Reproducción',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                'Ajusta la velocidad de la narración',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: speeds.length,
                  itemBuilder: (context, index) {
                    final speed = speeds[index];
                    final description = {
                      0.5: 'Muy lento',
                      0.75: 'Lento',
                      1.0: 'Normal',
                      1.25: 'Rápido',
                      1.5: 'Muy rápido',
                      1.75: 'Extra rápido',
                      2.0: 'Máximo',
                      2.5: 'Ultra rápido',
                    }[speed] ?? '';

                    return ListTile(
                      leading: Icon(
                        speed < 1.0 ? Icons.slow_motion_video : Icons.fast_forward,
                        color: _speed == speed
                            ? Theme.of(context).colorScheme.secondary
                            : null,
                      ),
                      title: Text('${speed.toStringAsFixed(2)}x'),
                      subtitle: Text(description),
                      trailing: _speed == speed
                          ? Icon(Icons.check, color: Theme.of(context).colorScheme.secondary)
                          : null,
                      onTap: () {
                        _changeSpeed(speed);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final coverUrl = widget.book.portada;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.titulo),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _currentVoice == null ? null : _saveProgress,
          ),
        ],
      ),
      body: _loadingVoices
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 3/4,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white12),
                            image: coverUrl != null && coverUrl.isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(coverUrl),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                            color: coverUrl == null ? Colors.grey[800] : null,
                          ),
                          child: coverUrl == null
                              ? const Center(child: Icon(Icons.book, size: 72))
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
                // Barra de progreso y controles
                StreamBuilder<DurationState>(
                  stream: _durationStateStream,
                  builder: (context, snapshot) {
                    final state = snapshot.data;
                    final progress = state?.progress ?? Duration.zero;
                    final total = state?.total ?? const Duration(minutes: 1);
                    return Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                          ),
                          child: Slider(
                            value: progress.inMilliseconds.clamp(0, total.inMilliseconds).toDouble(),
                            max: total.inMilliseconds.toDouble(),
                            onChanged: (v) async {
                              await _player.seek(Duration(milliseconds: v.toInt()));
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatDuration(progress)),
                              Text(_formatDuration(total)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Chips de selección: Voz y Velocidad
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // Chip de Voz
                              Expanded(
                                child: _buildVoiceChip(),
                              ),
                              const SizedBox(width: 12),
                              // Chip de Velocidad
                              Expanded(
                                child: _buildSpeedChip(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Controles de reproducción
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: 'Atrasar / segmento previo',
                              icon: const Icon(Icons.replay_10),
                              iconSize: 36,
                              onPressed: _onBackPressed,
                            ),
                            const SizedBox(width: 12),
                            // Botón de reproducir con indicador de carga.
                            // Mostrar spinner SOLO si estamos cargando y NO tenemos ya ningún audio disponible.
                            (_loadingSegment && _playlist.isEmpty)
                                ? const SizedBox(
                                    width: 56,
                                    height: 56,
                                    child: Padding(
                                      padding: EdgeInsets.all(12.0),
                                      child: CircularProgressIndicator(strokeWidth: 3),
                                    ),
                                  )
                                : StreamBuilder<bool>(
                                    stream: _player.playingStream,
                                    builder: (context, snapshot) {
                                      final playing = snapshot.data ?? false;
                                      return IconButton(
                                        tooltip: playing ? 'Pausar' : 'Reproducir',
                                        icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
                                        iconSize: 56,
                                        onPressed: _togglePlay,
                                      );
                                    },
                                  ),
                            const SizedBox(width: 12),
                            IconButton(
                              tooltip: 'Adelantar 10s',
                              icon: const Icon(Icons.forward_10),
                              iconSize: 36,
                              onPressed: () => _seekRelative(const Duration(seconds: 10)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Indicador de estado de carga
                        if (_loadingSegment && _playlist.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              'Generando primer audio...',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        if (_playlist.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              '${_playlist.length} audios disponibles',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        // Indicador de progreso guardado (si existe)
                        if (_progress != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.check_circle, size: 16, color: Colors.greenAccent),
                                SizedBox(width: 6),
                                Text('Progreso guardado', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                ),
              ],
            ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) {
      return '$h:$m:$s';
    }
    return '$m:$s';
  }
}

class DurationState {
  final Duration progress;
  final Duration buffered;
  final Duration total;
  DurationState({required this.progress, required this.buffered, required this.total});
}
