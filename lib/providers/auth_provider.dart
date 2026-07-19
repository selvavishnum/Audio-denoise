import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/analytics_service.dart';

class AuthProvider extends ChangeNotifier {
  static const _adminEmail = String.fromEnvironment(
    'ADMIN_EMAIL',
    defaultValue: 'selvavishnu.m@gmail.com',
  );
  // Play Store review account — treated as admin so Google's reviewers get
  // every Pro feature unlocked without needing to make a purchase.
  static const _reviewEmail = 'noiseclear.review@gmail.com';

  final _auth = FirebaseAuth.instance;
  // serverClientId (web client type-3) is required for Android to generate
  // a non-null idToken that Firebase Auth can consume via credential().
  final _googleSignIn = GoogleSignIn(
    serverClientId: '888976648050-nk5svn13jeu28aleiis2lj36qbs5ia9f.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
  );

  User? get user => _auth.currentUser;
  bool get isLoggedIn => user != null;
  bool get isAdmin {
    final e = email.toLowerCase().trim();
    return e.isNotEmpty && (e == _adminEmail.toLowerCase() || e == _reviewEmail);
  }
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

  /// Permanently delete the signed-in user's account and associated auth data
  /// from Firebase. Returns null on success, or a human-readable error.
  /// Firebase requires a recent login to delete; if the session is stale we
  /// return a message asking the user to sign in again and retry.
  Future<String?> deleteAccount() async {
    final u = _auth.currentUser;
    if (u == null) return 'You are not signed in.';
    try {
      await u.delete();
      await _googleSignIn.signOut();
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        return 'For security, please sign out and sign in again, then delete '
            'your account.';
      }
      return 'Could not delete account: ${e.message ?? e.code}';
    } catch (e) {
      return 'Could not delete account: $e';
    }
  }
}
