import 'package:flutter/material.dart';
import '../models/book.dart';

/// Tarjeta visual para mostrar la información de un libro.
class BookCard extends StatelessWidget {
  final Book book;
  const BookCard({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: ListTile(
        title: Text(
          book.titulo,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          book.descripcion ?? 'Sin descripción',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.picture_as_pdf),
          onPressed: () {
            // Aquí podrías abrir el PDF usando el archivoUrl
          },
        ),
      ),
    );
  }
}
