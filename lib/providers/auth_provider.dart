import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import 'service_providers.dart';

// Raw Firebase auth stream
final firebaseAuthStreamProvider = StreamProvider<User?>((ref) =>
    ref.watch(authRepositoryProvider).authStateChanges);

// Current UserModel (loaded after auth).
//
// Deliberately NOT autoDispose. Two things read it without holding a listener:
// the GoRouter `redirect` callback (`ref.read`) and the post-login routing
// (`await ref.read(currentUserProvider.future)`). With autoDispose the element
// is torn down as soon as that read returns, so the redirect saw a *fresh*
// `AsyncLoading` on every single call — its role/onboarding routing never ran —
// and awaiting `.future` raced against disposal. Keeping it alive makes both
// read the real, cached state. `signOut()` and the role-change paths already
// call `ref.invalidate(currentUserProvider)` explicitly, so nothing goes stale.
final currentUserProvider = FutureProvider<UserModel?>((ref) async {
  final authAsync = ref.watch(firebaseAuthStreamProvider);
  final user = authAsync.valueOrNull;
  if (user == null) return null;
  return ref.watch(authRepositoryProvider).getUserModel(user.uid);
});

// Auth state notifier
class AuthNotifier extends AsyncNotifier<UserModel?> {
  @override
  Future<UserModel?> build() async {
    final repo = ref.watch(authRepositoryProvider);
    final user = repo.currentUser;
    if (user == null) return null;
    return repo.getUserModel(user.uid);
  }

  Future<void> signInWithOTP(String verificationId, String otp) async {
    debugPrint('[AuthNotifier] signInWithOTP: state -> loading');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      final cred = await repo.signInWithOTP(verificationId, otp);
      return repo.createUserDocumentAfterAuth(
          cred.user!, phone: cred.user!.phoneNumber, loginProvider: 'phone');
    });
    state.when(
      data: (user) => debugPrint(
          '[AuthNotifier] signInWithOTP: state -> data (user=${user?.uid}, '
          'isProfileComplete=${user?.isProfileComplete})'),
      error: (e, st) =>
          debugPrint('[AuthNotifier] signInWithOTP: state -> error: $e'),
      loading: () => debugPrint('[AuthNotifier] signInWithOTP: still loading?!'),
    );
  }

  Future<void> registerWithEmail(String email, String password) async {
    debugPrint('[AuthNotifier] registerWithEmail: state -> loading');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      final cred = await repo.registerWithEmail(email, password);
      return repo.createUserDocumentAfterAuth(cred.user!,
          loginProvider: 'password');
    });
    state.when(
      data: (user) => debugPrint(
          '[AuthNotifier] registerWithEmail: state -> data (user=${user?.uid})'),
      error: (e, st) =>
          debugPrint('[AuthNotifier] registerWithEmail: state -> error: $e'),
      loading: () =>
          debugPrint('[AuthNotifier] registerWithEmail: still loading?!'),
    );
  }

  /// User signup collecting the essential details required by the spec
  /// (name, mobile, gender, DOB, location).
  Future<void> registerUser({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String gender,
    required DateTime dateOfBirth,
    required String location,
  }) async {
    debugPrint('[AuthNotifier] registerUser: state -> loading ($email)');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref.read(authRepositoryProvider).registerUserWithDetails(
            email: email,
            password: password,
            name: name,
            phone: phone,
            gender: gender,
            dateOfBirth: dateOfBirth,
            location: location,
          );
    });
    state.when(
      data: (user) => debugPrint(
          '[AuthNotifier] registerUser: state -> data (user=${user?.uid}, '
          'isProfileComplete=${user?.isProfileComplete})'),
      error: (e, st) =>
          debugPrint('[AuthNotifier] registerUser: state -> error: $e'),
      loading: () => debugPrint('[AuthNotifier] registerUser: still loading?!'),
    );
  }

  Future<void> signInWithEmail(String email, String password) async {
    debugPrint('[AuthNotifier] signInWithEmail: state -> loading ($email)');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      final cred = await repo.signInWithEmail(email, password);
      // Refresh lastLoginAt and return the up-to-date model.
      return repo.createUserDocumentAfterAuth(cred.user!,
          loginProvider: 'password');
    });
    state.when(
      data: (user) => debugPrint(
          '[AuthNotifier] signInWithEmail: state -> data (user=${user?.uid}, '
          'isProfileComplete=${user?.isProfileComplete})'),
      error: (e, st) =>
          debugPrint('[AuthNotifier] signInWithEmail: state -> error: $e'),
      loading: () =>
          debugPrint('[AuthNotifier] signInWithEmail: still loading?!'),
    );
  }

  /// Google sign-in. The returned [UserModel] is `null` only when the user
  /// cancels the picker; real failures propagate as an error state.
  Future<void> signInWithGoogle() async {
    debugPrint('[AuthNotifier] signInWithGoogle: state -> loading');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      return repo.signInWithGoogle();
    });
    state.when(
      data: (user) => debugPrint(
          '[AuthNotifier] signInWithGoogle: state -> data (user=${user?.uid})'),
      error: (e, st) =>
          debugPrint('[AuthNotifier] signInWithGoogle: state -> error: $e'),
      loading: () => debugPrint('[AuthNotifier] signInWithGoogle: still loading?!'),
    );
  }

  Future<void> signOut() async {
    debugPrint('[AuthNotifier] signOut: starting...');
    try {
      await ref.read(authRepositoryProvider).signOut();
      debugPrint('[AuthNotifier] signOut: Firebase sign-out succeeded.');
    } catch (e, st) {
      // Even if sign-out fails (e.g. network error), clear local state so the
      // user is not stuck on an authenticated screen. The router redirect will
      // see currentUser == null and navigate to /login.
      debugPrint('[AuthNotifier] signOut: Firebase sign-out failed (non-fatal): '
          '$e\n$st');
    }
    // Invalidate user-scoped providers to prevent stale data from leaking
    // into the next session if a different account signs in.
    ref.invalidate(currentUserProvider);
    state = const AsyncData(null);
    debugPrint('[AuthNotifier] signOut: local state cleared — '
        'GoRouterRefreshStream will redirect to /login.');
  }
}

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, UserModel?>(() => AuthNotifier());

