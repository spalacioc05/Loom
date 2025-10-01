import 'package:flutter/material.dart';
import '../models/book.dart';
import '../services/api_service.dart';
import '../widgets/books_list.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import 'search_screen.dart';
import '../widgets/loom_banner.dart';

/// Pantalla que muestra la lista de libros.
class BooksScreen extends StatefulWidget {
  const BooksScreen({super.key});

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  int _selectedIndex = 1; // Home por defecto

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
        children: const [
          LoomBanner(),
          Expanded(
            child: Center(
              child: Text('Perfil', style: TextStyle(fontSize: 24)),
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
