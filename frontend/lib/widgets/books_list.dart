import 'package:flutter/material.dart';
import '../models/book.dart';
import 'book_card.dart';

/// Lista de tarjetas de libros.
class BooksList extends StatelessWidget {
  final List<Book> books;
  const BooksList({super.key, required this.books});

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return const Center(child: Text('No hay libros disponibles.'));
    }
    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (context, index) => BookCard(book: books[index]),
    );
  }
}
