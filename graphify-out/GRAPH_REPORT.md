# Graph Report - jothida_matrimony  (2026-06-11)

## Corpus Check
- 103 files · ~42,224 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1742 nodes · 2534 edges · 104 communities (101 shown, 3 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `70f5e5fc`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 33|Community 33]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 48|Community 48]]
- [[_COMMUNITY_Community 49|Community 49]]
- [[_COMMUNITY_Community 50|Community 50]]
- [[_COMMUNITY_Community 51|Community 51]]
- [[_COMMUNITY_Community 52|Community 52]]
- [[_COMMUNITY_Community 53|Community 53]]
- [[_COMMUNITY_Community 54|Community 54]]
- [[_COMMUNITY_Community 55|Community 55]]
- [[_COMMUNITY_Community 56|Community 56]]
- [[_COMMUNITY_Community 57|Community 57]]
- [[_COMMUNITY_Community 58|Community 58]]
- [[_COMMUNITY_Community 59|Community 59]]
- [[_COMMUNITY_Community 60|Community 60]]
- [[_COMMUNITY_Community 61|Community 61]]
- [[_COMMUNITY_Community 62|Community 62]]
- [[_COMMUNITY_Community 63|Community 63]]
- [[_COMMUNITY_Community 64|Community 64]]
- [[_COMMUNITY_Community 65|Community 65]]
- [[_COMMUNITY_Community 66|Community 66]]
- [[_COMMUNITY_Community 67|Community 67]]
- [[_COMMUNITY_Community 68|Community 68]]
- [[_COMMUNITY_Community 69|Community 69]]
- [[_COMMUNITY_Community 70|Community 70]]
- [[_COMMUNITY_Community 71|Community 71]]
- [[_COMMUNITY_Community 72|Community 72]]
- [[_COMMUNITY_Community 73|Community 73]]
- [[_COMMUNITY_Community 74|Community 74]]
- [[_COMMUNITY_Community 75|Community 75]]
- [[_COMMUNITY_Community 76|Community 76]]
- [[_COMMUNITY_Community 77|Community 77]]
- [[_COMMUNITY_Community 78|Community 78]]
- [[_COMMUNITY_Community 79|Community 79]]
- [[_COMMUNITY_Community 80|Community 80]]
- [[_COMMUNITY_Community 81|Community 81]]
- [[_COMMUNITY_Community 82|Community 82]]
- [[_COMMUNITY_Community 83|Community 83]]
- [[_COMMUNITY_Community 84|Community 84]]
- [[_COMMUNITY_Community 85|Community 85]]
- [[_COMMUNITY_Community 86|Community 86]]
- [[_COMMUNITY_Community 87|Community 87]]
- [[_COMMUNITY_Community 88|Community 88]]
- [[_COMMUNITY_Community 89|Community 89]]
- [[_COMMUNITY_Community 90|Community 90]]
- [[_COMMUNITY_Community 91|Community 91]]
- [[_COMMUNITY_Community 92|Community 92]]
- [[_COMMUNITY_Community 93|Community 93]]
- [[_COMMUNITY_Community 94|Community 94]]
- [[_COMMUNITY_Community 95|Community 95]]
- [[_COMMUNITY_Community 96|Community 96]]
- [[_COMMUNITY_Community 97|Community 97]]
- [[_COMMUNITY_Community 98|Community 98]]
- [[_COMMUNITY_Community 99|Community 99]]
- [[_COMMUNITY_Community 100|Community 100]]
- [[_COMMUNITY_Community 101|Community 101]]

## God Nodes (most connected - your core abstractions)
1. `authNotifierProvider` - 25 edges
2. `profileCreationProvider` - 19 edges
3. `dateTime` - 15 edges
4. `authRepositoryProvider` - 14 edges
5. `firebaseAuthStreamProvider` - 10 edges
6. `Firebase Setup — Jothida Matrimony` - 10 edges
7. `myProfileProvider` - 9 edges
8. `build` - 9 edges
9. `_MatchDetailsScreenState` - 8 edges
10. `adminActionsProvider` - 7 edges

