import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist.dart';
import '../models/play_progress.dart';
import '../models/voice.dart';
import '../auth/google_auth_service.dart';
import 'api_service.dart';

/// Servicio de TTS (por ahora mock para UI) y persistencia de progreso local.
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  /// Obtiene la URL base del backend usando la misma lógica que ApiService
  Future<String> get _baseUrl async => await ApiService.resolveBaseUrl();

  /// Obtiene las voces reales del backend (`GET /voices`).
  Future<List<Voice>> getVoices() async {
    print('[TTS] 🔍 Solicitando voces al backend...');
    final baseUrl = await _baseUrl;
    final uri = Uri.parse('$baseUrl/voices');
    final resp = await http.get(uri).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw Exception('Error obteniendo voces: ${resp.statusCode} ${resp.body}');
    }
    print('[TTS] ✅ Voces obtenidas del backend');
    final List<dynamic> data = jsonDecode(resp.body);
    return data.map((e) => Voice.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Obtiene TODOS los audios de un libro (`GET /tts/libro/:libroId/audios`).
  /// Retorna una lista de URLs ordenadas por segmento Y el documento_id.
  /// Si autoGenerate > 0, genera automáticamente los primeros N audios faltantes.
  Future<Map<String, dynamic>> getBookAudios(int libroId, {int autoGenerate = 5, String? voiceId}) async {
    print('📚 [TTS] getBookAudios - Libro: $libroId, autoGen: $autoGenerate, voiceId: $voiceId');
    
    final baseUrl = await _baseUrl;
    final queryParams = {
      'autoGenerate': autoGenerate.toString(),
      if (voiceId != null) 'voiceId': voiceId,
    };
    final uri = Uri.parse('$baseUrl/tts/libro/$libroId/audios').replace(queryParameters: queryParams);
    print('   URL: $uri');
    
    try {
      // Timeout generoso: Si genera 10 audios en paralelo puede tardar hasta 30s
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      print('   Status: ${resp.statusCode}');
      
      if (resp.statusCode != 200) {
        print('   ❌ Error: ${resp.body}');
        throw Exception('Error obteniendo audios: ${resp.statusCode} ${resp.body}');
      }
      
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      final audios = (map['audios'] as List<dynamic>? ?? []);
      print('   ✅ Total segmentos: ${audios.length}');
      
      // DEVOLVER TODOS LOS SEGMENTOS (con o sin audio)
      // Los que no tienen audio_url se marcarán con URL vacía para mostrar en playlist
      final urls = audios
          .map((a) => (a['audio_url'] as String?) ?? '')
          .toList();
      
      final conAudio = urls.where((url) => url.isNotEmpty).length;
      print('   ✅ Segmentos con audio: $conAudio/${urls.length}');
      
      return {
        'documento_id': map['documento_id'], // UUID del documento
        'urls': urls,
        'total_segmentos': audios.length,
        'audios_generados': conAudio,
      };
    } catch (e) {
      print('   ❌ Excepción: $e');
      rethrow;
    }
  }

  /// Quick-start: Genera el primer audio de forma síncrona y lo devuelve inmediatamente.
  /// Mientras tanto, genera los siguientes 3 audios en background.
  /// Retorna un mapa con la URL del primer audio y el documento_id.
  Future<Map<String, dynamic>> quickStartBook(int libroId, String voiceId, {int nextCount = 3}) async {
    print('🚀 [TTS] quickStartBook - Libro: $libroId, voiceId: $voiceId, nextCount=$nextCount');
    
    final baseUrl = await _baseUrl;
    final uri = Uri.parse('$baseUrl/tts/libro/$libroId/quick-start');
    final body = {'voiceId': voiceId, 'nextCount': nextCount};
    
    print('   URL: $uri');
    print('   Esperando primer audio...');
    
    try {
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30)); // Timeout generoso para generación
      
      print('   Status: ${resp.statusCode}');
      
      if (resp.statusCode != 200) {
        print('   ❌ Error: ${resp.body}');
        throw Exception('Error en quick-start: ${resp.statusCode} ${resp.body}');
      }
      
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      final firstAudioUrl = map['first_audio_url'] as String;
      final documentoId = map['documento_id'] as String?;
      
      print('   ✅ Primer audio listo: $firstAudioUrl');
      print('   📄 Documento ID: $documentoId');
      
      return {
        'first_audio_url': firstAudioUrl,
        'documento_id': documentoId,
        'next_count': map['next_count'],
      };
    } catch (e) {
      print('   ❌ Excepción: $e');
      rethrow;
    }
  }

  /// Solicita una playlist inicial de segmentos (`POST /tts/playlist`).
  /// El backend devolverá hasta 5 segmentos y encolará más en background.
  Future<Playlist> getPlaylist({
    required String documentId,
    required String voiceId,
    int? fromOffsetChar,
  }) async {
    final baseUrl = await _baseUrl;
    final uri = Uri.parse('$baseUrl/tts/playlist');
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
    
    // Construir items con await para buildSegmentAudioUri
    final items = <PlaylistItem>[];
    for (var e in itemsRaw) {
      final item = e as Map<String, dynamic>;
      final segId = item['segment_id'] as int;
      final urlString = item['url'] as String?;
      final uri = urlString != null
          ? Uri.parse(urlString)
          : await buildSegmentAudioUri(documentId, voiceId, segId);
      items.add(PlaylistItem(
        segmentId: segId,
        url: uri,
        durationMs: item['duration_ms'] as int?,
      ));
    }

    return Playlist(
      documentId: documentId,
      voiceId: voiceId,
      items: items,
      startSegmentId: map['start_segment_id'] as int? ?? (items.isNotEmpty ? items.first.segmentId : 0),
      startIntraMs: map['start_intra_ms'] as int? ?? 0,
    );
  }

  /// Construye la URI para pedir el audio de un segmento. El backend hará redirect al MP3.
  /// NOTA: Este método debe ser async para resolver baseUrl
  Future<Uri> buildSegmentAudioUri(String documentId, String voiceId, int segmentId) async {
    // Enviamos doc y libro por compatibilidad; el backend resolverá
    final baseUrl = await _baseUrl;
    final params = 'doc=$documentId&libro=$documentId&voice=$voiceId&segment=$segmentId';
    return Uri.parse('$baseUrl/tts/segment?$params');
  }

  /// Prefetch de los próximos segmentos para reducir latencia.
  /// Dispara peticiones GET en background que cachearán en HTTP.
  /// OPTIMIZADO: Prefetch de un solo audio a la vez para no saturar
  Future<void> prefetchNext(List<PlaylistItem> playlist, int currentIndex) async {
    final idx = currentIndex + 1;
    if (idx >= playlist.length) return;
    
    final uri = playlist[idx].url;
    try {
      // GET en background sin await (fire and forget)
      http.get(uri).timeout(
        const Duration(seconds: 8),
        onTimeout: () => http.Response('timeout', 408),
      ).then((resp) {
        if (resp.statusCode == 200) {
          print('✅ Precargado audio ${idx + 1}');
        }
      }).catchError((e) {
        // Silencioso: el prefetch no debe romper la reproducción
        print('⚠️ Prefetch falló para audio ${idx + 1}: $e');
      });
    } catch (e) {
      // Silencioso
    }
  }

  // Persistencia local de progreso (clave por doc y voz)
  Future<void> saveProgress(PlayProgress progress) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _progressKey(progress.documentId, progress.voiceId);
    await prefs.setString(key, jsonEncode(progress.toJson()));
    // Intentar also sync con backend (no bloquear la UI si falla)
    try {
      final baseUrl = await _baseUrl;
      final uri = Uri.parse('$baseUrl/progress');
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

  /// Solicita al backend que genere más audios para un libro en background.
  /// No lanza excepción si falla; retorna mapa de respuesta si OK.
  Future<Map<String, dynamic>?> generateMore(int libroId, String voiceId, {int count = 5}) async {
    final baseUrl = await _baseUrl;
    final uri = Uri.parse('$baseUrl/tts/libro/$libroId/audios?voiceId=$voiceId&autoGenerate=$count');
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return null;
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
