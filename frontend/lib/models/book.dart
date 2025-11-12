/// Modelo de libro para mapear la respuesta del backend.
class Book {
  final String id;
  final String titulo;
  final String? descripcion;
  final DateTime? fechaPublicacion;
  final String? portada;
  final String? archivo;
  final int? paginas;
  final int? palabras;
  final List<Author> autores;
  final List<Genre> generos;
  final List<Category> categorias;

  Book({
    required this.id,
    required this.titulo,
    this.descripcion,
    this.fechaPublicacion,
    this.portada,
    this.archivo,
    this.paginas,
    this.palabras,
  this.autores = const [],
  this.generos = const [],
  this.categorias = const [],
  });

  /// Obtiene el id como entero
  int get intId => int.parse(id);

  /// Crea una instancia de Book desde un JSON.
  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: (json['id'] ?? 0).toString(),
      titulo: json['titulo'] ?? 'Sin título',
      descripcion: json['descripcion'],
      fechaPublicacion: json['fecha_publicacion'] != null 
        ? DateTime.parse(json['fecha_publicacion']) 
        : null,
      portada: json['portada'],
      archivo: json['archivo'],
      paginas: json['paginas'],
      palabras: json['palabras'],
      autores: json['autores'] != null 
        ? (json['autores'] as List).map((a) => Author.fromJson(a)).toList()
        : [],
      generos: json['generos'] != null
        ? (json['generos'] as List).map((g) => Genre.fromJson(g)).toList()
        : [],
      categorias: json['categorias'] != null
        ? (json['categorias'] as List).map((c) => Category.fromJson(c)).toList()
        : [],
    );
  }
}

/// Modelo de autor
class Author {
  final String id;
  final String nombre;

  Author({required this.id, required this.nombre});

  factory Author.fromJson(Map<String, dynamic> json) {
    return Author(
      id: (json['id'] ?? 0).toString(),
      nombre: json['nombre'] ?? 'Desconocido',
    );
  }
}

/// Modelo de género
class Genre {
  final String id;
  final String nombre;

  Genre({required this.id, required this.nombre});

  factory Genre.fromJson(Map<String, dynamic> json) {
    return Genre(
      id: (json['id'] ?? 0).toString(),
      nombre: json['nombre'] ?? 'Sin género',
    );
  }
}

/// Modelo de categoría
class Category {
  final String id;
  final String nombre;
  final String? descripcion;

  Category({required this.id, required this.nombre, this.descripcion});

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: (json['id'] ?? 0).toString(),
      nombre: json['nombre'] ?? 'General',
      descripcion: json['descripcion'],
    );
  }
}