## Surprising Connections (you probably didn't know these)
- `build` --references--> `authNotifierProvider`  [EXTRACTED]
  lib/screens/auth/otp_screen.dart → lib/providers/auth_provider.dart
- `_saveAndNext` --references--> `profileCreationProvider`  [EXTRACTED]
  lib/screens/profile/steps/step5_partner_prefs.dart → lib/providers/profile_provider.dart
- `_reject` --references--> `adminActionsProvider`  [EXTRACTED]
  lib/screens/admin/admin_approvals_screen.dart → lib/providers/admin_provider.dart
- `build` --references--> `adminActionsProvider`  [EXTRACTED]
  lib/screens/admin/admin_reports_screen.dart → lib/providers/admin_provider.dart
- `approveProfile` --references--> `adminRepositoryProvider`  [EXTRACTED]
  lib/providers/admin_provider.dart → lib/providers/service_providers.dart

## Import Cycles
- None detected.

## Communities (104 total, 3 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.02
Nodes (81): HoroscopeDetails get, about, aboutMe, additionalPhotos, age, annualIncome, birthPlace, birthTime (+73 more)

### Community 1 - "Community 1"
Cohesion: 0.03
Nodes (79): adminCollection, AppConstants, appName, appTagline, appVersion, astrologerRequestsCollection, astrologersCollection, astrologerSpecializations (+71 more)

### Community 2 - "Community 2"
Cohesion: 0.05
Nodes (45): ../astrologer/connect_astrologer_sheet.dart, AccountTypeScreen, _AccountTypeScreenState, ../../core/services/compatibility.dart, build, HomeScreen, _HomeScreenState, build (+37 more)

### Community 3 - "Community 3"
Cohesion: 0.05
Nodes (41): int get, about, Astrologer, AstrologerReview, AstrologerService, certifications, comment, description (+33 more)

### Community 4 - "Community 4"
Cohesion: 0.05
Nodes (42): static const Color, static const LinearGradient, alertCritical, alertHigh, alertNormal, alertWarning, AppColors, background (+34 more)

### Community 5 - "Community 5"
Cohesion: 0.05
Nodes (38): app_colors.dart, appName, businessName, currency, description, keyId, RazorpayConstants, supportEmail (+30 more)

### Community 6 - "Community 6"
Cohesion: 0.05
Nodes (38): ageScore, at, avgCat, bt, careerScore, categories, CompatibilityCategory, computeCompatibility (+30 more)

### Community 7 - "Community 7"
Cohesion: 0.06
Nodes (33): approveProfile, blockUser, createOrUpdateUserOnLogin, createProfile, _db, getActiveSubscription, getAdminStats, getAllReports (+25 more)

### Community 8 - "Community 8"
Cohesion: 0.06
Nodes (30): _about, _banner, build, _certFileName, _certName, _certNumber, _certOrg, _certUpload (+22 more)

### Community 9 - "Community 9"
Cohesion: 0.07
Nodes (30): astrologer_model.dart, about, certFileName, certName, certNumber, certOrg, city, consultationModes (+22 more)

### Community 10 - "Community 10"
Cohesion: 0.07
Nodes (26): GoRouter, authState, ../screens/admin/admin_approvals_screen.dart, ../screens/admin/admin_dashboard.dart, ../screens/admin/admin_reports_screen.dart, ../screens/admin/admin_shell.dart, ../screens/admin/admin_users_screen.dart, ../screens/astrologer/astrologer_dashboard_screen.dart (+18 more)

### Community 11 - "Community 11"
Cohesion: 0.07
Nodes (26): copyWith, createdAt, displayName, email, false, fcmToken, freePortuthamsUsed, fromFirestore (+18 more)

### Community 12 - "Community 12"
Cohesion: 0.09
Nodes (22): Animation, AnimationController, _controller, createState, dispose, _fade, icon, iconBg (+14 more)

