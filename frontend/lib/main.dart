import 'package:flutter/material.dart';
import 'screens/books_screen.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const MyApp());
}

/// App principal que muestra la pantalla de libros.
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _showSplash = true;

  void _continueToApp() {
    setState(() => _showSplash = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Biblioteca',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF00C853),
          secondary: const Color(0xFF2196F3),
          background: const Color(0xFF2B2A26),
          surface: const Color(0xFF36352F),
          onPrimary: Colors.black,
          onSecondary: Colors.white,
          onBackground: Colors.white,
          onSurface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFF2B2A26),
        useMaterial3: true,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 18.0, color: Colors.white),
          bodyMedium: TextStyle(fontSize: 16.0, color: Colors.white70),
          bodySmall: TextStyle(fontSize: 14.0, color: Colors.white60),
          titleLarge: TextStyle(
            fontSize: 22.0,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2B2A26),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF36352F),
          selectedItemColor: Color(0xFF00C853),
          unselectedItemColor: Color(0xFF2196F3),
          showSelectedLabels: false,
          showUnselectedLabels: false,
        ),
      ),
      home: _showSplash
          ? SplashScreen(onContinue: _continueToApp)
          : const BooksScreen(),
    );
  }
}
