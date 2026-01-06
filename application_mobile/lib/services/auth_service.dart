import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  static final _auth = FirebaseAuth.instance;

  static Future<User?> login(String email, String password) async {
    final creds = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );
    return creds.user;
  }

  static Future<void> logout() async => _auth.signOut();
}
