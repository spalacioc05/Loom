import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/book.dart';

/// Servicio para consumir la API de libros.
class ApiService {
  static const String baseUrl = 'http://10.0.2.2:3000/disponibles';

  /// Obtiene la lista de libros desde el backend.
  static Future<List<Book>> fetchBooks() async {
    final response = await http.get(Uri.parse(baseUrl));
    print('Petición a: ' + baseUrl);
    print('Status code: ' + response.statusCode.toString());
    print('Body: ' + response.body);
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Book.fromJson(json)).toList();
    } else {
      throw Exception(
        'Error al cargar los libros. Status: \\${response.statusCode}, Body: \\${response.body}',
      );
    }
  }
}
