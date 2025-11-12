import 'package:flutter/material.dart';
import '../models/book.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/category_carousel.dart';
import '../services/api_service.dart';
import '../widgets/loom_banner.dart';
import '../widgets/search_book_card.dart';
import '../auth/google_auth_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late Future<List<Book>> _booksFuture;
  String? _userId;
  int _selectedCategoryIndex = 0;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();
  // Categorías base (se muestran aunque la BD esté vacía o sin categorías)
  final List<String> _baseCategories = const [
    'General',
    'Romance',
    'Terror',
    'Aventura',
    'Fantasía',
    'Clásicos',
    'Ciencia Ficción',
    'Drama',
    'Infantil'
  ];
  List<String> categories = [];

  @override
  void initState() {
    super.initState();
  categories = List<String>.from(_baseCategories);
  _booksFuture = ApiService.fetchBooks();
    _loadUserId();
    _booksFuture.then((list) {
      // Derivar categorías dinámicas desde la relación many-to-many
      final dynamicCats = list
        .expand((b) => b.categorias.map((c) => (c.nombre).trim()))
        .where((name) => name.isNotEmpty)
        .toSet();
      if (dynamicCats.isNotEmpty) {
        final merged = <String>{..._baseCategories, ...dynamicCats}.toList()..sort((a,b){
          if (a == 'General') return -1;
          if (b == 'General') return 1;
          return a.compareTo(b);
        });
        setState(() {
          categories = merged;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserId() async {
    try {
      final user = GoogleAuthService().currentUser;
      if (user != null) {
        final userId = await ApiService.ensureUser(
          firebaseUid: user.uid,
          email: user.email,
          displayName: user.displayName ?? 'Usuario',
        );
        setState(() {
          _userId = userId;
        });
      }
    } catch (e) {
      print('❌ Error al cargar userId: $e');
    }
  }

  Future<void> _showAddToLibraryDialog(Book book) async {
    if (_userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: No se pudo obtener tu usuario')),
      );
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('¿Quieres leer este libro?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.titulo,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              if (book.autores.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  book.autores.map((a) => a.nombre).join(', '),
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.black,
              ),
              child: const Text('Aceptar'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      try {
        // Mostrar loading
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Agregando a tu biblioteca...')),
        );

        final message = await ApiService.addBookToLibrary(_userId!, book.intId);
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        // Opcional: Navegar a la biblioteca (BooksScreen) y seleccionar la pestaña 1
        // Esto asume que BooksScreen escucha el índice y recarga la biblioteca
        // Si la navegación actual no permite esto, puede omitirse.
        // Navigator.of(context).pushReplacement(
        //   MaterialPageRoute(builder: (_) => const BooksScreen(initialTab: 1)),
        // );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
            SearchBarWidget(
              controller: _searchController,
              onChanged: (text) {
                setState(() => _query = text);
              },
              onClear: () {
                _searchController.clear();
                setState(() => _query = '');
                // Notificar a onChanged manualmente si hace falta
              },
            ),
            CategoryCarousel(
              categories: categories,
              onCategorySelected: (idx) {
                setState(() => _selectedCategoryIndex = idx);
              },
              selectedIndex: _selectedCategoryIndex,
            ),
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
                      // Filtrar por categoría seleccionada (si no es 'General')
                      final selectedCat = (_selectedCategoryIndex >= 0 && _selectedCategoryIndex < categories.length)
                        ? categories[_selectedCategoryIndex]
                        : 'General';
                      bool matchesCategory(Book b) {
                        if (selectedCat == 'General') return true;
                        return b.categorias.any((c) => c.nombre.toLowerCase() == selectedCat.toLowerCase());
                      }
                      bool matchesQuery(Book b) {
                        final q = _query.trim().toLowerCase();
                        if (q.isEmpty) return true;
                        if (b.titulo.toLowerCase().contains(q)) return true;
                        if (b.autores.any((a) => a.nombre.toLowerCase().contains(q))) return true;
                        if (b.categorias.any((c) => c.nombre.toLowerCase().contains(q))) return true;
                        return false;
                      }
                      final displayed = books.where((b) => matchesCategory(b) && matchesQuery(b)).toList();
                      if (displayed.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.search_off, size: 64, color: Colors.white70),
                                const SizedBox(height: 12),
                                Text(
                                  'No se encontraron resultados para "${_query}"',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 16, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
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
                        itemCount: displayed.length,
                        itemBuilder: (context, index) {
                          return SearchBookCard(
                            book: displayed[index],
                            onTap: () => _showAddToLibraryDialog(displayed[index]),
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
