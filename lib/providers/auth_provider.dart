import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import 'service_providers.dart';

// Raw Firebase auth stream
final firebaseAuthStreamProvider = StreamProvider<User?>((ref) =>
    ref.watch(authRepositoryProvider).authStateChanges);

// Current UserModel (loaded after auth)
final currentUserProvider = FutureProvider.autoDispose<UserModel?>((ref) async {
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
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      final cred = await repo.signInWithOTP(verificationId, otp);
      return repo.createUserDocumentAfterAuth(
          cred.user!, phone: cred.user!.phoneNumber);
    });
  }

  Future<void> registerWithEmail(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      final cred = await repo.registerWithEmail(email, password);
      return repo.createUserDocumentAfterAuth(cred.user!);
    });
  }

  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      final cred = await repo.signInWithEmail(email, password);
      // Refresh lastLoginAt and return the up-to-date model.
      return repo.createUserDocumentAfterAuth(cred.user!);
    });
  }

  /// Google sign-in. The returned [UserModel] is `null` only when the user
  /// cancels the picker; real failures propagate as an error state.
  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      return repo.signInWithGoogle();
    });
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AsyncData(null);
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
    state = state.copyWith(isLoading: true, error: null);
    await ref.read(authRepositoryProvider).verifyPhone(
      phoneNumber: phoneNumber,
      onCodeSent: (id) {
        state = state.copyWith(verificationId: id, isLoading: false, codeSent: true);
      },
      onError: (e) {
        state = state.copyWith(isLoading: false, error: e);
      },
      onAutoVerified: (credential) async {
        // Auto sign-in handled separately
        state = state.copyWith(isLoading: false);
      },
    );
  }

  void reset() => state = const OtpState();
}

final otpNotifierProvider = NotifierProvider<OtpNotifier, OtpState>(() => OtpNotifier());