### Community 13 - "Community 13"
Cohesion: 0.10
Nodes (23): account, _AvailabilitySection, _BookingsSection, build, _fmt, _info, _list, _OverviewSection (+15 more)

### Community 14 - "Community 14"
Cohesion: 0.12
Nodes (23): AsyncNotifier, UserModel, authAsync, AuthNotifier, build, codeSent, copyWith, error (+15 more)

### Community 15 - "Community 15"
Cohesion: 0.09
Nodes (23): discoverProvider, _activeChip, _ageRange, _applyFilters, build, _buildEmptyState, _city, createState (+15 more)

### Community 16 - "Community 16"
Cohesion: 0.08
Nodes (23): _aboutController, _annualIncome, build, _caste, _city, _country, createState, dispose (+15 more)

### Community 17 - "Community 17"
Cohesion: 0.09
Nodes (22): AstrologerRegisterScreen, _AstrologerRegisterScreenState, _buildAccount, _cityController, _confirmPasswordController, createState, dispose, _emailController (+14 more)

### Community 18 - "Community 18"
Cohesion: 0.09
Nodes (21): File?, authAsync, build, copyWith, data, error, filters, hasMore (+13 more)

### Community 19 - "Community 19"
Cohesion: 0.10
Nodes (21): amount, astrologerId, AstrologerRequestModel, AstrologerRequestStatus, AstrologerRequestStatusX, AstrologerRequestType, AstrologerRequestTypeX, copyWith (+13 more)

### Community 20 - "Community 20"
Cohesion: 0.14
Nodes (21): _afterAuth, build, _submit, _routeByRole, _signInWithEmail, _signInWithGoogle, _verify, build (+13 more)

### Community 21 - "Community 21"
Cohesion: 0.10
Nodes (19): ../../core/constants/app_constants.dart, ../../core/constants/razorpay_constants.dart, package:razorpay_flutter/razorpay_flutter.dart, build, _planPrice, purchase, userId, watch (+11 more)

### Community 22 - "Community 22"
Cohesion: 0.10
Nodes (20): ../../core/data/sample_astrologer_dashboard.dart, AstrologerAccount, account, avgRating, bookingEarnings, bookings, build, completed (+12 more)

### Community 23 - "Community 23"
Cohesion: 0.12
Nodes (19): build, _buildTab, createState, dispose, _emailController, _formKey, LoginMode, LoginScreen (+11 more)

### Community 24 - "Community 24"
Cohesion: 0.11
Nodes (19): demo_data_provider.dart, profile_provider.dart, build, ChatController, copyWith, DemoChatNotifier, demoChatProvider, DemoChatState (+11 more)

### Community 25 - "Community 25"
Cohesion: 0.10
Nodes (19): _auth, AuthRepository, authStateChanges, createUserDocumentAfterAuth, currentUser, currentUserId, _fcm, _firestore (+11 more)

### Community 26 - "Community 26"
Cohesion: 0.11
Nodes (18): ../../../core/data/selection_data.dart, ../../../core/utils/horoscope_utils.dart, _birthPlace, _birthTime, _birthTimeController, build, createState, dispose (+10 more)

### Community 27 - "Community 27"
Cohesion: 0.11
Nodes (18): _auth, AuthService, authStateChanges, currentUser, currentUserId, _googleSignIn, registerWithEmail, sendPasswordReset (+10 more)

### Community 28 - "Community 28"
Cohesion: 0.11
Nodes (18): fromFirestore, id, lastMessage, lastMessageAt, lastSenderId, otherId, otherName, otherPhoto (+10 more)

### Community 29 - "Community 29"
Cohesion: 0.11
Nodes (18): createState, _currentStep, dispose, _nextStep, _pageController, _prevStep, ProfileCreationScreen, _ProfileCreationScreenState (+10 more)

### Community 30 - "Community 30"
Cohesion: 0.11
Nodes (17): _confirmPasswordController, createState, dispose, _dob, _dobController, _emailController, _formKey, _gender (+9 more)

