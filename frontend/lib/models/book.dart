/// Modelo de libro para mapear la respuesta del backend.
class Book {
  final String id;
  final String titulo;
  final String descripcion;
  final DateTime fechaPublicacion;
  final String? portada;
  final String archivoUrl;

  Book({
    required this.id,
    required this.titulo,
    required this.descripcion,
    required this.fechaPublicacion,
    this.portada,
    required this.archivoUrl,
  });

  /// Crea una instancia de Book desde un JSON.
  factory Book.fromJson(Map<String, dynamic> json) {
    // Decodifica el campo archivo (Buffer) a String URL
    String archivoUrl = '';
    if (json['archivo'] != null && json['archivo']['data'] != null) {
      archivoUrl = String.fromCharCodes(
        List<int>.from(json['archivo']['data']),
      );
    }
    return Book(
      id: json['id'].toString(),
      titulo: json['titulo'],
      descripcion: json['descripcion'],
      fechaPublicacion: DateTime.parse(json['fecha_publicacion']),
      portada: json['portada'],
      archivoUrl: archivoUrl,
    );
  }
}
