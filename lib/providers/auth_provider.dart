import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/analytics_service.dart';

class AuthProvider extends ChangeNotifier {
  static const _adminEmail = 'selvavishnu.m@gmail.com';

  final _auth = FirebaseAuth.instance;
  // serverClientId (web client type-3) is required for Android to generate
  // a non-null idToken that Firebase Auth can consume via credential().
  final _googleSignIn = GoogleSignIn(
    serverClientId: '888976648050-nk5svn13jeu28aleiis2lj36qbs5ia9f.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
  );

  User? get user => _auth.currentUser;
  bool get isLoggedIn => user != null;
  bool get isAdmin => email == _adminEmail;
  String get displayName => user?.displayName ?? '';
  String get email => user?.email ?? '';
  String? get photoUrl => user?.photoURL;

  AuthProvider() {
    _auth.authStateChanges().listen((_) => notifyListeners());
  }

  Future<bool> signInWithGoogle() async {
    try {
      await AnalyticsService.logGoogleLoginStarted();
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return false;
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.signInWithCredential(credential);
      await AnalyticsService.logGoogleLoginCompleted();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
    notifyListeners();
  }
}