### Community 31 - "Community 31"
Cohesion: 0.11
Nodes (17): build, controller, hint, inputFormatters, keyboardType, label, maxLength, maxLines (+9 more)

### Community 32 - "Community 32"
Cohesion: 0.12
Nodes (16): FirestoreService, ../../models/subscription_model.dart, AdminRepository, approveProfile, blockUser, _firestore, getAdminStats, getAllReports (+8 more)

### Community 33 - "Community 33"
Cohesion: 0.14
Nodes (17): build, _buildInfoSection, _buildProfileView, createState, icon, _InfoItem, label, _photoIndex (+9 more)

### Community 34 - "Community 34"
Cohesion: 0.12
Nodes (15): ../astrologer/astrologers_tab.dart, _activeIcons, createState, _icons, _selectedIndex, _tabs, package:flutter_riverpod/flutter_riverpod.dart, ../../../providers/notification_provider.dart (+7 more)

### Community 35 - "Community 35"
Cohesion: 0.12
Nodes (16): adminNotes, alertLevel, createdAt, description, fromFirestore, getAlertLevel, id, isResolved (+8 more)

### Community 36 - "Community 36"
Cohesion: 0.12
Nodes (16): _brothers, build, _buildCounter, _buildSegment, createState, dispose, _familyStatus, _familyType (+8 more)

### Community 37 - "Community 37"
Cohesion: 0.12
Nodes (14): color, icon, label, onTap, _StatCard, title, value, package:fl_chart/fl_chart.dart (+6 more)

### Community 38 - "Community 38"
Cohesion: 0.16
Nodes (13): Astrologer, astrologer, _intro, _section, astrologer, AstrologerSheetCard, _availabilityDot, showConnectAstrologerSheet (+5 more)

### Community 39 - "Community 39"
Cohesion: 0.13
Nodes (15): AstrologerService, chatServiceProvider, fcmServiceProvider, razorpayServiceProvider, storageServiceProvider, subscriptionRepositoryProvider, SubscriptionNotifier, ../repositories/admin_repository.dart (+7 more)

### Community 40 - "Community 40"
Cohesion: 0.17
Nodes (16): OtpScreen, _OtpScreenState, RegisterScreen, _RegisterScreenState, SplashScreen, _SplashScreenState, ConsumerState, ConsumerStatefulWidget (+8 more)

### Community 41 - "Community 41"
Cohesion: 0.12
Nodes (15): fromFirestore, id, InterestModel, isAccepted, isPending, isRejected, message, receiverId (+7 more)

### Community 42 - "Community 42"
Cohesion: 0.13
Nodes (14): @pragma, buildPayload, _db, deleteToken, FcmService, _firebaseMessagingBackgroundHandler, getToken, initialize (+6 more)

### Community 43 - "Community 43"
Cohesion: 0.16
Nodes (14): AstrologerLoginScreen, _AstrologerLoginScreenState, createState, dispose, _emailController, _formKey, _obscurePassword, _passwordController (+6 more)

### Community 44 - "Community 44"
Cohesion: 0.14
Nodes (14): astrologerId, AstrologerProfileScreen, _bookingBar, build, _chips, _comingSoonSection, _headerBackground, _reviewsList (+6 more)

### Community 45 - "Community 45"
Cohesion: 0.15
Nodes (14): build, _buildSuccess, createState, dispose, _emailController, ForgotPasswordScreen, _ForgotPasswordScreenState, _formKey (+6 more)

### Community 46 - "Community 46"
Cohesion: 0.16
Nodes (14): build, ChatScreen, _ChatScreenState, _controller, createState, dispose, extra, isMine (+6 more)

### Community 47 - "Community 47"
Cohesion: 0.13
Nodes (14): AstrologerService, createAccount, createRequest, _db, getAccount, updateAccount, updateRequestStatus, watchAccount (+6 more)

### Community 48 - "Community 48"
Cohesion: 0.15
Nodes (14): ../../../models/interest_request_model.dart, accept, build, _counter, incomingRequestsProvider, matchesProvider, outgoingRequestsProvider, reject (+6 more)

