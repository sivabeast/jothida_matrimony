import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../services/firebase/auth_service.dart';
import '../services/firebase/fcm_service.dart';

class AuthRepository {
  final AuthService _auth;
  final FcmService _fcm;

  AuthRepository(this._auth, this._fcm);

  Stream<User?> get authStateChanges => _auth.authStateChanges;
  User? get currentUser => _auth.currentUser;
  String? get currentUserId => _auth.currentUserId;

  Future<void> verifyPhone({
    required String phoneNumber,
    required Function(String) onCodeSent,
    required Function(String) onError,
    required Function(PhoneAuthCredential) onAutoVerified,
  }) =>
      _auth.verifyPhone(
        phoneNumber: phoneNumber,
        onCodeSent: onCodeSent,
        onError: onError,
        onAutoVerified: onAutoVerified,
      );

  Future<UserCredential> signInWithOTP(String verificationId, String otp) =>
      _auth.signInWithOTP(verificationId, otp);

  Future<UserCredential> registerWithEmail(String email, String password) =>
      _auth.registerWithEmail(email, password);

  Future<UserCredential> signInWithEmail(String email, String password) =>
      _auth.signInWithEmail(email, password);

  Future<UserCredential?> signInWithGoogle() => _auth.signInWithGoogle();

  Future<void> sendPasswordReset(String email) => _auth.sendPasswordReset(email);

  Future<void> createUserDocumentAfterAuth(User user, {String? phone}) async {
    await _auth.createUserDocument(user, phone: phone);
    final uid = user.uid;
    final token = await _fcm.getToken();
    if (token != null) await _auth.updateFcmToken(uid, token);
  }

  Future<UserModel?> getUserModel(String uid) => _auth.getUserModel(uid);

  Future<void> signOut() => _auth.signOut();
}
