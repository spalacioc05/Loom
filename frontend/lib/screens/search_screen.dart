import 'package:flutter/material.dart';
import '../models/book.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/category_carousel.dart';
import '../services/api_service.dart';
import '../widgets/loom_banner.dart';
import '../widgets/search_book_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late Future<List<Book>> _booksFuture;
  final List<String> categories = [
    'Romance',
    'Terror',
    'Aventura',
    'Fantasía',
    'Clásicos',
    'Ciencia Ficción',
    'Drama',
    'Infantil',
  ];

  @override
  void initState() {
    super.initState();
    _booksFuture = ApiService.fetchBooks();
  }

  Future<void> _showBookInfoDialog(Book book) async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(book.titulo),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (book.autores.isNotEmpty) ...[
                  const Text('Autor:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(book.autores.map((a) => a.nombre).join(', ')),
                  const SizedBox(height: 8),
                ],
                if (book.descripcion != null && book.descripcion!.isNotEmpty) ...[
                  const Text('Descripción:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(book.descripcion!),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LoomBanner(),
            const SearchBarWidget(),
            CategoryCarousel(categories: categories),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                'Libros recomendados',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FutureBuilder<List<Book>>(
                  future: _booksFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                      } else if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Error al cargar libros: ${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        );
                    } else if (snapshot.hasData) {
                      final books = snapshot.data!;
                      return GridView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.75,
                            ),
                        itemCount: books.length,
                        itemBuilder: (context, index) {
                          return SearchBookCard(
                            book: books[index],
                            onTap: () => _showBookInfoDialog(books[index]),
                          );
                        },
                      );
                    } else {
                      return const Center(child: Text('No hay libros.'));
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
