# Graph Report - jothida_matrimony  (2026-06-12)

## Corpus Check
- 122 files · ~144,805 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1898 nodes · 2791 edges · 114 communities (107 shown, 7 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `5fa28b27`
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
- [[_COMMUNITY_Community 104|Community 104]]
- [[_COMMUNITY_Community 105|Community 105]]
- [[_COMMUNITY_Community 106|Community 106]]
- [[_COMMUNITY_Community 107|Community 107]]
- [[_COMMUNITY_Community 108|Community 108]]
- [[_COMMUNITY_Community 109|Community 109]]
- [[_COMMUNITY_Community 110|Community 110]]

## God Nodes (most connected - your core abstractions)
1. `authNotifierProvider` - 24 edges
2. `profileCreationProvider` - 19 edges
3. `dateTime` - 16 edges
4. `firebaseAuthStreamProvider` - 14 edges
5. `authRepositoryProvider` - 14 edges
6. `Firebase Setup — Jothida Matrimony` - 10 edges
7. `myProfileProvider` - 9 edges
8. `discoverProvider` - 9 edges
9. `build` - 9 edges
10. `matchGenderProvider` - 8 edges

## Surprising Connections (you probably didn't know these)
- `build` --references--> `authNotifierProvider`  [EXTRACTED]
  lib/screens/auth/otp_screen.dart → lib/providers/auth_provider.dart
- `_saveAndNext` --references--> `profileCreationProvider`  [EXTRACTED]
  lib/screens/profile/steps/step5_partner_prefs.dart → lib/providers/profile_provider.dart
- `JothidaMatrimonyApp` --references--> `localeProvider`  [EXTRACTED]
  lib/main.dart → lib/providers/locale_provider.dart
- `build` --references--> `localeProvider`  [EXTRACTED]
  lib/main.dart → lib/providers/locale_provider.dart
- `_reject` --references--> `adminActionsProvider`  [EXTRACTED]
  lib/screens/admin/admin_approvals_screen.dart → lib/providers/admin_provider.dart

## Import Cycles
- None detected.

## Communities (114 total, 7 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.02
Nodes (81): HoroscopeDetails get, about, aboutMe, additionalPhotos, age, annualIncome, birthPlace, birthTime (+73 more)

### Community 1 - "Community 1"
Cohesion: 0.03
Nodes (79): adminCollection, AppConstants, appName, appTagline, appVersion, astrologerRequestsCollection, astrologersCollection, astrologerSpecializations (+71 more)

### Community 2 - "Community 2"
Cohesion: 0.10
Nodes (20): ../astrologer/connect_astrologer_sheet.dart, ../../core/services/compatibility.dart, _bullet, _card, _categoryCard, _connectAstrologerCard, _controller, createState (+12 more)

### Community 3 - "Community 3"
Cohesion: 0.05
Nodes (41): int get, about, Astrologer, AstrologerReview, AstrologerService, certifications, comment, description (+33 more)

### Community 4 - "Community 4"
Cohesion: 0.05
Nodes (42): static const Color, static const LinearGradient, alertCritical, alertHigh, alertNormal, alertWarning, AppColors, background (+34 more)

### Community 5 - "Community 5"
Cohesion: 0.04
Nodes (43): app_colors.dart, app_text_styles.dart, appName, businessName, currency, description, keyId, RazorpayConstants (+35 more)

### Community 6 - "Community 6"
Cohesion: 0.05
Nodes (38): ageScore, at, avgCat, bt, careerScore, categories, CompatibilityCategory, computeCompatibility (+30 more)

### Community 7 - "Community 7"
Cohesion: 0.06
Nodes (33): approveProfile, blockUser, createOrUpdateUserOnLogin, createProfile, _db, getActiveSubscription, getAdminStats, getAllReports (+25 more)

### Community 8 - "Community 8"
Cohesion: 0.07
Nodes (28): _age, assetPath, _bannerCtrl, _BannerData, _bannerPage, _banners, _bannerTimer, _buildBannerCarousel (+20 more)

### Community 9 - "Community 9"
Cohesion: 0.06
Nodes (32): astrologer_model.dart, about, certFileName, certName, certNumber, certOrg, city, consultationFee (+24 more)

### Community 10 - "Community 10"
Cohesion: 0.07
Nodes (29): GoRouter, authRepo, dispose, refreshStream, _subscription, ../screens/admin/admin_approvals_screen.dart, ../screens/admin/admin_dashboard.dart, ../screens/admin/admin_reports_screen.dart (+21 more)

### Community 11 - "Community 11"
Cohesion: 0.07
Nodes (28): copyWith, createdAt, displayName, email, false, fcmToken, freePortuthamsUsed, fromFirestore (+20 more)

### Community 12 - "Community 12"
Cohesion: 0.13
Nodes (14): _controller, createState, dispose, _fade, icon, iconBg, initState, onTap (+6 more)

### Community 13 - "Community 13"
Cohesion: 0.12
Nodes (16): account, _fmt, _info, _list, pending, _ProfileSection, rejected, request (+8 more)

### Community 14 - "Community 14"
Cohesion: 0.12
Nodes (23): AsyncNotifier, UserModel, authAsync, AuthNotifier, build, codeSent, copyWith, error (+15 more)

### Community 15 - "Community 15"
Cohesion: 0.11
Nodes (19): hasSentInterestProvider, _activeChip, _ageRange, build, _buildEmptyState, _city, createState, _detailLine (+11 more)

### Community 16 - "Community 16"
Cohesion: 0.08
Nodes (25): _aboutController, _annualIncome, build, _caste, _city, _country, createState, dispose (+17 more)

### Community 17 - "Community 17"
Cohesion: 0.06
Nodes (37): _aboutController, _buildAccount, _chipGroup, _city, _country, createState, dispose, _dob (+29 more)

### Community 18 - "Community 18"
Cohesion: 0.07
Nodes (26): File?, authAsync, build, copyWith, data, error, filters, _friendlyProfileError (+18 more)

### Community 19 - "Community 19"
Cohesion: 0.10
Nodes (21): amount, astrologerId, AstrologerRequestModel, AstrologerRequestStatus, AstrologerRequestStatusX, AstrologerRequestType, AstrologerRequestTypeX, copyWith (+13 more)

### Community 20 - "Community 20"
Cohesion: 0.06
Nodes (45): build, _afterAuth, AstrologerLoginScreen, _AstrologerLoginScreenState, build, _signIn, _signInWithGoogle, build (+37 more)

### Community 21 - "Community 21"
Cohesion: 0.10
Nodes (19): ../../core/constants/app_constants.dart, ../../core/constants/razorpay_constants.dart, package:razorpay_flutter/razorpay_flutter.dart, build, _planPrice, purchase, userId, watch (+11 more)

### Community 22 - "Community 22"
Cohesion: 0.11
Nodes (17): account, avgRating, bookingEarnings, bookings, build, completed, completeOnboarding, demoAstrologerRequestsProvider (+9 more)

### Community 23 - "Community 23"
Cohesion: 0.09
Nodes (22): _buildTab, createState, dispose, _emailController, _formKey, LoginMode, _mode, _obscurePassword (+14 more)

### Community 24 - "Community 24"
Cohesion: 0.11
Nodes (19): demo_data_provider.dart, profile_provider.dart, build, ChatController, copyWith, DemoChatNotifier, demoChatProvider, DemoChatState (+11 more)

### Community 25 - "Community 25"
Cohesion: 0.10
Nodes (19): _auth, AuthRepository, authStateChanges, createUserDocumentAfterAuth, currentUser, currentUserId, _fcm, _firestore (+11 more)

### Community 26 - "Community 26"
Cohesion: 0.12
Nodes (16): ../../../core/utils/horoscope_utils.dart, _birthPlace, _birthTime, _birthTimeController, build, createState, dispose, _lagnam (+8 more)

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
Nodes (17): AppTextField, build, controller, hint, inputFormatters, keyboardType, label, maxLength (+9 more)

### Community 32 - "Community 32"
Cohesion: 0.12
Nodes (16): FirestoreService, ../../models/subscription_model.dart, AdminRepository, approveProfile, blockUser, _firestore, getAdminStats, getAllReports (+8 more)

### Community 33 - "Community 33"
Cohesion: 0.14
Nodes (17): build, _buildInfoSection, _buildProfileView, createState, icon, _InfoItem, label, _photoIndex (+9 more)

### Community 34 - "Community 34"
Cohesion: 0.12
Nodes (16): ../chat/chat_list_screen.dart, activeIcon, _BottomNav, createState, icon, _items, label, _NavItem (+8 more)

### Community 35 - "Community 35"
Cohesion: 0.12
Nodes (16): adminNotes, alertLevel, createdAt, description, fromFirestore, getAlertLevel, id, isResolved (+8 more)

### Community 36 - "Community 36"
Cohesion: 0.12
Nodes (16): _brothers, build, _buildCounter, _buildSegment, createState, dispose, _familyStatus, _familyType (+8 more)

### Community 37 - "Community 37"
Cohesion: 0.12
Nodes (16): AdminDashboard, build, color, icon, label, onTap, _QuickAction, _StatCard (+8 more)

### Community 38 - "Community 38"
Cohesion: 0.18
Nodes (10): astrologer, AstrologerSheetCard, _availabilityDot, showConnectAstrologerSheet, package:flutter_riverpod/flutter_riverpod.dart, package:flutter/widgets.dart, package:go_router/go_router.dart, ../../providers/astrologer_session_provider.dart (+2 more)

### Community 39 - "Community 39"
Cohesion: 0.13
Nodes (15): AstrologerService, chatServiceProvider, fcmServiceProvider, razorpayServiceProvider, subscriptionRepositoryProvider, SubscriptionNotifier, ../repositories/admin_repository.dart, ../repositories/auth_repository.dart (+7 more)

### Community 40 - "Community 40"
Cohesion: 0.14
Nodes (14): AdminShell, _AdminShellState, RegisterScreen, _RegisterScreenState, ConsumerStatefulWidget, _Step1State, Step1WhoAreYou, Step6Photos (+6 more)

### Community 41 - "Community 41"
Cohesion: 0.12
Nodes (15): fromFirestore, id, InterestModel, isAccepted, isPending, isRejected, message, receiverId (+7 more)

### Community 42 - "Community 42"
Cohesion: 0.13
Nodes (14): @pragma, buildPayload, _db, deleteToken, FcmService, _firebaseMessagingBackgroundHandler, getToken, initialize (+6 more)

### Community 43 - "Community 43"
Cohesion: 0.22
Nodes (8): createState, dispose, _emailController, _formKey, _obscurePassword, _passwordController, ../../core/config/dev_config.dart, FormState

### Community 44 - "Community 44"
Cohesion: 0.14
Nodes (14): astrologerId, AstrologerProfileScreen, _bookingBar, build, _chips, _comingSoonSection, _headerBackground, _reviewsList (+6 more)

### Community 45 - "Community 45"
Cohesion: 0.20
Nodes (9): build, _buildSuccess, createState, dispose, _emailController, _formKey, _isLoading, _sent (+1 more)

### Community 46 - "Community 46"
Cohesion: 0.15
Nodes (13): _Bubble, _controller, createState, dispose, extra, initState, isMine, message (+5 more)

### Community 47 - "Community 47"
Cohesion: 0.13
Nodes (14): AstrologerService, createAccount, createRequest, _db, getAccount, updateAccount, updateRequestStatus, watchAccount (+6 more)

### Community 48 - "Community 48"
Cohesion: 0.06
Nodes (38): copyWith, ../../../models/interest_request_model.dart, direction, id, InterestRequest, isAccepted, isIncoming, profileId (+30 more)

### Community 49 - "Community 49"
Cohesion: 0.15
Nodes (12): astrologer, _buildTopBanner, color, _fallbackBanner, gradient, icon, iconColor, label (+4 more)

### Community 50 - "Community 50"
Cohesion: 0.08
Nodes (36): AdminApprovalsScreen, _ApprovalCard, build, icon, _InfoChip, label, profile, _reject (+28 more)

### Community 51 - "Community 51"
Cohesion: 0.17
Nodes (14): AstrologersTab, build, build, _ConnectAstrologerSheet, ../core/data/sample_astrologers.dart, astrologersProvider, list, null (+6 more)

### Community 52 - "Community 52"
Cohesion: 0.16
Nodes (13): AsyncValue, ../../models/interest_model.dart, acceptInterest, build, InterestNotifier, receivedInterestsProvider, rejectInterest, sendInterest (+5 more)

### Community 53 - "Community 53"
Cohesion: 0.18
Nodes (11): Animation, AnimationController, build, _controller, createState, dispose, _fadeAnim, initState (+3 more)

### Community 54 - "Community 54"
Cohesion: 0.15
Nodes (13): RangeValues, _ageRange, build, _buildDropdown, _caste, createState, _education, onNext (+5 more)

### Community 55 - "Community 55"
Cohesion: 0.13
Nodes (14): createProfile, _firestore, getProfile, getProfileByUserId, incrementViewCount, ProfileRepository, searchProfiles, _storage (+6 more)

### Community 56 - "Community 56"
Cohesion: 0.15
Nodes (13): typedef, about, age, AppValidators, confirmPassword, email, name, otp (+5 more)

### Community 57 - "Community 57"
Cohesion: 0.15
Nodes (12): ../constants/app_constants.dart, calculateAge, calculateDasaBalance, calculateKaranam, calculateLagnam, calculateNakshatra, calculateRasi, calculateYogam (+4 more)

### Community 58 - "Community 58"
Cohesion: 0.14
Nodes (13): build, createState, dispose, _formKey, isLoading, _mobileController, _nameController, onNext (+5 more)

### Community 59 - "Community 59"
Cohesion: 0.04
Nodes (45): _client, CloudinaryStorageService, cloudName, deleteFile, deleteProfilePhotos, _endpoint, maxRetries, _send (+37 more)

### Community 60 - "Community 60"
Cohesion: 0.15
Nodes (12): Map, body, createdAt, data, fromFirestore, id, isRead, NotificationModel (+4 more)

### Community 61 - "Community 61"
Cohesion: 0.20
Nodes (11): auth_provider.dart, build, markRead, notificationNotifierProvider, notificationsProvider, notifs, userId, watch (+3 more)

### Community 62 - "Community 62"
Cohesion: 0.25
Nodes (7): myUid, thread, _ThreadTile, _when, ChatThread, ../../models/chat_model.dart, ../../providers/chat_provider.dart

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
Cohesion: 0.20
Nodes (9): cancelled, code, from, message, toString, userCancelled, package:firebase_auth/firebase_auth.dart, package:flutter/services.dart (+1 more)

### Community 67 - "Community 67"
Cohesion: 0.18
Nodes (11): amount, AstrologerBooking, BookingStatus, BookingStatusX, dateTime, id, mode, serviceName (+3 more)

### Community 68 - "Community 68"
Cohesion: 0.29
Nodes (12): ConsumerState, discoverProvider, matchGenderProvider, Route /subscription, _applyFilters, _DiscoverTabState, build, _buildPremiumBanner (+4 more)

### Community 69 - "Community 69"
Cohesion: 0.15
Nodes (13): build, createState, initState, _loading, onChanged, PrivacySettingsScreen, _PrivacyState, _PrivacyTile (+5 more)

### Community 70 - "Community 70"
Cohesion: 0.18
Nodes (10): CloudinaryResponse, errorMessage, format, fromJsonString, publicId, resourceType, secureUrl, version (+2 more)

### Community 71 - "Community 71"
Cohesion: 0.18
Nodes (10): bool get, checks, computeProfileCompletion, filled, isComplete, missing, missingFields, percent (+2 more)

### Community 72 - "Community 72"
Cohesion: 0.20
Nodes (9): build, gradient, height, isLoading, onPressed, text, width, double? (+1 more)

### Community 73 - "Community 73"
Cohesion: 0.17
Nodes (11): build, enabled, isRequired, items, label, onChanged, prefixIcon, SearchableField (+3 more)

### Community 74 - "Community 74"
Cohesion: 0.20
Nodes (9): core/theme/app_theme.dart, firebase_options.dart, _localizationsDelegates, main, package:flutter_localizations/flutter_localizations.dart, package:jothida_matrimony/l10n/app_localizations.dart, router/app_router.dart, ../screens/settings/language_screen.dart (+1 more)

### Community 75 - "Community 75"
Cohesion: 0.18
Nodes (10): 1. Create the Firebase project, 2. Generate the config files, 3. Enable Authentication providers, 4. Create Firestore, 5. Storage (profile photos, horoscope PDFs, ID proof), 6. Switch off demo mode, 7. End-to-end flow (what to expect), 8. Troubleshooting "Google Sign-In failed" (+2 more)

### Community 76 - "Community 76"
Cohesion: 0.31
Nodes (9): build, ChatListScreen, build, ChatScreen, _ChatScreenState, chatMessagesProvider, chatThreadProvider, myChatThreadsProvider (+1 more)

### Community 77 - "Community 77"
Cohesion: 0.20
Nodes (10): @Deprecated, AstrologerOnboardingScreen, GradientButton, StatelessWidget, _AstrologerCard, _FeaturedCard, _ServiceAction, _BannerSlide (+2 more)

### Community 78 - "Community 78"
Cohesion: 0.25
Nodes (7): package:shared_preferences/shared_preferences.dart, build, code, _kLocaleKey, prefs, setLocale, supportedLocales

### Community 79 - "Community 79"
Cohesion: 0.20
Nodes (9): package:cloud_firestore/cloud_firestore.dart, acceptInterest, _firestore, getInterestBetweenProfiles, InterestRepository, rejectInterest, sendInterest, watchReceivedInterests (+1 more)

### Community 80 - "Community 80"
Cohesion: 0.09
Nodes (22): ../../core/theme/app_colors.dart, ../../core/utils/profile_completion.dart, package:flutter/material.dart, package:flutter_test/flutter_test.dart, package:image_picker/image_picker.dart, package:jothida_matrimony/main.dart, package:percent_indicator/circular_percent_indicator.dart, ../../providers/profile_provider.dart (+14 more)

### Community 81 - "Community 81"
Cohesion: 0.22
Nodes (8): CloudinaryUploadException, isRetryable, message, statusCode, toString, AuthException, Exception, int?

### Community 82 - "Community 82"
Cohesion: 0.14
Nodes (12): child, createState, _index, _routes, android, DefaultFirebaseOptions, package:firebase_core/firebase_core.dart, package:flutter/foundation.dart (+4 more)

### Community 83 - "Community 83"
Cohesion: 0.13
Nodes (14): ../../core/theme/app_text_styles.dart, build, createState, _gender, _genderCard, onNext, _profileFor, _profileForOptions (+6 more)

### Community 84 - "Community 84"
Cohesion: 0.22
Nodes (9): build, profileCreationProvider, _saveAndNext, _saveAndNext, _autoGenerate, _saveAndNext, _saveAndNext, _saveAndNext (+1 more)

### Community 85 - "Community 85"
Cohesion: 0.22
Nodes (8): 1. Current State Assessment, 2. Migration Plan (step-by-step), 3. Open questions before Step 1, Good news: the Firebase architecture already exists, Jothida Matrimony — Firebase Production Migration Plan, What is missing entirely (not started), What is mock / demo / placeholder right now, What's already solid (verified)

### Community 86 - "Community 86"
Cohesion: 0.20
Nodes (11): ../../providers/locale_provider.dart, localeProvider, build, _choose, LanguageScreen, _LanguageTile, onTap, selected (+3 more)

### Community 87 - "Community 87"
Cohesion: 0.24
Nodes (10): AstrologerRegisterScreen, _AstrologerRegisterScreenState, initState, _submit, _loadSettings, _submitProfile, loadFromFirestore, firebaseAuthStreamProvider (+2 more)

### Community 88 - "Community 88"
Cohesion: 0.29
Nodes (6): Astrologer, astrologer, _AstrologerCard, _intro, _section, ../../../providers/astrologer_provider.dart

### Community 89 - "Community 89"
Cohesion: 0.29
Nodes (6): ../core/data/sample_profiles.dart, build, byId, discover, kDemoUserId, upsert

### Community 90 - "Community 90"
Cohesion: 0.29
Nodes (6): a, reviews, s, sampleAstrologers, services, ../../../models/astrologer_model.dart

### Community 91 - "Community 91"
Cohesion: 0.29
Nodes (6): _build, featured, now, sampleProfiles, ../../models/profile_model.dart, required int prefMaxAge,
  bool

### Community 92 - "Community 92"
Cohesion: 0.29
Nodes (6): ⚠️ API secret, Cloudinary Setup — Profile Media Uploads, Current configuration, How it works, Retry & progress, Verifying the upload preset

### Community 93 - "Community 93"
Cohesion: 0.19
Nodes (15): List, Notifier, _save, DemoAstrologerRequestsNotifier, DemoProfilesNotifier, demoProfilesProvider, myDemoProfileIdProvider, NotificationNotifier (+7 more)

### Community 94 - "Community 94"
Cohesion: 0.33
Nodes (6): LoginScreen, _LoginScreenState, OtpScreen, _OtpScreenState, _resend, otpNotifierProvider

### Community 95 - "Community 95"
Cohesion: 0.40
Nodes (6): build, HomeScreen, _HomeScreenState, MaterialPageRoute, currentUserProvider, unreadNotificationCountProvider

### Community 96 - "Community 96"
Cohesion: 0.40
Nodes (6): build, JothidaMatrimonyApp, Locale?, initialLocaleProvider, LocaleNotifier, appRouterProvider

### Community 97 - "Community 97"
Cohesion: 0.40
Nodes (6): build, _lockedView, MatchDetailsScreen, _MatchDetailsScreenState, profileByIdProvider, isMatchedProvider

### Community 98 - "Community 98"
Cohesion: 0.15
Nodes (13): AstrologerDashboardScreen, _AvailabilitySection, _BookingsSection, build, _OverviewSection, _RequestsSection, _ReviewsSection, astrologerAvailabilityProvider (+5 more)

### Community 104 - "Community 104"
Cohesion: 0.33
Nodes (5): ../../models/notification_model.dart, ../../../providers/notification_provider.dart, _timeAgo, _typeColor, _typeIcon

### Community 105 - "Community 105"
Cohesion: 0.40
Nodes (5): AccountTypeScreen, _AccountTypeScreenState, SingleTickerProviderStateMixin, State, StatefulWidget

### Community 106 - "Community 106"
Cohesion: 0.50
Nodes (4): ForgotPasswordScreen, _ForgotPasswordScreenState, _send, authServiceProvider

## Knowledge Gaps
- **1245 isolated node(s):** `kBypassAuth`, `AppConstants`, `appName`, `appTagline`, `appVersion` (+1240 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `dateTime` connect `Community 67` to `Community 0`, `Community 3`, `Community 35`, `Community 9`, `Community 41`, `Community 11`, `Community 60`, `Community 48`, `Community 17`, `Community 16`, `Community 19`, `Community 28`, `Community 30`?**
  _High betweenness centrality (0.070) - this node is a cross-community bridge._
- **Why does `AuthException` connect `Community 81` to `Community 66`?**
  _High betweenness centrality (0.010) - this node is a cross-community bridge._
- **Why does `ProfileModel` connect `Community 50` to `Community 0`, `Community 8`, `Community 15`?**
  _High betweenness centrality (0.008) - this node is a cross-community bridge._
- **What connects `kBypassAuth`, `AppConstants`, `appName` to the rest of the system?**
  _1245 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.024390243902439025 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.025 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.09523809523809523 - nodes in this community are weakly interconnected._