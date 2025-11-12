import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist.dart';
import '../models/play_progress.dart';
import '../models/voice.dart';
import '../auth/google_auth_service.dart';

/// Servicio de TTS (por ahora mock para UI) y persistencia de progreso local.
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  // Ajusta esta URL a la IP de tu backend accesible desde el dispositivo/emulador.
  // Sugerencia: usa SharedPreferences o un archivo de config si necesitas cambiarla en runtime.
  static const String _baseUrl = 'http://192.168.1.6:3000';

  /// Obtiene las voces reales del backend (`GET /voices`).
  Future<List<Voice>> getVoices() async {
    final uri = Uri.parse('$_baseUrl/voices');
    final resp = await http.get(uri).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw Exception('Error obteniendo voces: ${resp.statusCode} ${resp.body}');
    }
    final List<dynamic> data = jsonDecode(resp.body);
    return data.map((e) => Voice.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Obtiene TODOS los audios de un libro (`GET /tts/libro/:libroId/audios`).
  /// Retorna una lista de URLs ordenadas por segmento.
  /// Si autoGenerate > 0, genera automáticamente los primeros N audios faltantes.
  Future<List<String>> getBookAudios(int libroId, {int autoGenerate = 5, String? voiceId}) async {
    final queryParams = {
      'autoGenerate': autoGenerate.toString(),
      if (voiceId != null) 'voiceId': voiceId,
    };
    final uri = Uri.parse('$_baseUrl/tts/libro/$libroId/audios').replace(queryParameters: queryParams);
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
    
    if (resp.statusCode != 200) {
      throw Exception('Error obteniendo audios: ${resp.statusCode} ${resp.body}');
    }
    
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final audios = (map['audios'] as List<dynamic>? ?? []);
    
    // Filtrar solo los que tienen audio_url
    return audios
        .where((a) => a['audio_url'] != null)
        .map((a) => a['audio_url'] as String)
        .toList();
  }

  /// Quick-start: Genera el primer audio de forma síncrona y lo devuelve inmediatamente.
  /// Mientras tanto, genera los siguientes 3 audios en background.
  /// Retorna la URL del primer audio listo para reproducir.
  Future<String> quickStartBook(int libroId, String voiceId) async {
    final uri = Uri.parse('$_baseUrl/tts/libro/$libroId/quick-start');
    final body = {'voiceId': voiceId};
    
    print('🚀 QuickStart: Esperando primer audio para libro $libroId...');
    
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 30)); // Timeout generoso para generación
    
    if (resp.statusCode != 200) {
      throw Exception('Error en quick-start: ${resp.statusCode} ${resp.body}');
    }
    
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final firstAudioUrl = map['first_audio_url'] as String;
    
    print('✅ Primer audio listo: $firstAudioUrl');
    
    return firstAudioUrl;
  }

  /// Solicita una playlist inicial de segmentos (`POST /tts/playlist`).
  /// El backend devolverá hasta 5 segmentos y encolará más en background.
  Future<Playlist> getPlaylist({
    required String documentId,
    required String voiceId,
    int? fromOffsetChar,
  }) async {
    final uri = Uri.parse('$_baseUrl/tts/playlist');
    final body = {
      // Enviamos ambos por compatibilidad: si documentId no es UUID, el backend usará libro_id
      'document_id': documentId,
      'libro_id': documentId,
      'voice_id': voiceId,
      if (fromOffsetChar != null) 'from_offset_char': fromOffsetChar,
    };
    final resp = await http
        .post(uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      throw Exception('Error playlist: ${resp.statusCode} ${resp.body}');
    }

    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final itemsRaw = (map['items'] as List<dynamic>? ?? []);
    final items = itemsRaw.map((e) {
      final item = e as Map<String, dynamic>;
      final segId = item['segment_id'] as int;
      final urlString = item['url'] as String?; // puede ser null si no está generado
      return PlaylistItem(
        segmentId: segId,
        url: urlString != null
            ? Uri.parse(urlString)
            : buildSegmentAudioUri(documentId, voiceId, segId),
        durationMs: item['duration_ms'] as int?,
      );
    }).toList();

    return Playlist(
      documentId: documentId,
      voiceId: voiceId,
      items: items,
      startSegmentId: map['start_segment_id'] as int? ?? (items.isNotEmpty ? items.first.segmentId : 0),
      startIntraMs: map['start_intra_ms'] as int? ?? 0,
    );
  }

  /// Construye la URI para pedir el audio de un segmento. El backend hará redirect al MP3.
  Uri buildSegmentAudioUri(String documentId, String voiceId, int segmentId) {
    // Enviamos doc y libro por compatibilidad; el backend resolverá
    final params = 'doc=$documentId&libro=$documentId&voice=$voiceId&segment=$segmentId';
    return Uri.parse('$_baseUrl/tts/segment?$params');
  }

  /// Prefetch de los próximos segmentos (n+1, n+2) para reducir latencia.
  /// Simplemente dispara una petición GET que seguirá el redirect y cacheará en HTTP.
  Future<void> prefetchNext(List<PlaylistItem> playlist, int currentIndex) async {
    for (var offset = 1; offset <= 2; offset++) {
      final idx = currentIndex + offset;
      if (idx >= playlist.length) break;
      final uri = playlist[idx].url;
      try {
        // Usamos HEAD si el servidor soporta redirect; si no, GET.
        final resp = await http.get(uri).timeout(const Duration(seconds: 10));
        if (resp.statusCode >= 300 && resp.statusCode < 400) {
          // Redirect manual si fuese necesario (http package sigue redirects por defecto)
        }
        // No necesitamos nada más; el audio se habrá descargado y el player podrá usarlo desde cache temporal.
      } catch (e) {
        // Silencioso: el prefetch no debe romper la reproducción.
        // print('Prefetch fallo para ${uri.toString()}: $e');
      }
    }
  }

  // Persistencia local de progreso (clave por doc y voz)
  Future<void> saveProgress(PlayProgress progress) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _progressKey(progress.documentId, progress.voiceId);
    await prefs.setString(key, jsonEncode(progress.toJson()));
    // Intentar also sync con backend (no bloquear la UI si falla)
    try {
      final uri = Uri.parse('$_baseUrl/progress');
      final body = {
        'document_id': progress.documentId,
        'voice_id': progress.voiceId,
        'segment_id': progress.segmentId,
        'intra_ms': progress.intraMs,
        'global_offset_char': progress.globalOffsetChar,
      };
      // Adjuntar id_usuario del backend para asociar progreso a biblioteca
      String? backendUserId;
      try {
        backendUserId = await GoogleAuthService().getBackendUserId();
      } catch (_) {}
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (backendUserId != null) headers['x-user-id'] = backendUserId;
      final resp = await http
          .post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        // Ignorar fallos del backend, ya está guardado localmente
        // print('Advertencia: saveProgress backend responded ${resp.statusCode}');
      }
    } catch (e) {
      // Silencioso: si falla la sincronización, la app seguirá funcionando con el cache local
      // print('No se pudo sincronizar progreso con backend: $e');
    }
  }

  Future<PlayProgress?> loadProgress(String documentId, String voiceId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _progressKey(documentId, voiceId);
    final data = prefs.getString(key);
    if (data == null) return null;
    try {
      final map = jsonDecode(data) as Map<String, dynamic>;
      return PlayProgress.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  String _progressKey(String documentId, String voiceId) => 'progress:$documentId:$voiceId';
}