### Community 49 - "Community 49"
Cohesion: 0.14
Nodes (13): ../../providers/auth_provider.dart, ../../providers/profile_provider.dart, ../../providers/subscription_provider.dart, features, isPopular, isPremium, plan, price (+5 more)

### Community 50 - "Community 50"
Cohesion: 0.20
Nodes (13): _ApprovalCard, _reject, _ReportTile, AdminUsersScreen, build, _roleColor, user, _UserTile (+5 more)

### Community 51 - "Community 51"
Cohesion: 0.19
Nodes (13): AstrologersTab, build, build, _ConnectAstrologerSheet, ../core/data/sample_astrologers.dart, astrologersProvider, list, null (+5 more)

### Community 52 - "Community 52"
Cohesion: 0.16
Nodes (13): AsyncValue, auth_provider.dart, ../../models/interest_model.dart, acceptInterest, build, InterestNotifier, receivedInterestsProvider, rejectInterest (+5 more)

### Community 53 - "Community 53"
Cohesion: 0.15
Nodes (13): ../../providers/demo_data_provider.dart, ../../providers/requests_provider.dart, requestsProvider, _actions, createState, dispose, request, _RequestCard (+5 more)

### Community 54 - "Community 54"
Cohesion: 0.15
Nodes (13): RangeValues, _ageRange, build, _buildDropdown, _caste, createState, _education, onNext (+5 more)

### Community 55 - "Community 55"
Cohesion: 0.14
Nodes (13): createProfile, _firestore, getProfile, getProfileByUserId, incrementViewCount, ProfileRepository, searchProfiles, _storage (+5 more)

### Community 56 - "Community 56"
Cohesion: 0.15
Nodes (13): typedef, about, age, AppValidators, confirmPassword, email, name, otp (+5 more)

### Community 57 - "Community 57"
Cohesion: 0.15
Nodes (12): ../constants/app_constants.dart, calculateAge, calculateDasaBalance, calculateKaranam, calculateLagnam, calculateNakshatra, calculateRasi, calculateYogam (+4 more)

### Community 58 - "Community 58"
Cohesion: 0.15
Nodes (12): ../../../core/utils/validators.dart, build, createState, dispose, _formKey, isLoading, _mobileController, _nameController (+4 more)

### Community 59 - "Community 59"
Cohesion: 0.15
Nodes (12): dart:io, deleteFile, deleteProfilePhotos, _storage, StorageService, uploadHoroscopeImage, uploadHoroscopePdf, uploadIdProof (+4 more)

### Community 60 - "Community 60"
Cohesion: 0.15
Nodes (12): Map, body, createdAt, data, fromFirestore, id, isRead, NotificationModel (+4 more)

### Community 61 - "Community 61"
Cohesion: 0.18
Nodes (12): ../../models/notification_model.dart, build, markRead, notificationNotifierProvider, notificationsProvider, notifs, userId, watch (+4 more)

### Community 62 - "Community 62"
Cohesion: 0.20
Nodes (11): build, ChatListScreen, myUid, thread, _ThreadTile, _when, ChatThread, ../../models/chat_model.dart (+3 more)

### Community 63 - "Community 63"
Cohesion: 0.17
Nodes (11): CollectionReference, _chats, ChatService, _db, getOrCreateThread, markThreadRead, sendMessage, watchMessages (+3 more)

### Community 64 - "Community 64"
Cohesion: 0.17
Nodes (11): AvailabilitySlot, b, defaultAstrologerServices, enabled, end, now, sampleBookings, sampleDashboardReviews (+3 more)

### Community 65 - "Community 65"
Cohesion: 0.17
Nodes (11): castesByReligion, castesFor, citiesByState, citiesFor, countries, indianStates, SelectionData, subCastesByCaste (+3 more)

### Community 66 - "Community 66"
Cohesion: 0.17
Nodes (11): AuthException, cancelled, code, from, message, toString, userCancelled, Exception (+3 more)

