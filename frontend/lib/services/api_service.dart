import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/book.dart';

/// Servicio para consumir la API de libros.
class ApiService {
  static String? _cachedBaseUrl;
  static DateTime? _cacheTime;
  static const _cacheDuration = Duration(minutes: 5); // Expirar cache después de 5 minutos

  /// Resetea el cache de URL para forzar re-detección
  static void resetCache() {
    print('🔄 Reseteando cache de URL...');
    _cachedBaseUrl = null;
    _cacheTime = null;
  }

  // Obtiene base URL - TEMPORAL: URL FIJA PARA DEBUGGING
  static Future<String> resolveBaseUrl() async {
    // TEMP: Forzar IP local conocida para dispositivo físico.
    // Cambia esta IP si tu PC tiene otra (mírala en la consola del backend).
    const forced = 'http://172.23.32.1:3000';
    print('🌐 Usando baseUrl forzada: $forced');
    return forced;
  }


  /// Obtiene la lista de libros desde el backend.
  static Future<List<Book>> fetchBooks() async {
    try {
      final baseUrl = await resolveBaseUrl();
      print('📚 Cargando libros desde: $baseUrl/disponibles');
      final response = await http.get(
        Uri.parse('$baseUrl/disponibles')
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Timeout: El servidor no responde');
        },
      );
      print('   Status code: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        print('   Libros recibidos: ${data.length}');
        return data.map((json) => Book.fromJson(json)).toList();
      } else {
        print('❌ Error al cargar libros: ${response.statusCode}');
        print('   Body: ${response.body}');
        // Devolver lista vacía para que la UI no se quede congelada
        return [];
      }
    } catch (e) {
      print('❌ Excepción en fetchBooks: $e');
      // Devolver lista vacía en errores para finalizar future
      return [];
    }
  }

  /// Obtiene la biblioteca personal del usuario
  static Future<List<Book>> fetchUserLibrary(String userId) async {
    try {
      final baseUrl = await resolveBaseUrl();
      print('📚 Solicitando biblioteca para usuario: $userId');
      print('🌐 URL: $baseUrl/biblioteca/$userId');
      
      final response = await http.get(
        Uri.parse('$baseUrl/biblioteca/$userId'),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Timeout al conectar con el servidor');
        },
      );
      
      print('📡 Status code: ${response.statusCode}');
      print('📦 Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        print('✅ Libros en biblioteca: ${data.length}');
        if (data.isNotEmpty) {
          print('📖 Primer libro: ${data[0]}');
        }
        return data.map((json) => Book.fromJson(json)).toList();
      } else {
        print('❌ Error del servidor: ${response.statusCode}');
        print('Body: ${response.body}');
        // NO retornar lista vacía, lanzar excepción para que se vea el error
        throw Exception(
          'Error al cargar biblioteca. Status: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Excepción en fetchUserLibrary: $e');
      // LANZAR el error en lugar de retornar lista vacía
      rethrow;
    }
  }

  /// Agrega un libro a la biblioteca del usuario
  static Future<String> addBookToLibrary(String userId, int bookId) async {
    final baseUrl = await resolveBaseUrl();
    final response = await http.post(
      Uri.parse('$baseUrl/biblioteca/agregar'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'userId': userId, 'bookId': bookId}),
    );
    print('Agregar a biblioteca: ${response.statusCode}');
    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['message'] ?? 'Libro agregado';
    } else {
      throw Exception('Error al agregar libro: ${response.statusCode}');
    }
  }

  /// Remueve un libro de la biblioteca del usuario
  static Future<void> removeBookFromLibrary(String userId, int bookId) async {
    final baseUrl = await resolveBaseUrl();
    final request = http.Request('DELETE', Uri.parse('$baseUrl/biblioteca/remover'));
    request.headers['Content-Type'] = 'application/json';
    request.body = json.encode({'userId': userId, 'bookId': bookId});
    
    final response = await request.send();
    if (response.statusCode != 200) {
      throw Exception('Error al remover libro: ${response.statusCode}');
    }
  }

  /// Asegura usuario en backend y devuelve id_usuario (string)
  static Future<String> ensureUser({
    String? firebaseUid,
    String? email,
    String? displayName,
    String? photoUrl,
  }) async {
    try {
      final baseUrl = await resolveBaseUrl();
      
      print('📤 Sincronizando usuario con backend...');
      print('   URL: $baseUrl/usuarios/ensure');
      print('   Firebase UID: $firebaseUid');
      print('   Email: $email');
      print('   Nombre: $displayName');
      
      final response = await http.post(
        Uri.parse('$baseUrl/usuarios/ensure'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'firebaseUid': firebaseUid,
          'email': email,
          'displayName': displayName,
          'photoUrl': photoUrl,
        }),
      ).timeout(
        const Duration(seconds: 15), // Timeout más largo para debugging
        onTimeout: () {
          print('❌ Timeout después de 15 segundos');
          throw Exception('Timeout al sincronizar con servidor. Verifica que el backend esté corriendo.');
        },
      );

      print('   Status code: ${response.statusCode}');
      print('   Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        final id = data['id_usuario'];
        if (id == null) throw Exception('Respuesta inválida: falta id_usuario');
        print('✅ Usuario sincronizado con ID: $id');
        return id.toString();
      } else if (response.statusCode == 409) {
        // Nombre de usuario ya existe
        final data = json.decode(response.body);
        throw Exception(data['error'] ?? 'Nombre de usuario ya existe');
      } else {
        throw Exception('Error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('❌ Error en ensureUser: $e');
      rethrow;
    }
  }

  /// Prueba simple de POST
  static Future<void> testPost() async {
    try {
      final baseUrl = await resolveBaseUrl();
      print('=== PROBANDO POST SIMPLE ===');
      print('URL: $baseUrl/test');
      
      final response = await http.post(
        Uri.parse('$baseUrl/test'),
        headers: {'Content-Type': 'application/json'},
        body: '{"test": "data"}',
      ).timeout(const Duration(seconds: 10));
      
      print('Status: ${response.statusCode}');
      print('Response: ${response.body}');
    } catch (e) {
      print('❌ Error en testPost: $e');
      rethrow;
    }
  }

  /// Sube un nuevo libro con archivo PDF y portada opcional
  static Future<void> uploadBook({
    required String titulo,
    String? descripcion,
    required List<String> categoriasIds,
    required File pdfFile,
    File? coverFile,
    String? userId,
  }) async {
    try {
      print('=== INICIANDO UPLOAD ===');
      final baseUrl = await resolveBaseUrl();
      print('URL: $baseUrl/libros');
      print('Título: $titulo');
      
  var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/libros'));
      
      // Agregar campos de texto
      request.fields['titulo'] = titulo;
      if (descripcion != null && descripcion.isNotEmpty) {
        request.fields['descripcion'] = descripcion;
      }
      // Enviar categorías como JSON array de IDs
      request.fields['categoria'] = json.encode(categoriasIds);
      if (userId != null && userId.isNotEmpty) {
        request.fields['userId'] = userId; // backend acepta userId
      }

      // Agregar archivo PDF
      var pdfBytes = await pdfFile.readAsBytes();
      print('Tamaño del PDF: ${pdfBytes.length} bytes (${(pdfBytes.length / 1024 / 1024).toStringAsFixed(2)} MB)');
      
      var multipartFile = http.MultipartFile.fromBytes(
        'pdf',
        pdfBytes,
        filename: pdfFile.path.split('/').last,
        contentType: MediaType('application', 'pdf'),
      );
      request.files.add(multipartFile);

      // Agregar portada si existe
      if (coverFile != null) {
        var coverBytes = await coverFile.readAsBytes();
        print('Tamaño de la portada: ${coverBytes.length} bytes');
        
        var coverMultipartFile = http.MultipartFile.fromBytes(
          'portada',
          coverBytes,
          filename: coverFile.path.split('/').last,
          contentType: MediaType('image', 'jpeg'), // Asume JPEG, puedes mejorar esto
        );
        request.files.add(coverMultipartFile);
      }

      print('Enviando request...');
      
      // Enviar request con timeout de 2 minutos
      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Timeout: El servidor tardó demasiado en responder');
        },
      );
      
      print('Respuesta recibida, procesando...');
      var response = await http.Response.fromStream(streamedResponse);

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 201) {
        print('✅ Libro subido exitosamente');
      } else {
        throw Exception('Error del servidor: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error en uploadBook: $e');
      rethrow;
    }
  }

  /// Elimina (soft-delete) un libro si el usuario es el autor/uploader
  static Future<void> deleteBook({required String userId, required int bookId}) async {
    final baseUrl = await resolveBaseUrl();
    final uri = Uri.parse('$baseUrl/libros/$bookId');
    final response = await http.delete(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'userId': userId}),
    );
    if (response.statusCode != 200) {
      throw Exception('No se pudo eliminar el libro (${response.statusCode}): ${response.body}');
    }
  }

  /// Edita título/descripcion de un libro (solo autor/uploader)
  static Future<void> updateBook({
    required String userId,
    required int bookId,
    String? titulo,
    String? descripcion,
  }) async {
    final baseUrl = await resolveBaseUrl();
    final uri = Uri.parse('$baseUrl/libros/$bookId');
    final response = await http.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'userId': userId, 'titulo': titulo, 'descripcion': descripcion}),
    );
    if (response.statusCode != 200) {
      throw Exception('No se pudo actualizar el libro (${response.statusCode}): ${response.body}');
    }
  }

  /// Obtener las categorías disponibles desde el backend
  static Future<List<Category>> fetchCategories() async {
    try {
      final baseUrl = await resolveBaseUrl();
      print('📂 Cargando categorías desde: $baseUrl/categorias');
      final response = await http.get(Uri.parse('$baseUrl/categorias'));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        print('   Categorías recibidas: ${data.length}');
        return data.map((item) => Category.fromJson(item)).toList();
      } else {
        print('⚠️ Error al cargar categorías, usando fallback');
        return [Category(id: '1', nombre: 'General')];
      }
    } catch (e) {
      print('❌ Excepción en fetchCategories: $e');
      return [Category(id: '1', nombre: 'General')]; // Fallback seguro
    }
  }
}