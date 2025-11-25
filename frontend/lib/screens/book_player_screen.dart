import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';
import '../models/voice.dart';
import '../services/tts_service.dart';
import '../services/api_service.dart';
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
  // Fuente gapless para transición instantánea entre segmentos ya descargados
  ConcatenatingAudioSource? _gaplessSource;
  final Set<int> _gaplessAdded = {}; // segment indices ya añadidos

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
  String? _documentoId; // UUID del documento real (no el libro_id)
  bool _addedToLibrary = false; // Para rastrear si ya se agregó a la biblioteca

  @override
  void initState() {
    super.initState();
    print('🎬 [BookPlayer] initState - Libro: ${widget.book.titulo}');
    _init();
  }

  Future<void> _init() async {
    print('🔄 [BookPlayer] Iniciando carga...');
    
    try {
      // Cargar voces mock
      print('   1. Cargando voces...');
      final voices = await TtsService.instance.getVoices();
      print('   ✅ ${voices.length} voces cargadas');
      
      // Seleccionar primera voz por defecto
      Voice current = voices.first;
      print('   Voz seleccionada: ${current.voiceCode}');
      
      // Cargar progreso previo si existe
      print('   2. Cargando progreso previo...');
      final progress = await TtsService.instance.loadProgress(widget.book.id, current.id);
      print('   ${progress != null ? "✅ Progreso encontrado" : "ℹ️ Sin progreso previo"}');
      
      setState(() {
        _voices = voices;
        _currentVoice = current;
        _progress = progress;
        _loadingVoices = false;
      });
      print('   ✅ Estado actualizado');
    } catch (e) {
      print('   ❌ Error en _init: $e');
      setState(() {
        _loadingVoices = false;
      });
    }

    // Avanzar automáticamente al siguiente segmento cuando termine el actual
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        // Guardar progreso final del segmento actual antes de avanzar
        _saveProgress();
        print('🔚 Segmento completado, intentando avanzar...');
        _playNext();
      }
    });

    // Supervisar playerState para capturar fin antes de que entre en completed (algunos backends)
    _player.playerStateStream.listen((playerState) {
      final processing = playerState.processingState;
      if (processing == ProcessingState.ready) {
        // Si estamos muy cerca del final (posición ~ duración) y aún no disparó completed
        final dur = _player.duration;
        final pos = _player.position;
        if (dur != null && pos >= dur - const Duration(milliseconds: 500)) {
          // Evitar doble avance si ya está reproduciendo siguiente
          if (!_player.playing) {
            print('⏭️ Auto-avance anticipado (posición ≈ duración)');
            _playNext();
          }
        }
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
    _autosaveTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  /// Agrega el libro a la biblioteca del usuario (marca como "en progreso")
  Future<void> _addToLibraryIfNeeded() async {
    if (_addedToLibrary) {
      print('ℹ️ Libro ya agregado anteriormente');
      return; // Ya se agregó
    }
    
    try {
      print('📚 Intentando agregar libro a biblioteca...');
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('backend_user_id');
      print('   User ID: $userId');
      print('   Book ID: ${widget.book.intId}');
      
      if (userId == null) {
        print('⚠️ No hay userId en SharedPreferences');
        return;
      }
      
      await ApiService.addBookToLibrary(userId, widget.book.intId);
      setState(() => _addedToLibrary = true);
      print('✅ Libro agregado a biblioteca (en progreso)');
    } catch (e) {
      // Ignorar errores silenciosamente (puede que ya esté agregado)
      print('ℹ️ No se pudo agregar a biblioteca: $e');
    }
  }

  void _togglePlay() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      // Si aún no tenemos playlist, usar quick-start para obtener el primer audio inmediatamente
      if (_playlist.isEmpty) {
        setState(() => _loadingSegment = true);
        try {
          // Agregar a biblioteca ANTES de empezar a reproducir
          await _addToLibraryIfNeeded();
          
          print('🎧 Iniciando quick-start para libro ${widget.book.intId}...');
          // Quick-start: genera y espera el primer audio
          final quickStartResult = await TtsService.instance.quickStartBook(
            widget.book.intId,
            _currentVoice!.id,
            nextCount: 10,
          ).timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Timeout: El audio está tardando mucho en generarse');
            },
          );
          
          final firstAudioUrl = quickStartResult['first_audio_url'] as String;
          final documentoId = quickStartResult['documento_id'] as String?;
          
          print('✅ Primer audio listo: $firstAudioUrl');
          print('📄 Documento ID: $documentoId');
          
          // Guardar documento_id para saveProgress
          if (documentoId != null) {
            setState(() {
              _documentoId = documentoId;
            });
          }
          
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
        // Ya tenemos playlist, buscar primer audio disponible y reproducir
        if (!_loadingSegment) {
          // Agregar a biblioteca también cuando reanuda
          await _addToLibraryIfNeeded();
          
          // Buscar el primer audio con URL válida desde el índice actual
          int indexToPlay = _currentIndex;
          for (int i = _currentIndex; i < _playlist.length; i++) {
            if (_playlist[i].url.toString().isNotEmpty) {
              indexToPlay = i;
              break;
            }
          }
          
          // Si no hay audios generados aún, esperar y polling
          if (_playlist[indexToPlay].url.toString().isEmpty) {
            setState(() => _loadingSegment = true);
            print('⏳ Esperando que se genere el primer audio...');
            _waitForFirstAudioAndPlay();
          } else {
            await _loadAndPlay(indexToPlay);
          }
          
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
    if (_currentVoice?.id == voice.id) return; // Ya está usando esta voz
    
    setState(() => _currentVoice = voice);
    
    // Detener reproducción actual
    await _player.stop();
    
    // Limpiar playlist
    _playlist = [];
    _currentIndex = 0;
    
    // Mostrar mensaje al usuario
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cambiando a voz: ${voice.voiceCode}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    
    // Usar quick-start para cargar el primer audio con la nueva voz
    setState(() => _loadingSegment = true);
    try {
      final quickStartResult = await TtsService.instance.quickStartBook(
        widget.book.intId,
        voice.id,
      );
      
      final firstAudioUrl = quickStartResult['first_audio_url'] as String;
      final documentoId = quickStartResult['documento_id'] as String?;
      
      // Guardar documento_id
      if (documentoId != null) {
        setState(() {
          _documentoId = documentoId;
        });
      }

      // Ajustar velocidad automáticamente según tipo de voz (Female más lenta, Male normal)
      if (voice.voiceCode.contains('Female')) {
        _speed = 0.90; // ligeramente más lenta
      } else if (voice.voiceCode.contains('Male')) {
        _speed = 1.05; // ligeramente más rápida
      } else {
        _speed = 1.0; // neutra
      }
      await _player.setSpeed(_speed);
      
      // Crear playlist con el primer audio
      // Usamos segmentId = 1 (primer segmento real) para reflejar orden > 0
      _playlist = [
        PlaylistItem(
          segmentId: 1,
          url: Uri.parse(firstAudioUrl),
          durationMs: null,
        ),
      ];
      _currentIndex = 0;
      
      // Reproducir automáticamente con la nueva voz
      await _loadAndPlay(0);
      
      // Cargar el resto de la playlist en background
      _ensurePlaylistLoaded();
      
    } catch (e) {
      print('Error cambiando voz: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cambiando voz: $e')),
        );
      }
    } finally {
      setState(() => _loadingSegment = false);
    }
  }

  Future<void> _saveProgress() async {
    if (_currentVoice == null || _documentoId == null) return;
    
    // Guardar posición actual con el índice real del segmento
    final pos = _player.position;
    final progress = PlayProgress(
      documentId: _documentoId!, // Usar el UUID del documento real
      voiceId: _currentVoice!.id,
      segmentId: _currentIndex, // Usar el índice actual del segmento en reproducción
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
      // autoGenerate: 3 para tener buffer inicial
      print('🚀 Cargando playlist inicial...');
      final result = await TtsService.instance.getBookAudios(
        widget.book.intId,
        autoGenerate: 3,
        voiceId: _currentVoice!.id, // Pasar la voz seleccionada
      );
      print('✅ Playlist cargada: ${result['urls']?.length ?? 0} segmentos');
      print('   Segmentos con audio: ${result['audios_generados'] ?? 0}');
      
      final audioUrls = result['urls'] as List<String>;
      final documentoId = result['documento_id'] as String?;
      
      // Guardar el documento_id real para usarlo en saveProgress
      if (documentoId != null) {
        setState(() {
          _documentoId = documentoId;
        });
      }
      
      // Convertir URLs a PlaylistItems (incluir TODOS los segmentos, con o sin audio)
      final items = audioUrls.asMap().entries.map((entry) {
        return PlaylistItem(
          segmentId: entry.key,
          url: entry.value.isEmpty ? Uri.parse('') : Uri.parse(entry.value),
          durationMs: null,
        );
      }).toList();
      
      setState(() {
        _playlist = items;
        // SIEMPRE empezar desde el primer audio (índice 0), no desde progreso anterior
        _currentIndex = 0;
      });

      // Construir fuente gapless inicial con los audios ya disponibles
      _setupGaplessInitial();

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
    // Consultar cada 5 segundos
    final interval = const Duration(seconds: 5);
    
    await Future.delayed(interval);
    if (!mounted || _loadingSegment) return;
    
    try {
      // Calcular cuántos audios adelante necesitamos generar
      final audiosRestantes = _playlist.where((p) => p.url.toString().isNotEmpty).length - _currentIndex;
      final shouldGenerate = audiosRestantes < 10;
      
      final result = await TtsService.instance.getBookAudios(
        widget.book.intId,
        autoGenerate: shouldGenerate ? 3 : 0,
        voiceId: _currentVoice?.id,
      );
      
      final audioUrls = result['urls'] as List<String>;
      final totalSegmentos = result['total_segmentos'] as int? ?? audioUrls.length;
      final audiosGenerados = result['audios_generados'] as int? ?? audioUrls.where((u) => u.isNotEmpty).length;
      
      // Actualizar playlist solo si hay cambios (nuevos audios generados)
      final currentGenerated = _playlist.where((p) => p.url.toString().isNotEmpty).length;
      if (audiosGenerados > currentGenerated || audioUrls.length != _playlist.length) {
        final items = audioUrls.asMap().entries.map((entry) {
          return PlaylistItem(
            segmentId: entry.key,
            url: entry.value.isEmpty ? Uri.parse('') : Uri.parse(entry.value),
            durationMs: null,
          );
        }).toList();
        
        setState(() => _playlist = items);
        // Añadir nuevos audios al source gapless para próximas transiciones instantáneas
        _appendGaplessNew();
        print('Playlist actualizada: $audiosGenerados/$totalSegmentos audios generados');
      }
      
      // Continuar polling hasta tener todos los audios generados
      if (audiosGenerados < totalSegmentos) {
        _schedulePlaylistRefresh();
      } else {
        print('✅ Todos los audios generados ($audiosGenerados/$totalSegmentos)');
      }
    } catch (e) {
      print('Error actualizando playlist: $e');
      // Reintentar en caso de error
      _schedulePlaylistRefresh();
    }
  }

  /// Espera hasta que haya al menos un audio generado y lo reproduce automáticamente
  Future<void> _waitForFirstAudioAndPlay() async {
    int attempts = 0;
    const maxAttempts = 20; // 20 intentos * 2s = 40s máximo
    
    while (attempts < maxAttempts && mounted) {
      try {
        // Consultar el backend por nuevos audios
        final result = await TtsService.instance.getBookAudios(
          widget.book.intId,
          autoGenerate: 3,
          voiceId: _currentVoice?.id,
        );
        
        final audioUrls = result['urls'] as List<String>;
        
        // Actualizar playlist
        final items = audioUrls.asMap().entries.map((entry) {
          return PlaylistItem(
            segmentId: entry.key,
            url: entry.value.isEmpty ? Uri.parse('') : Uri.parse(entry.value),
            durationMs: null,
          );
        }).toList();
        
        setState(() => _playlist = items);
        
        // Buscar primer audio disponible
        for (int i = 0; i < _playlist.length; i++) {
          if (_playlist[i].url.toString().isNotEmpty) {
            print('✅ Primer audio listo en índice $i, reproduciendo...');
            setState(() => _loadingSegment = false);
            await _loadAndPlay(i);
            return;
          }
        }
        
        // No hay audios todavía, esperar y reintentar
        print('⏳ Intento ${attempts + 1}/$maxAttempts - esperando primer audio...');
        await Future.delayed(const Duration(seconds: 2));
        attempts++;
      } catch (e) {
        print('Error esperando primer audio: $e');
        await Future.delayed(const Duration(seconds: 2));
        attempts++;
      }
    }
    
    // Timeout: no se generó ningún audio
    setState(() => _loadingSegment = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo generar el audio. Intenta de nuevo.')),
      );
    }
  }

  void _setupGaplessInitial() {
    if (_gaplessSource != null) return;
    final sources = <AudioSource>[];
    for (int i = 0; i < _playlist.length; i++) {
      final url = _playlist[i].url.toString();
      if (url.isNotEmpty) {
        sources.add(AudioSource.uri(Uri.parse(url)));
        _gaplessAdded.add(i);
      } else {
        break; // detener en primer faltante para añadir luego incrementalmente
      }
    }
    if (sources.isEmpty) return;
    _gaplessSource = ConcatenatingAudioSource(children: sources);
    _player.setAudioSource(_gaplessSource!, initialIndex: 0).then((_) async {
      await _player.play();
    }).onError((e, st) {
      print('Gapless init error: $e');
    });  
  }

  void _appendGaplessNew() {
    if (_gaplessSource == null) return;
    for (int i = 0; i < _playlist.length; i++) {
      if (_gaplessAdded.contains(i)) continue;
      final url = _playlist[i].url.toString();
      if (url.isEmpty) break; // parar en primer no generado
      _gaplessSource!.add(AudioSource.uri(Uri.parse(url)));  
      _gaplessAdded.add(i);
    }
  }

  Future<void> _loadAndPlay(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    setState(() => _loadingSegment = true);
    try {
      await _player.setSpeed(_speed);
      await _player.setUrl(_playlist[index].url.toString());
      // Guardar progreso (segmento actual, intra 0) inmediatamente para futuras sesiones
      final effectiveDocId = _documentoId ?? widget.book.id;
      final progress = PlayProgress(
        documentId: effectiveDocId,
        voiceId: _currentVoice!.id,
        segmentId: _playlist[index].segmentId,
        intraMs: 0,
        globalOffsetChar: null,
      );
      await TtsService.instance.saveProgress(progress);
      await _player.play();
      setState(() => _currentIndex = index);
      // Guardar progreso nuevamente con posición real tras iniciar (posición probablemente ~0)
      _saveProgress();
      
      // Prefetch agresivo: n+1, n+2, n+3, n+4, n+5 (los próximos 5 audios)
      _prefetchUpcoming(index);
      
      // Verificar si necesitamos generar más audios adelante
      _checkAndGenerateAhead(index);
    } finally {
      setState(() => _loadingSegment = false);
    }
  }
  
  /// Precarga los próximos 5 audios para transiciones instantáneas
  void _prefetchUpcoming(int currentIndex) async {
    for (var i = 1; i <= 5; i++) {
      final nextIndex = currentIndex + i;
      if (nextIndex >= _playlist.length) break;
      // Fire and forget - no esperar
      TtsService.instance.prefetchNext(_playlist, currentIndex + i - 1);
    }
  }
  
  /// Verifica si necesitamos generar más audios adelante
  void _checkAndGenerateAhead(int currentIndex) async {
    // Contar cuántos audios CON URL tenemos adelante
    final audiosGeneradosRestantes = _playlist
        .skip(currentIndex)
        .where((p) => p.url.toString().isNotEmpty)
        .length;
        
    if (audiosGeneradosRestantes < 5) {
      // Estamos cerca del final de audios GENERADOS, solicitar más
      print('⚡ Solicitando más audios (solo quedan $audiosGeneradosRestantes generados)...');
      try {
        final result = await TtsService.instance.getBookAudios(
          widget.book.intId,
          autoGenerate: 3,
          voiceId: _currentVoice?.id,
        );
        final audioUrls = result['urls'] as List<String>;
        final audiosGenerados = result['audios_generados'] as int? ?? audioUrls.where((u) => u.isNotEmpty).length;
        
        // Actualizar playlist con nuevas URLs generadas
        final items = audioUrls.asMap().entries.map((entry) {
          return PlaylistItem(
            segmentId: entry.key,
            url: entry.value.isEmpty ? Uri.parse('') : Uri.parse(entry.value),
            durationMs: null,
          );
        }).toList();
        setState(() => _playlist = items);
        print('✅ Playlist actualizada: $audiosGenerados audios generados');
      } catch (e) {
        print('Error generando audios adelante: $e');
      }
    }
  }

  Future<void> _playNext() async {
    // Buscar el siguiente audio disponible (con URL válida)
    // Si tenemos fuente gapless y siguiente índice ya está precargado, usar seek instantáneo
    if (_gaplessSource != null) {
      final nextIndex = _currentIndex + 1;
      if (_gaplessAdded.contains(nextIndex)) {
        print('⚡ Gapless seek a índice $nextIndex');
        await _player.seek(Duration.zero, index: nextIndex);
        setState(() => _currentIndex = nextIndex);
        _saveProgress();
        // Verificar prefetch y generación adicional
        _checkAndGenerateAhead(nextIndex);
        return;
      }
    }

    for (int i = _currentIndex + 1; i < _playlist.length; i++) {
      if (_playlist[i].url.toString().isNotEmpty) {
        print('▶️ Reproduciendo siguiente audio (índice $i)...');
        await _loadAndPlay(i);
        _saveProgress();
        return;
      }
    }
    
    // No hay más audios disponibles, esperar a que se generen
    print('⏸️ No hay más audios generados, solicitando generación adicional...');
    // Solicitar generación de más audios (buffer de 5)
    if (_currentVoice != null) {
      await TtsService.instance.generateMore(widget.book.intId, _currentVoice!.id, count: 5);
    }
    _waitForNextAudioAndPlay(_currentIndex + 1);
  }
  
  /// Espera a que el siguiente audio esté disponible y lo reproduce
  Future<void> _waitForNextAudioAndPlay(int startIndex) async {
    int attempts = 0;
    const maxAttempts = 10;
    
    while (attempts < maxAttempts && mounted) {
      await Future.delayed(const Duration(seconds: 3));
      
      try {
        // Refrescar playlist
        final result = await TtsService.instance.getBookAudios(
          widget.book.intId,
          autoGenerate: 3,
          voiceId: _currentVoice?.id,
        );
        
        final audioUrls = result['urls'] as List<String>;
        final items = audioUrls.asMap().entries.map((entry) {
          return PlaylistItem(
            segmentId: entry.key,
            url: entry.value.isEmpty ? Uri.parse('') : Uri.parse(entry.value),
            durationMs: null,
          );
        }).toList();
        
        setState(() => _playlist = items);
        
        // Buscar siguiente audio disponible
        for (int i = startIndex; i < _playlist.length; i++) {
          if (_playlist[i].url.toString().isNotEmpty) {
            print('✅ Siguiente audio listo en índice $i');
            await _loadAndPlay(i);
            return;
          }
        }
        
        // Escalada de generación: si pasaron varios intentos sin nuevo audio, pedir más agresivamente
        if (_currentVoice != null) {
          if (attempts == 3) {
            print('⚡ Escalada generación: solicitando 10 audios...');
            await TtsService.instance.generateMore(widget.book.intId, _currentVoice!.id, count: 10);
          } else if (attempts == 6) {
            print('🔥 Escalada generación: solicitando 20 audios...');
            await TtsService.instance.generateMore(widget.book.intId, _currentVoice!.id, count: 20);
          } else if (attempts == 8) {
            print('🚀 Escalada final: solicitando generación completa...');
            await TtsService.instance.generateMore(widget.book.intId, _currentVoice!.id, count: 1000);
          }
        }
        
        attempts++;
      } catch (e) {
        print('Error esperando siguiente audio: $e');
        attempts++;
      }
    }
    
    print('⏹️ No hay más audios disponibles');
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
                      'es': '🌐 Español',
                      'es-MX': '🇲🇽 México',
                      'es-ES': '🇪🇸 España',
                      'es-CO': '🇨🇴 Colombia',
                      'es-AR': '🇦🇷 Argentina',
                      'es-CL': '🇨🇱 Chile',
                      'es-PE': '🇵🇪 Perú',
                      'es-VE': '🇻🇪 Venezuela',
                      'en': '🇺🇸 English',
                      'en-US': '🇺🇸 English (US)',
                      'en-GB': '🇬🇧 English (UK)',
                    }[lang] ?? '🌐 $lang';

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
                          // Extraer información de la voz
                          final parts = voice.voiceCode.split('-');
                          String displayName;
                          String subtitle;
                          IconData icon;
                          
                          // Detectar si es Female/Male para Google TTS
                          if (voice.voiceCode.contains('Female')) {
                            displayName = parts.length > 2 
                                ? '${parts[1]} Femenina ${parts.last.replaceAll('Female', '')}'
                                : 'Voz Femenina ${parts.last.replaceAll('Female', '')}';
                            subtitle = '${voice.voiceCode} (Lenta/Clara)';
                            icon = Icons.woman;
                          } else if (voice.voiceCode.contains('Male')) {
                            displayName = parts.length > 2
                                ? '${parts[1]} Masculina ${parts.last.replaceAll('Male', '')}'
                                : 'Voz Masculina ${parts.last.replaceAll('Male', '')}';
                            subtitle = '${voice.voiceCode} (Normal/Rápida)';
                            icon = Icons.man;
                          } else {
                            // Fallback para otras voces
                            displayName = voice.voiceCode.split('-').last.replaceAll('Neural', '');
                            subtitle = voice.voiceCode;
                            icon = Icons.record_voice_over;
                          }
                          
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              icon,
                              color: _currentVoice?.id == voice.id
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey[600],
                              size: 28,
                            ),
                            title: Text(
                              displayName,
                              style: TextStyle(
                                fontWeight: _currentVoice?.id == voice.id 
                                    ? FontWeight.bold 
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              subtitle, 
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: _currentVoice?.id == voice.id
                                ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
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

  void _showPlaylistDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  'Partes del Audiolibro',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '${_playlist.length} ${_playlist.length == 1 ? "parte disponible" : "partes disponibles"}',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _playlist.length,
                  itemBuilder: (context, index) {
                    final isPlaying = _currentIndex == index && _player.playing;
                    final isCurrent = _currentIndex == index;
                    
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isCurrent
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[700],
                        child: Icon(
                          isPlaying ? Icons.volume_up : Icons.headphones,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Parte ${index + 1}',
                        style: TextStyle(
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        isCurrent 
                            ? (isPlaying ? 'Reproduciendo ahora' : 'En pausa')
                            : 'Toca para reproducir',
                        style: TextStyle(
                          color: isCurrent 
                              ? Theme.of(context).colorScheme.primary 
                              : Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      trailing: isCurrent
                          ? Icon(
                              isPlaying ? Icons.pause_circle : Icons.play_circle,
                              color: Theme.of(context).colorScheme.primary,
                              size: 32,
                            )
                          : Icon(
                              Icons.play_arrow,
                              color: Colors.grey[600],
                            ),
                      onTap: () async {
                        Navigator.pop(context);
                        // Si es la parte actual, solo toggle play/pause
                        if (isCurrent) {
                          _togglePlay();
                        } else {
                          // Cambiar a la parte seleccionada
                          setState(() {
                            _currentIndex = index;
                          });
                          await _loadAndPlay(index);
                        }
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
            icon: const Icon(Icons.list),
            onPressed: _playlist.isEmpty ? null : _showPlaylistDialog,
            tooltip: 'Ver partes del audiolibro',
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
