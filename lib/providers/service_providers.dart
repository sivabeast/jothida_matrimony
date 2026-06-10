import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firebase/auth_service.dart';
import '../services/firebase/firestore_service.dart';
import '../services/firebase/storage_service.dart';
import '../services/firebase/fcm_service.dart';
import '../services/razorpay/razorpay_service.dart';
import '../repositories/auth_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/interest_repository.dart';
import '../repositories/subscription_repository.dart';
import '../repositories/admin_repository.dart';

// ── Services ──────────────────────────────────────────────────────────────────
final authServiceProvider = Provider<AuthService>((ref) => AuthService());
final firestoreServiceProvider = Provider<FirestoreService>((ref) => FirestoreService());
final storageServiceProvider = Provider<StorageService>((ref) => StorageService());
final fcmServiceProvider = Provider<FcmService>((ref) => FcmService());
final razorpayServiceProvider = Provider<RazorpayService>((ref) => RazorpayService());

// ── Repositories ──────────────────────────────────────────────────────────────
final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(
      ref.watch(authServiceProvider),
      ref.watch(firestoreServiceProvider),
      ref.watch(fcmServiceProvider),
    ));

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository(
      ref.watch(firestoreServiceProvider),
      ref.watch(storageServiceProvider),
    ));

final interestRepositoryProvider = Provider<InterestRepository>((ref) => InterestRepository(
      ref.watch(firestoreServiceProvider),
    ));

final subscriptionRepositoryProvider =
    Provider<SubscriptionRepository>((ref) => SubscriptionRepository(
          ref.watch(firestoreServiceProvider),
        ));

final adminRepositoryProvider = Provider<AdminRepository>((ref) => AdminRepository(
      ref.watch(firestoreServiceProvider),
    ));
