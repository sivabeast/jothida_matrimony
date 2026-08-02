import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firebase/auth_service.dart';
import '../services/firebase/firestore_service.dart';
import '../services/storage_service.dart';
import '../services/cloudinary/cloudinary_storage_service.dart';
import '../services/firebase/fcm_service.dart';
import '../services/firebase/astrologer_service.dart';
import '../services/firebase/astrology_team_service.dart';
import '../services/firebase/consultation_service.dart';
import '../services/firebase/chat_service.dart';
import '../services/firebase/login_directory_service.dart';
import '../services/billing/play_billing_service.dart';
import '../repositories/auth_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/interest_repository.dart';
import '../repositories/admin_repository.dart';

// ── Services ──────────────────────────────────────────────────────────────────
final authServiceProvider = Provider<AuthService>((ref) => AuthService());
final firestoreServiceProvider = Provider<FirestoreService>((ref) => FirestoreService());
// Profile media (photos, horoscope PDFs/images, ID proof) is uploaded to
// Cloudinary (unsigned upload preset) — see lib/services/storage_service.dart
// for the abstraction and lib/services/firebase/storage_service.dart for the
// Firebase Storage alternative (requires the Blaze plan).
final storageServiceProvider =
    Provider<StorageService>((ref) => CloudinaryStorageService());
final fcmServiceProvider = Provider<FcmService>((ref) => FcmService());

/// App-wide Google Play Billing service (replaces the removed Razorpay service).
/// A single instance owns one purchase-stream listener; disposed with the
/// provider container at app shutdown.
final playBillingServiceProvider = Provider<PlayBillingService>((ref) {
  final billing = PlayBillingService();
  ref.onDispose(billing.dispose);
  return billing;
});
final astrologerServiceProvider =
    Provider<AstrologerService>((ref) => AstrologerService());
final astrologyTeamServiceProvider =
    Provider<AstrologyTeamService>((ref) => AstrologyTeamService());
final consultationServiceProvider =
    Provider<ConsultationService>((ref) => ConsultationService());
final chatServiceProvider = Provider<ChatService>((ref) => ChatService());

/// Mobile-number → sign-in-address index, used to resolve a phone login before
/// the user is authenticated (see [LoginDirectoryService]).
final loginDirectoryServiceProvider =
    Provider<LoginDirectoryService>((ref) => LoginDirectoryService());

// ── Repositories ──────────────────────────────────────────────────────────────
final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(
      ref.watch(authServiceProvider),
      ref.watch(firestoreServiceProvider),
      ref.watch(fcmServiceProvider),
      ref.watch(loginDirectoryServiceProvider),
    ));

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository(
      ref.watch(firestoreServiceProvider),
      ref.watch(storageServiceProvider),
    ));

final interestRepositoryProvider = Provider<InterestRepository>((ref) => InterestRepository(
      ref.watch(firestoreServiceProvider),
    ));

final adminRepositoryProvider = Provider<AdminRepository>((ref) => AdminRepository(
      ref.watch(firestoreServiceProvider),
    ));
