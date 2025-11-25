import 'package:flutter/material.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import 'search_screen.dart';
import '../widgets/loom_banner.dart';
import '../auth/google_auth_service.dart';
import '../models/book.dart';
import '../services/api_service.dart';
import '../widgets/book_grid_card.dart';
import 'upload_book_screen.dart';
import '../widgets/category_carousel.dart';

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
  String? _userName;
  String? _userEmail;
  int _libraryFilter = 0; // 0 todos, 1 subidos por mi
  int _totalBooks = 0;
  int _totalListenHours = 0;
  int _streakDays = 7;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab;
    // Cargar biblioteca del usuario al iniciar SOLO si empieza en pestaña Biblioteca
    if (_selectedIndex == 1) {
      _loadUserLibrary();
    }
  }

  Future<void> _loadUserLibrary() async {
    print('🔄 [_loadUserLibrary] Iniciando carga de biblioteca...');
    try {
      // Obtener el userId del GoogleAuthService
      final user = GoogleAuthService().currentUser;
      if (user == null) {
        print('⚠️ No hay usuario logueado');
        return;
      }
      
      print('👤 Usuario Firebase: ${user.email}');
      
      // Obtener id_usuario del backend
      final userId = await ApiService.ensureUser(
        firebaseUid: user.uid,
        email: user.email,
        displayName: user.displayName ?? 'Usuario',
      );
      
      _userId = userId;
      print('✅ Usuario backend ID: $_userId');
      
      // Guardar datos del usuario
      setState(() {
        _userName = user.displayName ?? 'Usuario';
        _userEmail = user.email ?? '';
      });
      
      // Cargar biblioteca personal del usuario
      print('📚 Solicitando biblioteca al backend...');
      setState(() {
        _booksFuture = ApiService.fetchUserLibrary(_userId!).then((books) {
          print('✅ Biblioteca recibida: ${books.length} libros');
          setState(() {
            _totalBooks = books.length;
            final totalMinutes = books.fold<double>(0.0, (sum, book) => sum + (book.progreso ?? 0.0));
            _totalListenHours = totalMinutes.toInt() ~/ 60;
          });
          return books;
        });
      });
    } catch (e) {
      print('❌ Error al cargar biblioteca: $e');
    }
  }

  void _refreshBooks() {
    // Ambos filtros trabajan sobre la biblioteca del usuario
    _loadUserLibrary();
  }

  Widget _buildProfileScreen() {
    final initials = (_userName ?? 'U').split(' ').map((n) => n[0]).take(2).join().toUpperCase();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Perfil',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () {
                    // TODO: Configuración
                  },
                ),
              ],
            ),
          ),
          
          // User Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00D9FF), Color(0xFF0099CC)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // User Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _userName ?? 'Usuario',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _userEmail ?? '',
                        style: Theme.of(context).textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Stats Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    _totalBooks.toString(),
                    'Libros',
                    context,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    '${_totalListenHours}h',
                    'Escuchadas',
                    context,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    '$_streakDays',
                    'Días seguidos',
                    context,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Logout Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ElevatedButton(
              onPressed: () async {
                await GoogleAuthService().signOut();
                if (!mounted) return;
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout),
                  SizedBox(width: 8),
                  Text(
                    'Cerrar sesión',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildStatCard(String value, String label, BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00D9FF),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
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
          // Barra de filtros tipo categorías
          CategoryCarousel(
            categories: const ['Todos', 'Mis subidos'],
            selectedIndex: _libraryFilter,
            onCategorySelected: (i) {
              setState(() => _libraryFilter = i);
              // No recargar, solo cambiar el filtro visual
            },
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
                        print('📊 FutureBuilder hasData: ${books.length} libros');
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
                        // Aplicar filtro según selección
                        List<Book> filtered = books;
                        if (_libraryFilter == 1 && _userId != null) {
                          // "Mis subidos" - filtrar solo los que el usuario subió
                          print('🔍 Filtrando "Mis subidos": _userId = $_userId');
                          filtered = books.where((b) => b.uploaderId == _userId).toList();
                          print('✅ Libros subidos por mí: ${filtered.length}');
                        } else {
                          // "Todos" - mostrar todos los libros de la biblioteca
                          print('📚 Mostrando todos los libros de la biblioteca: ${books.length}');
                        }
                        
                        // Si no hay resultados después del filtro, mostrar mensaje
                        if (filtered.isEmpty) {
                          String mensaje = 'No hay libros en esta categoría';
                          if (_libraryFilter == 1) {
                            mensaje = 'No has subido ningún libro aún';
                          }
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.library_books_outlined,
                                  size: 80,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  mensaje,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
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
                          itemCount: filtered.length,
                          itemBuilder: (context, index) => BookGridCard(
                            book: filtered[index],
                            onRemoved: _refreshBooks,
                            currentUserId: _userId,
                          ),
                        );
                      }
                      print('⚠️ FutureBuilder sin datos - snapshot.hasError: ${snapshot.hasError}');
                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, size: 64, color: Colors.red),
                              const SizedBox(height: 16),
                              Text('Error: ${snapshot.error}'),
                            ],
                          ),
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
      body = _buildProfileScreen();
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
      // Quitamos ToggleButtons en footer; ahora se muestra CategoryCarousel arriba
      persistentFooterButtons: null,
    );
  }
}
