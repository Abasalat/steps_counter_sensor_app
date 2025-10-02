import 'package:firebase_auth/firebase_auth.dart';
import 'package:steps_counter_sensor_app/data/models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Stream for auth state changes
  Stream<UserModel?> get authStateChanges {
    return _auth.authStateChanges().map((user) {
      if (user != null) {
        return UserModel(uid: user.uid, email: user.email ?? '');
      }
      return null;
    });
  }

  // Sign up with email/password
  Future<UserModel?> signUp(String email, String password) async {
    try {
      UserCredential credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return UserModel(
        uid: credential.user!.uid,
        email: credential.user!.email ?? '',
      );
    } catch (e) {
      print('Signup error: $e');
      return null;
    }
  }

  // Login with email/password
  Future<UserModel?> login(String email, String password) async {
    try {
      UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return UserModel(
        uid: credential.user!.uid,
        email: credential.user!.email ?? '',
      );
    } catch (e) {
      print('Login error: $e');
      return null;
    }
  }

  // Logout
  Future<void> logout() async {
    await _auth.signOut();
  }

  // Get current user
  UserModel? get currentUser {
    final user = _auth.currentUser;
    if (user != null) {
      return UserModel(uid: user.uid, email: user.email ?? '');
    }
    return null;
  }
}
