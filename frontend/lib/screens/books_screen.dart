import 'package:flutter/material.dart';
// import '../models/book.dart';
// import '../services/api_service.dart';
// import '../widgets/books_list.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import 'search_screen.dart';
import '../widgets/loom_banner.dart';
import '../auth/google_auth_service.dart';

/// Pantalla que muestra la lista de libros.

class BooksScreen extends StatefulWidget {
  final int initialTab;
  const BooksScreen({super.key, this.initialTab = 1});

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_selectedIndex == 0) {
      body = const SearchScreen();
    } else if (_selectedIndex == 1) {
      body = const Center(child: Text('Home', style: TextStyle(fontSize: 24)));
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sesión cerrada')),
                      );
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
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }
}
