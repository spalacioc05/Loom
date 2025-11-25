import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/books_screen.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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
    if (mounted) {
      setState(() => _showSplash = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Loom',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF00D9FF),
          secondary: const Color(0xFF00D9FF),
          surface: const Color(0xFF1E1E1E),
          background: const Color(0xFF121212),
          onPrimary: Colors.black,
          onSecondary: Colors.white,
          onSurface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        useMaterial3: true,
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 32.0,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
          displayMedium: TextStyle(
            fontSize: 28.0,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          titleLarge: TextStyle(
            fontSize: 22.0,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          titleMedium: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          bodyLarge: TextStyle(
            fontSize: 16.0,
            color: Colors.white,
            height: 1.5,
          ),
          bodyMedium: TextStyle(
            fontSize: 14.0,
            color: Color(0xFFB0B0B0),
            height: 1.4,
          ),
          labelLarge: TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1E1E1E),
          selectedItemColor: Color(0xFF00D9FF),
          unselectedItemColor: Color(0xFF666666),
          showSelectedLabels: false,
          showUnselectedLabels: false,
          type: BottomNavigationBarType.fixed,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
        ),
      ),
      home: _showSplash
          ? SplashScreen(onContinue: _continueToApp)
          : const BooksScreen(initialTab: 1),
    );
  }
}