### Community 67 - "Community 67"
Cohesion: 0.18
Nodes (11): amount, AstrologerBooking, BookingStatus, BookingStatusX, dateTime, id, mode, serviceName (+3 more)

### Community 68 - "Community 68"
Cohesion: 0.17
Nodes (11): copyWith, direction, id, InterestRequest, isAccepted, isIncoming, profileId, RequestDirection (+3 more)

### Community 69 - "Community 69"
Cohesion: 0.17
Nodes (11): build, createState, initState, _loading, onChanged, _settings, subtitle, title (+3 more)

### Community 70 - "Community 70"
Cohesion: 0.18
Nodes (10): build, _canResend, createState, initState, _otp, phone, _secondsLeft, _startTimer (+2 more)

### Community 71 - "Community 71"
Cohesion: 0.18
Nodes (10): bool get, checks, computeProfileCompletion, filled, isComplete, missing, missingFields, percent (+2 more)

### Community 72 - "Community 72"
Cohesion: 0.18
Nodes (10): build, gradient, GradientButton, height, isLoading, onPressed, text, width (+2 more)

### Community 73 - "Community 73"
Cohesion: 0.18
Nodes (10): build, enabled, isRequired, items, label, onChanged, prefixIcon, selectedItem (+2 more)

### Community 74 - "Community 74"
Cohesion: 0.18
Nodes (10): core/theme/app_theme.dart, firebase_options.dart, _localizationsDelegates, main, package:flutter_localizations/flutter_localizations.dart, package:jothida_matrimony/l10n/app_localizations.dart, ../../providers/locale_provider.dart, router/app_router.dart (+2 more)

### Community 75 - "Community 75"
Cohesion: 0.18
Nodes (10): 1. Firebase project + Android app, 2. Register the SHA-1 / SHA-256 fingerprints (fixes error 10) — IMPORTANT, 3. Download the real `google-services.json`, 4. Regenerate `lib/firebase_options.dart`, 5. Enable sign-in providers, 6. Firestore database + rules, 7. CI/CD secrets (GitHub Actions), Firebase Setup — Jothida Matrimony (+2 more)

### Community 76 - "Community 76"
Cohesion: 0.22
Nodes (9): AdminApprovalsScreen, build, icon, _InfoChip, label, profile, IconData?, ProfileModel (+1 more)

### Community 77 - "Community 77"
Cohesion: 0.20
Nodes (10): _QuickAction, _ProfileSection, _ServicesSection, _AstrologerCard, _TypeCard, _Bubble, AppTextField, SearchableField (+2 more)

### Community 78 - "Community 78"
Cohesion: 0.20
Nodes (9): Locale?, package:shared_preferences/shared_preferences.dart, build, code, _kLocaleKey, LocaleNotifier, prefs, setLocale (+1 more)

### Community 79 - "Community 79"
Cohesion: 0.20
Nodes (9): package:cloud_firestore/cloud_firestore.dart, acceptInterest, _firestore, getInterestBetweenProfiles, InterestRepository, rejectInterest, sendInterest, watchReceivedInterests (+1 more)

### Community 80 - "Community 80"
Cohesion: 0.20
Nodes (9): package:image_picker/image_picker.dart, build, createState, onNext, _photos, _picker, _pickPhoto, _removePhoto (+1 more)

### Community 81 - "Community 81"
Cohesion: 0.25
Nodes (8): AdminReportsScreen, _alertColor, build, report, ../../models/report_model.dart, ReportModel, allReportsProvider, ../../providers/admin_provider.dart

### Community 82 - "Community 82"
Cohesion: 0.25
Nodes (8): AdminShell, _AdminShellState, child, createState, _index, _routes, static const, Widget?

### Community 83 - "Community 83"
Cohesion: 0.22
Nodes (8): ../../core/theme/app_text_styles.dart, build, createState, _gender, _genderCard, onNext, _profileFor, _profileForOptions

### Community 84 - "Community 84"
Cohesion: 0.22
Nodes (9): build, profileCreationProvider, _saveAndNext, _saveAndNext, _autoGenerate, _saveAndNext, _saveAndNext, _saveAndNext (+1 more)

