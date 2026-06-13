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

  /// Human-readable reason the last sign-in failed (shown in the UI).
  String? lastError;

  AuthProvider() {
    _auth.authStateChanges().listen((_) => notifyListeners());
  }

  Future<bool> signInWithGoogle() async {
    lastError = null;
    try {
      await AnalyticsService.logGoogleLoginStarted();
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        lastError = 'Sign-in cancelled';
        return false;
      }
      final googleAuth = await googleUser.authentication;

      // The #1 failure for sideloaded builds: a null idToken means this APK's
      // SHA-1 fingerprint is NOT registered in Firebase for com.noiseclear.app.
      if (googleAuth.idToken == null) {
        lastError =
            'No Google ID token. This build\'s SHA-1 is not registered in '
            'Firebase. Install a RELEASE APK signed with the registered '
            'keystore (debug APKs will not work).';
        notifyListeners();
        return false;
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.signInWithCredential(credential);
      await AnalyticsService.logGoogleLoginCompleted();
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      lastError = 'Firebase: ${e.code} — ${e.message ?? ''}';
      debugPrint('Google Sign-In FirebaseAuthException: $e');
      notifyListeners();
      return false;
    } catch (e) {
      lastError = 'Sign-in error: $e';
      debugPrint('Google Sign-In error: $e');
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
    notifyListeners();
  }
}