// OTP state
class OtpState {
  final String? verificationId;
  final bool isLoading;
  final String? error;
  final bool codeSent;

  const OtpState({
    this.verificationId,
    this.isLoading = false,
    this.error,
    this.codeSent = false,
  });

  OtpState copyWith({
    String? verificationId,
    bool? isLoading,
    String? error,
    bool? codeSent,
  }) =>
      OtpState(
        verificationId: verificationId ?? this.verificationId,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        codeSent: codeSent ?? this.codeSent,
      );
}

class OtpNotifier extends Notifier<OtpState> {
  @override
  OtpState build() => const OtpState();

  Future<void> sendOtp(String phoneNumber) async {
    debugPrint('[OtpNotifier] sendOtp: requesting OTP for $phoneNumber');
    state = state.copyWith(isLoading: true, error: null);
    await ref.read(authRepositoryProvider).verifyPhone(
      phoneNumber: phoneNumber,
      onCodeSent: (id) {
        debugPrint('[OtpNotifier] sendOtp: code sent (verificationId=$id)');
        state = state.copyWith(verificationId: id, isLoading: false, codeSent: true);
      },
      onError: (e) {
        debugPrint('[OtpNotifier] sendOtp: error: $e');
        state = state.copyWith(isLoading: false, error: e);
      },
      onAutoVerified: (credential) async {
        // Some Android devices auto-detect the SMS and verify instantly
        // (before the user reaches the OTP screen). We don't auto-navigate
        // here — the user can still enter the code manually if this fires
        // too early; this just clears the loading spinner.
        debugPrint('[OtpNotifier] sendOtp: onAutoVerified fired.');
        state = state.copyWith(isLoading: false);
      },
    );
  }

  void reset() => state = const OtpState();
}

final otpNotifierProvider = NotifierProvider<OtpNotifier, OtpState>(() => OtpNotifier());
