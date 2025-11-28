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
  bool _isTransitioning = false; // Flag para prevenir múltiples transiciones simultáneas
  bool _userRequestedPlay = false; // true cuando el usuario presionó play
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
      // Cargar voces reales del backend (incluye Google TTS)
      print('   1. Cargando voces...');
      final voices = await TtsService.instance.getVoices();
      print('   ✅ ${voices.length} voces cargadas (backend)');

      // Filtrar SOLO voces GCP y condensar: por estilo (voiceType) seleccionar 4 voces
      // por estilo: 2 en inglés (1F + 1M) y 2 en español (1F + 1M)
      final gcp = voices.where((v) => v.provider == 'gcp').toList();
      final source = gcp.isNotEmpty ? gcp : voices;

      final preferredStyles = ['Neural2', 'Wavenet', 'Studio', 'Journey', 'Chirp', 'Standard'];

      // Agrupar por estilo
      final Map<String, List<Voice>> byStyle = {};
      for (final v in source) {
        final style = v.voiceType;
        byStyle.putIfAbsent(style, () => []);
        byStyle[style]!.add(v);
      }

      final condensed = <Voice>[];
      final styles = preferredStyles.where((s) => byStyle.containsKey(s)).toList() + byStyle.keys.where((k) => !preferredStyles.contains(k)).toList();

      for (final style in styles) {
        final list = byStyle[style] ?? [];
        if (list.isEmpty) continue;

        // Crear sublistas por idioma
        final enList = list.where((v) => v.lang.startsWith('en')).toList();
        final esList = list.where((v) => v.lang.startsWith('es')).toList();

        // Helper para elegir 1F + 1M de una lista
        Voice? pickFemale(List<Voice> lst) {
          for (final v in lst) {
            if (v.gender.toUpperCase() == 'FEMALE') return v;
          }
          return lst.isNotEmpty ? lst.first : null;
        }

        Voice? pickMale(List<Voice> lst) {
          for (final v in lst) {
            if (v.gender.toUpperCase() == 'MALE') return v;
          }
          return lst.isNotEmpty ? lst.first : null;
        }

        final enF = pickFemale(enList);
        final enM = pickMale(enList.where((v) => v.id != enF?.id).toList());
        final esF = pickFemale(esList);
        final esM = pickMale(esList.where((v) => v.id != esF?.id).toList());

        // Añadir en orden: ES F, ES M, EN F, EN M (o el orden que prefieras)
        if (esF != null && !condensed.any((c) => c.id == esF.id)) condensed.add(esF);
        if (esM != null && !condensed.any((c) => c.id == esM.id)) condensed.add(esM);
        if (enF != null && !condensed.any((c) => c.id == enF.id)) condensed.add(enF);
        if (enM != null && !condensed.any((c) => c.id == enM.id)) condensed.add(enM);
      }

      print('   🔎 Voces condensadas: ${condensed.length} (máx 2 por idioma)');

      // Preferir voz por defecto: preferir explicitamente 'es-ES-Wavenet-E' cuando exista
      Voice current = condensed.firstWhere(
        (v) => v.provider == 'gcp' && v.voiceCode.contains('es-ES-Wavenet-E'),
        orElse: () => condensed.firstWhere(
          (v) => v.provider == 'gcp' && v.lang.startsWith('es') && v.voiceCode.contains('Wavenet'),
          orElse: () => condensed.firstWhere(
            (v) => v.provider == 'gcp' && v.lang.startsWith('es'),
            orElse: () => condensed.isNotEmpty ? condensed.first : voices.first,
          ),
        ),
      );
      print('   Voz seleccionada por defecto: ${current.voiceCode} (${current.provider})');
      
      // Cargar progreso previo si existe
      print('   2. Cargando progreso previo...');
      final progress = await TtsService.instance.loadProgress(widget.book.id, current.id);
      print('   ${progress != null ? "✅ Progreso encontrado" : "ℹ️ Sin progreso previo"}');
      
      setState(() {
        _voices = condensed.isNotEmpty ? condensed : voices;
        _currentVoice = current;
        _progress = progress;
        _loadingVoices = false;
      });
      // Intentar arrancar reproducción desde DB inmediatamente si ya hay audios generados
      _tryStartFromDb();
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
      // Usuario pausó manualmente
      _userRequestedPlay = false;
      await _player.pause();
    } else {
      // Usuario solicitó reproducir
      _userRequestedPlay = true;
      // Asegurar que exista una voz seleccionada; si no, intentar cargar y elegir una por defecto
      if (_currentVoice == null) {
        try {
          final voices = await TtsService.instance.getVoices();
          if (voices.isNotEmpty) {
            final defaultVoice = voices.firstWhere(
              (v) => v.provider == 'gcp' && v.voiceCode.contains('es-ES-Wavenet-E'),
              orElse: () => voices.firstWhere(
                (v) => v.provider == 'gcp' && v.lang.startsWith('es') && v.voiceCode.contains('Wavenet'),
                orElse: () => voices.firstWhere(
                  (v) => v.provider == 'gcp' && v.lang.startsWith('es'),
                  orElse: () => voices.first,
                ),
              ),
            );
            setState(() => _currentVoice = defaultVoice);
            print('🔔 Voz por defecto aplicada antes de reproducir: ${defaultVoice.voiceCode}');
          }
        } catch (e) {
          print('⚠️ No se pudo cargar voz por defecto: $e');
        }
      }

      // Si aún no tenemos playlist, usar quick-start para obtener el primer audio inmediatamente
      if (_playlist.isEmpty) {
        setState(() => _loadingSegment = true);
          try {
          // Agregar a biblioteca ANTES de empezar a reproducir
          await _addToLibraryIfNeeded();
          
          print('🎧 Iniciando quick-start para libro ${widget.book.intId}...');
          // Quick-start: genera y espera el primer audio
          // Llamamos al quick-start pero lo manejamos de forma silenciosa: si el backend
          // responde 202 (segmentación en curso) no enseñamos errores feos sino que
          // iniciamos polling en background para esperar el primer audio.
          final quickStartResp = await TtsService.instance.quickStartBook(
            widget.book.intId,
            _currentVoice!.id,
            nextCount: 10,
          ).timeout(
            const Duration(seconds: 30),
            onTimeout: () => {'status': -1, 'body': 'timeout'},
          );

          final status = quickStartResp['status'] as int? ?? -1;
          final body = quickStartResp['body'];

          if (status == 200) {
            // Respuesta OK: backend entregó el primer audio
            final map = body as Map<String, dynamic>;
            final firstAudioUrl = map['first_audio_url'] as String;
            final documentoId = map['documento_id'] as String?;

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
          } else if (status == 202) {
            // Segmentación en curso: no mostrar error al usuario, iniciar polling silencioso
            print('ℹ️ Quick-start: segmentación iniciada en backend (202). Iniciando polling silencioso.');
            setState(() => _loadingSegment = true);
            // Llamar al polling que ya existe para esperar el primer audio y reproducirlo
            _waitForFirstAudioAndPlay();
          } else {
            // Errores o timeouts: mostrar mensaje genérico y permitir reintento manual
            print('⚠️ quick-start devolvió status=$status, body=$body');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No se pudo iniciar la reproducción. Intenta de nuevo.')),
              );
            }
          }
          
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

    // Limpiar playlist localmente para iniciar con la nueva voz
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

    // Intentar obtener una playlist desde el backend pidiendo que prefiera audios existentes
    // y que genere sincrónicamente el primer segmento faltante para no reiniciar la reproducción.
    setState(() => _loadingSegment = true);
    try {
      final docId = _documentoId ?? widget.book.id.toString();

      final playlist = await TtsService.instance.getPlaylist(
        documentId: docId,
        voiceId: voice.id,
        startSegmentId: null,
        preferExisting: true,
        generateFirstIfMissing: true,
      );

      // Guardar documento_id si viene
      if (playlist.documentId.isNotEmpty) {
        setState(() {
          _documentoId = playlist.documentId;
        });
      }

      // Ajustar velocidad automáticamente según tipo de voz (heurística simple)
      if (voice.voiceCode.toLowerCase().contains('female') || voice.gender.toUpperCase() == 'FEMALE') {
        _speed = 0.90;
      } else if (voice.voiceCode.toLowerCase().contains('male') || voice.gender.toUpperCase() == 'MALE') {
        _speed = 1.05;
      } else {
        _speed = 1.0;
      }
      await _player.setSpeed(_speed);

      // Usar los items devueltos por el backend
      setState(() {
        _playlist = playlist.items;
      });

      // Determinar índice inicial
      final startSeg = playlist.startSegmentId;
      final idx = _playlist.indexWhere((it) => it.segmentId == startSeg);
      _currentIndex = idx >= 0 ? idx : 0;

      // Reproducir inmediatamente el segmento inicial
      await _loadAndPlay(_currentIndex);

      // Cargar el resto de la playlist en background
      _ensurePlaylistLoaded();
    } catch (e) {
      print('Error cambiando voz (getPlaylist): $e');
      // Evitar mostrar errores técnicos al usuario. Mostrar mensaje amigable y reintentar en background.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo cambiar la voz ahora. Reintentando en segundo plano.')),
        );
      }
      // Iniciar intento silencioso de refrescar la playlist en background
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _ensurePlaylistLoaded();
      });
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

      // Pedir generación agresiva en background para evitar que la reproducción se quede sin audios
      if (_currentVoice != null) {
        // Solicitar generación de un buffer grande (50) en background. No bloquea.
        Future.microtask(() async {
          try {
            await TtsService.instance.generateMore(widget.book.intId, _currentVoice!.id, count: 50);
          } catch (e) {
            print('⚠️ Error solicitando generación agresiva: $e');
          }
        });
      }

      // Siempre programar polling para actualizar cuando se generen más
      // (se detendrá automáticamente cuando tenga todos)
      _schedulePlaylistRefresh();
    } catch (e) {
      print('Error cargando playlist: $e');
      // Errores automáticos no deben mostrarse crudos al usuario. Mantener silent fail and retry.
      print('⚠️ Error cargando playlist (silencioso): $e');
    } finally {
      setState(() => _loadingSegment = false);
    }
  }

  /// Intenta cargar audios desde la BD al abrir el libro y reproducir el primer audio
  /// disponible inmediatamente (sin pasar por quick-start) si existe.
  Future<void> _tryStartFromDb() async {
    try {
      if (_currentVoice == null) return;

      // Pedir al backend todos los audios SIN generar nuevos (autoGenerate = 0)
      final result = await TtsService.instance.getBookAudios(
        widget.book.intId,
        autoGenerate: 0,
        voiceId: _currentVoice!.id,
      );

      final urls = result['urls'] as List<String>;
      final documentoId = result['documento_id'] as String?;

      // Guardar documento_id si viene
      if (documentoId != null && documentoId.isNotEmpty) {
        _documentoId = documentoId;
      }

      // Buscar primer audio ya generado
      int firstIndex = -1;
      for (int i = 0; i < urls.length; i++) {
        if (urls[i].isNotEmpty) {
          firstIndex = i;
          break;
        }
      }

      if (firstIndex >= 0) {
        // Construir playlist con todas las URLs (vacías donde no hay audio)
        final items = urls.asMap().entries.map((entry) {
          return PlaylistItem(
            segmentId: entry.key,
            url: entry.value.isEmpty ? Uri.parse('') : Uri.parse(entry.value),
            durationMs: null,
          );
        }).toList();

        setState(() {
          _playlist = items;
          _currentIndex = firstIndex;
          _loadingSegment = false;
        });

        // No reproducir automáticamente al entrar al libro.
        // Si el usuario ya presionó Play antes de que esto se complete, reproducir ahora.
        if (_userRequestedPlay) {
          await _loadAndPlay(firstIndex);
        }

        // Continuar cargando/generando en background si hace falta
        _ensurePlaylistLoaded();
      } else {
        // No hay audios en DB: no forzamos quick-start aquí (la UI podrá usar quick-start al tocar play)
        print('ℹ️ No hay audios en BD para libro ${widget.book.intId} (voz ${_currentVoice!.voiceCode})');
      }
    } catch (e) {
      print('⚠️ Error intentando reproducir desde BD: $e');
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
        
        // Reconfigurar gapless si es necesario
        if (_gaplessSource == null && items.where((i) => i.url.toString().isNotEmpty).length > 3) {
          _setupGaplessPlaylist();
        }
        
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
            print('✅ Primer audio listo en índice $i');
            setState(() => _loadingSegment = false);
            // Solo reproducir automáticamente si el usuario había solicitado play
            if (_userRequestedPlay) {
              print('ℹ️ Usuario solicitó reproducción: iniciando automáticamente');
              await _loadAndPlay(i);
            }
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
    // No mostrar alertas técnicas al usuario; dejamos el botón de reproducir disponible
    print('⚠️ Timeout esperando primer audio - no se generó a tiempo');
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
      // Solo iniciar reproducción automática si el usuario ya solicitó play
      if (_userRequestedPlay) {
        await _player.play();
      }
    }).onError((e, st) {
      print('Gapless init error: $e');
    });  
  }
  
  /// Configura playlist gapless completa con todos los audios disponibles
  void _setupGaplessPlaylist() {
    final sources = <AudioSource>[];
    _gaplessAdded.clear();
    
    for (int i = 0; i < _playlist.length; i++) {
      final url = _playlist[i].url.toString();
      if (url.isNotEmpty) {
        sources.add(AudioSource.uri(Uri.parse(url)));
        _gaplessAdded.add(i);
      }
    }
    
    if (sources.isEmpty) {
      print('⚠️ No hay audios para configurar gapless');
      return;
    }
    
    print('🎵 Configurando playlist gapless con ${sources.length} audios');
    _gaplessSource = ConcatenatingAudioSource(
      children: sources,
      useLazyPreparation: true, // Preparar bajo demanda para mejor performance
    );
    
    // Configurar como fuente principal del player
    _player.setAudioSource(_gaplessSource!, initialIndex: _currentIndex).catchError((e) {
      print('❌ Error configurando gapless: $e');
      return null; // Retornar null en caso de error
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
    
    // Proteger contra llamadas múltiples
    if (_loadingSegment) {
      print('⚠️ Ya está cargando un segmento, ignorando...');
      return;
    }
    
    setState(() => _loadingSegment = true);
    try {
      // Si tenemos gapless source y el índice está cargado, usar seek (FLUIDO)
      if (_gaplessSource != null && _gaplessAdded.contains(index)) {
        print('⚡ Reproducción FLUIDA - seek a índice $index');
        await _player.seek(Duration.zero, index: index);
        setState(() => _currentIndex = index);
        
        // Si no estaba reproduciendo, iniciar
        if (!_player.playing) {
          await _player.play();
        }
      } else {
        // Fallback: reproducir audio individual (CON PAUSA)
        print('🔄 Carga tradicional - índice $index');
        await _player.stop();
        await _player.setSpeed(_speed);
        await _player.setUrl(_playlist[index].url.toString());
        setState(() => _currentIndex = index);
        await _player.play();
      }
      
      // Guardar progreso
      final effectiveDocId = _documentoId ?? widget.book.id;
      final progress = PlayProgress(
        documentId: effectiveDocId,
        voiceId: _currentVoice!.id,
        segmentId: _playlist[index].segmentId,
        intraMs: 0,
        globalOffsetChar: null,
      );
      await TtsService.instance.saveProgress(progress);
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
    // Prevenir múltiples llamadas simultáneas
    if (_isTransitioning) {
      print('⏸️ Ya está en transición, ignorando _playNext...');
      return;
    }
    
    _isTransitioning = true;
    try {
      // Buscar el siguiente audio disponible (con URL válida)
      // Si tenemos fuente gapless y siguiente índice ya está precargado, usar seek instantáneo
      if (_gaplessSource != null) {
        final nextIndex = _currentIndex + 1;
        if (_gaplessAdded.contains(nextIndex)) {
          print('⚡ Gapless seek a índice $nextIndex');
          // Pausar antes de seek para evitar que el reproductor repita el segmento actual
          try {
            if (_player.playing) await _player.pause();
          } catch (_) {}

          await _player.seek(Duration.zero, index: nextIndex);
          setState(() => _currentIndex = nextIndex);

          // Reanudar reproducción solo si el usuario había solicitado play
          if (_userRequestedPlay) {
            try {
              await _player.play();
            } catch (_) {}
          }

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
    } finally {
      _isTransitioning = false;
    }
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
                _currentVoice?.name ?? 'Seleccionar voz',
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
    if (_voices.isEmpty) return;

    // Forzar: usar SOLO voces de Google (gcp). Si por alguna razón no hay, caer a todas.
    final googleVoices = _voices.where((v) => v.provider == 'gcp').toList();
    final source = googleVoices.isNotEmpty ? googleVoices : _voices;

    // Condensar por estilo: por cada estilo mostrar hasta 4 voces (ES F, ES M, EN F, EN M)
    final preferredStyles = ['Neural2', 'Wavenet', 'Studio', 'Journey', 'Chirp', 'Standard'];
    final Map<String, List<Voice>> byStyle = {};
    for (final v in source) {
      final style = v.voiceType;
      byStyle.putIfAbsent(style, () => []);
      byStyle[style]!.add(v);
    }

    final voicesToShow = <Voice>[];
    final styles = preferredStyles.where((s) => byStyle.containsKey(s)).toList() + byStyle.keys.where((k) => !preferredStyles.contains(k)).toList();
    for (final style in styles) {
      final list = byStyle[style] ?? [];
      if (list.isEmpty) continue;

      final enList = list.where((v) => v.lang.startsWith('en')).toList();
      final esList = list.where((v) => v.lang.startsWith('es')).toList();

      Voice? pickFemale(List<Voice> lst) {
        for (final v in lst) if (v.gender.toUpperCase() == 'FEMALE') return v;
        return lst.isNotEmpty ? lst.first : null;
      }
      Voice? pickMale(List<Voice> lst) {
        for (final v in lst) if (v.gender.toUpperCase() == 'MALE') return v;
        return lst.isNotEmpty ? lst.first : null;
      }

      final esF = pickFemale(esList);
      final esM = pickMale(esList.where((v) => v.id != esF?.id).toList());
      final enF = pickFemale(enList);
      final enM = pickMale(enList.where((v) => v.id != enF?.id).toList());

      if (esF != null && !voicesToShow.any((c) => c.id == esF.id)) voicesToShow.add(esF);
      if (esM != null && !voicesToShow.any((c) => c.id == esM.id)) voicesToShow.add(esM);
      if (enF != null && !voicesToShow.any((c) => c.id == enF.id)) voicesToShow.add(enF);
      if (enM != null && !voicesToShow.any((c) => c.id == enM.id)) voicesToShow.add(enM);
    }
    
    // Agrupar por tipo para la UI (Neural2, Wavenet, Studio, etc.)
    final Map<String, List<Voice>> groupedVoices = {};
    for (final voice in voicesToShow) {
      final type = voice.voiceType;
      groupedVoices.putIfAbsent(type, () => []);
      groupedVoices[type]!.add(voice);
    }

    // Ordenar grupos por calidad (Neural2 > Studio > Wavenet > Chirp > Standard > Otro)
    final orderedTypes = ['Neural2', 'Studio', 'Wavenet', 'Journey', 'Chirp', 'Standard', 'Otro'];
    final sortedTypes = orderedTypes.where((t) => groupedVoices.containsKey(t)).toList();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.record_voice_over, color: Color(0xFF00D9FF), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Seleccionar Voz',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        Text(
                              '${voicesToShow.length} voces Google disponibles',
                              style: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: Colors.grey[800]),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: sortedTypes.length,
                  itemBuilder: (context, groupIndex) {
                    final type = sortedTypes[groupIndex];
                    final voices = groupedVoices[type]!;
                    
                    // Descripción del tipo de voz
                    String typeDescription;
                    Color typeColor;
                    switch (type) {
                      case 'Neural2':
                        typeDescription = 'Última generación - Muy natural';
                        typeColor = const Color(0xFF00D9FF);
                        break;
                      case 'Studio':
                        typeDescription = 'Optimizada para contenido largo';
                        typeColor = const Color(0xFF00FF88);
                        break;
                      case 'Wavenet':
                        typeDescription = 'Alta calidad';
                        typeColor = const Color(0xFFFFAA00);
                        break;
                      case 'Journey':
                        typeDescription = 'Conversacional';
                        typeColor = const Color(0xFFFF6B9D);
                        break;
                      case 'Chirp':
                        typeDescription = 'Emocional y expresiva';
                        typeColor = const Color(0xFFAA88FF);
                        break;
                      default:
                        typeDescription = 'Calidad estándar';
                        typeColor = Colors.grey;
                    }
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header del grupo
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: typeColor,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                type,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: typeColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  typeDescription,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Voces del grupo
                        ...voices.map((voice) {
                          final isSelected = _currentVoice?.id == voice.id;
                          
                          // Determinar emoji por idioma
                          String emoji;
                          if (voice.lang.startsWith('es')) {
                            emoji = '🇪🇸';
                          } else if (voice.lang.startsWith('en')) {
                            emoji = '🇺🇸';
                          } else {
                            emoji = '🌐';
                          }
                          
                          final voiceName = voice.name;
                          final gender = voice.gender;
                          final description = voice.description;
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: isSelected 
                                ? typeColor.withOpacity(0.15) 
                                : const Color(0xFF2A2A2A),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: isSelected 
                                  ? BorderSide(color: typeColor, width: 2)
                                  : BorderSide.none,
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor: isSelected 
                                    ? typeColor 
                                    : Colors.grey[700],
                                child: Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 18),
                                ),
                              ),
                              title: Text(
                                voiceName,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 15,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    gender,
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    description,
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                              trailing: isSelected
                                  ? Icon(Icons.check_circle, color: typeColor, size: 24)
                                  : Icon(Icons.play_circle_outline, color: Colors.grey[600], size: 24),
                              onTap: () {
                                _changeVoice(voice);
                                Navigator.pop(context);
                              },
                            ),
                          );
                        }),
                        const SizedBox(height: 12),
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
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Velocidad de Reproducción',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Ajusta la velocidad de la narración',
                style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 14),
              ),
              const SizedBox(height: 16),
              Divider(color: Colors.grey[800]),
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

                    final isSelected = _speed == speed;

                    return ListTile(
                      leading: Icon(
                        speed < 1.0 ? Icons.slow_motion_video : Icons.fast_forward,
                        color: isSelected ? const Color(0xFF00D9FF) : Colors.grey,
                      ),
                      title: Text(
                        '${speed.toStringAsFixed(2)}x',
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        description,
                        style: const TextStyle(color: Color(0xFFB0B0B0)),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: Color(0xFF00D9FF))
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
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Partes del Audiolibro',
                style: TextStyle(
                  fontSize: 24, 
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_playlist.length} ${_playlist.length == 1 ? "parte disponible" : "partes disponibles"}',
                style: const TextStyle(
                  color: Color(0xFFB0B0B0), 
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              Divider(color: Colors.grey[800]),
              const SizedBox(height: 8),
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
                            ? const Color(0xFF00D9FF)
                            : const Color(0xFF2A2A2A),
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
                          color: Colors.white,
                        ),
                      ),
                      subtitle: Text(
                        isCurrent 
                            ? (isPlaying ? 'Reproduciendo ahora' : 'En pausa')
                            : 'Toca para reproducir',
                        style: TextStyle(
                          color: isCurrent 
                              ? const Color(0xFF00D9FF)
                              : const Color(0xFFB0B0B0),
                          fontSize: 12,
                        ),
                      ),
                      trailing: isCurrent
                          ? const Icon(
                              Icons.check_circle,
                              color: Color(0xFF00D9FF),
                              size: 28,
                            )
                          : Icon(
                              Icons.play_arrow,
                              color: Colors.grey[600],
                              size: 28,
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
                              ? Center(
                                  child: Image.asset(
                                    'assets/loom_splash.png',
                                    fit: BoxFit.cover,
                                  ),
                                )
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
