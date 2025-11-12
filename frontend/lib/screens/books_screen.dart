import 'package:flutter/material.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import 'search_screen.dart';
import '../widgets/loom_banner.dart';
import '../auth/google_auth_service.dart';
import '../models/book.dart';
import '../services/api_service.dart';
import '../widgets/book_grid_card.dart';
import 'upload_book_screen.dart';

/// Pantalla que muestra la lista de libros.

class BooksScreen extends StatefulWidget {
  final int initialTab;
  const BooksScreen({super.key, this.initialTab = 1});

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  late int _selectedIndex;
  Future<List<Book>>? _booksFuture;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab;
    _loadUserLibrary();
  }

  Future<void> _loadUserLibrary() async {
    try {
      // Obtener el userId del GoogleAuthService
      final user = GoogleAuthService().currentUser;
      if (user == null) {
        print('⚠️ No hay usuario logueado');
        return;
      }
      
      // Obtener id_usuario del backend
      final userId = await ApiService.ensureUser(
        firebaseUid: user.uid,
        email: user.email,
        displayName: user.displayName ?? 'Usuario',
      );
      
      _userId = userId;
      
      // Cargar biblioteca personal del usuario
      setState(() {
        _booksFuture = ApiService.fetchUserLibrary(_userId!);
      });
    } catch (e) {
      print('❌ Error al cargar biblioteca: $e');
    }
  }

  void _refreshBooks() {
    _loadUserLibrary();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    FloatingActionButton? fab;
    
    if (_selectedIndex == 0) {
      body = const SearchScreen();
    } else if (_selectedIndex == 1) {
      // Home - Biblioteca del usuario
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LoomBanner(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              'Mi Biblioteca',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ),
          Expanded(
            child: _booksFuture == null
                ? const Center(child: CircularProgressIndicator())
                : FutureBuilder<List<Book>>(
                    future: _booksFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      } else if (snapshot.hasData) {
                        final books = snapshot.data!;
                        if (books.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.auto_stories,
                                  size: 80,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  '¡Embárcate en una\naventura de lectura!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Explora libros en la pestaña de búsqueda',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.75,
                          ),
                          itemCount: books.length,
                          itemBuilder: (context, index) => BookGridCard(book: books[index]),
                        );
                      }
                      return const Center(child: Text('Sin datos'));
                    },
                  ),
          ),
        ],
      );
      
      // Botón + solo en Home
      fab = FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const UploadBookScreen(),
            ),
          );
          if (result == true) {
            _refreshBooks();
          }
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.black),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LoomBanner(),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Perfil', style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () async {
                      await GoogleAuthService().signOut();
                      if (!mounted) return;
                      // Simplemente salir de la app o volver al inicio
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      'Cerrar sesión',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: null,
        toolbarHeight: 0,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: body,
      floatingActionButton: fab,
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
          // Si el usuario entra a la pestaña de Biblioteca, recargar siempre
          if (index == 1) {
            _loadUserLibrary();
          }
        },
      ),
    );
  }
}
