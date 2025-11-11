import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class GoogleAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  /// Login simple: Firebase + guardar en BD
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;
      
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      
      final cred = await _auth.signInWithCredential(credential);

      // Guardar en BD en background (no bloquear si falla)
      _saveUserInDatabase(cred.user);

      return cred;
    } catch (e) {
      print('❌ Error en login: $e');
      rethrow;
    }
  }

  /// Guarda usuario en BD (sin bloquear el login si falla)
  Future<void> _saveUserInDatabase(User? user) async {
    if (user == null) return;
    
    try {
      print('💾 Guardando usuario en BD...');
      final idUsuario = await ApiService.ensureUser(
        firebaseUid: user.uid,
        email: user.email,
        displayName: user.displayName,
        photoUrl: user.photoURL,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print('❌ Timeout después de 15 segundos');
          throw Exception('Timeout al sincronizar con servidor. Verifica que el backend esté corriendo.');
        },
      );
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('backend_user_id', idUsuario);
      print('✅ Usuario guardado en BD: $idUsuario');
    } catch (e) {
      print('⚠️ No se pudo guardar en BD (modo offline): $e');
      // NO lanzar error - permitir que la app funcione sin backend
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('backend_user_id');
  }

  User? get currentUser => _auth.currentUser;

  Future<String?> getBackendUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('backend_user_id');
  }

  /// Verifica si hay una sesión activa de Firebase
  bool get isSignedIn => _auth.currentUser != null;
  
  /// Stream de cambios de autenticación
  Stream<User?> get authStateChanges => _auth.authStateChanges();
}