### Community 85 - "Community 85"
Cohesion: 0.25
Nodes (7): android, DefaultFirebaseOptions, ios, web, package:firebase_core/firebase_core.dart, package:flutter/foundation.dart, static const FirebaseOptions

### Community 86 - "Community 86"
Cohesion: 0.32
Nodes (8): build, JothidaMatrimonyApp, initialLocaleProvider, localeProvider, appRouterProvider, build, _choose, LanguageScreen

### Community 87 - "Community 87"
Cohesion: 0.29
Nodes (8): _loadSettings, PrivacySettingsScreen, _PrivacyState, _save, _submitProfile, firebaseAuthStreamProvider, NotificationNotifier, firestoreServiceProvider

### Community 88 - "Community 88"
Cohesion: 0.29
Nodes (6): app_text_styles.dart, package:flutter/material.dart, static ThemeData get, AppTheme, darkTheme, lightTheme

### Community 89 - "Community 89"
Cohesion: 0.29
Nodes (6): ../core/data/sample_profiles.dart, build, byId, discover, kDemoUserId, upsert

### Community 90 - "Community 90"
Cohesion: 0.29
Nodes (6): a, reviews, s, sampleAstrologers, services, ../../models/astrologer_model.dart

### Community 91 - "Community 91"
Cohesion: 0.29
Nodes (6): _build, featured, now, sampleProfiles, ../../models/profile_model.dart, required int prefMaxAge,
  bool

### Community 92 - "Community 92"
Cohesion: 0.43
Nodes (6): AdminActionsNotifier, approveProfile, blockUser, build, rejectProfile, adminRepositoryProvider

### Community 93 - "Community 93"
Cohesion: 0.33
Nodes (7): demoProfilesProvider, myDemoProfileIdProvider, DiscoverNotifier, DiscoverState, ProfileCreationNotifier, ProfileCreationState, submitProfile

### Community 94 - "Community 94"
Cohesion: 0.33
Nodes (6): AdminDashboard, build, adminStatsProvider, Route /admin/approvals, Route /admin/reports, Route /admin/users

### Community 95 - "Community 95"
Cohesion: 0.33
Nodes (6): initState, _send, chatControllerProvider, hasSentInterestProvider, _openChat, _ProfileCard

### Community 96 - "Community 96"
Cohesion: 0.40
Nodes (5): build, build, build, Route /astrologer-login, Route /login

### Community 97 - "Community 97"
Cohesion: 0.60
Nodes (5): List, Notifier, DemoAstrologerRequestsNotifier, DemoProfilesNotifier, RequestsNotifier

### Community 98 - "Community 98"
Cohesion: 0.50
Nodes (4): AstrologerDashboardScreen, AstrologerOnboardingScreen, _AstrologerOnboardingScreenState, myAstrologerAccountProvider

## Knowledge Gaps
- **1157 isolated node(s):** `kBypassAuth`, `AppConstants`, `appName`, `appTagline`, `appVersion` (+1152 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `dateTime` connect `Community 67` to `Community 0`, `Community 3`, `Community 68`, `Community 35`, `Community 8`, `Community 9`, `Community 41`, `Community 11`, `Community 60`, `Community 16`, `Community 19`, `Community 28`, `Community 30`?**
  _High betweenness centrality (0.089) - this node is a cross-community bridge._
- **Why does `FirestoreService` connect `Community 32` to `Community 39`, `Community 7`, `Community 79`, `Community 55`, `Community 25`?**
  _High betweenness centrality (0.006) - this node is a cross-community bridge._
- **Why does `ProfileModel` connect `Community 76` to `Community 0`, `Community 15`?**
  _High betweenness centrality (0.006) - this node is a cross-community bridge._
- **What connects `kBypassAuth`, `AppConstants`, `appName` to the rest of the system?**
  _1157 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.024390243902439025 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.025 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.05217391304347826 - nodes in this community are weakly interconnected._