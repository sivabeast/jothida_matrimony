import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ta.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ta')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Jothida Matrimony'**
  String get appTitle;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Find Your Perfect Match'**
  String get appTagline;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get chooseLanguage;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageTamil.
  ///
  /// In en, this message translates to:
  /// **'தமிழ்'**
  String get languageTamil;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get tryAgain;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get viewAll;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @filters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filters;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming Soon'**
  String get comingSoon;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @notSpecified.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get notSpecified;

  /// No description provided for @notAvailable.
  ///
  /// In en, this message translates to:
  /// **'Not Available'**
  String get notAvailable;

  /// No description provided for @fieldRequired.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get fieldRequired;

  /// No description provided for @invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get invalidEmail;

  /// No description provided for @invalidPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid mobile number'**
  String get invalidPhone;

  /// No description provided for @invalidOtp.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid OTP'**
  String get invalidOtp;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get passwordTooShort;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get somethingWentWrong;

  /// No description provided for @noInternet.
  ///
  /// In en, this message translates to:
  /// **'No internet connection'**
  String get noInternet;

  /// No description provided for @savedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Saved successfully'**
  String get savedSuccessfully;

  /// No description provided for @updatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Updated successfully'**
  String get updatedSuccessfully;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get welcomeBack;

  /// No description provided for @signInToContinue.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue'**
  String get signInToContinue;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @mobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Mobile Number'**
  String get mobileNumber;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullName;

  /// No description provided for @sendOtp.
  ///
  /// In en, this message translates to:
  /// **'Send OTP'**
  String get sendOtp;

  /// No description provided for @verifyOtp.
  ///
  /// In en, this message translates to:
  /// **'Verify OTP'**
  String get verifyOtp;

  /// No description provided for @enterOtp.
  ///
  /// In en, this message translates to:
  /// **'Enter OTP'**
  String get enterOtp;

  /// No description provided for @otpSentTo.
  ///
  /// In en, this message translates to:
  /// **'OTP sent to {number}'**
  String otpSentTo(String number);

  /// No description provided for @resendOtp.
  ///
  /// In en, this message translates to:
  /// **'Resend OTP'**
  String get resendOtp;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signIn;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signUp;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccount;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPassword;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetPassword;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @dontHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? '**
  String get dontHaveAccount;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? '**
  String get alreadyHaveAccount;

  /// No description provided for @astrologerPortal.
  ///
  /// In en, this message translates to:
  /// **'Astrologer Portal'**
  String get astrologerPortal;

  /// No description provided for @orLabel.
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get orLabel;

  /// No description provided for @chooseAccountType.
  ///
  /// In en, this message translates to:
  /// **'Choose Account Type'**
  String get chooseAccountType;

  /// No description provided for @matrimonyUser.
  ///
  /// In en, this message translates to:
  /// **'Matrimony User'**
  String get matrimonyUser;

  /// No description provided for @findLifePartner.
  ///
  /// In en, this message translates to:
  /// **'Find your life partner'**
  String get findLifePartner;

  /// No description provided for @astrologerAccount.
  ///
  /// In en, this message translates to:
  /// **'Astrologer'**
  String get astrologerAccount;

  /// No description provided for @offerConsultations.
  ///
  /// In en, this message translates to:
  /// **'Offer consultations to members'**
  String get offerConsultations;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @discover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get discover;

  /// No description provided for @matches.
  ///
  /// In en, this message translates to:
  /// **'Matches'**
  String get matches;

  /// No description provided for @astrologers.
  ///
  /// In en, this message translates to:
  /// **'Astrologers'**
  String get astrologers;

  /// No description provided for @interests.
  ///
  /// In en, this message translates to:
  /// **'Interests'**
  String get interests;

  /// No description provided for @alerts.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get alerts;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @brides.
  ///
  /// In en, this message translates to:
  /// **'Brides'**
  String get brides;

  /// No description provided for @grooms.
  ///
  /// In en, this message translates to:
  /// **'Grooms'**
  String get grooms;

  /// No description provided for @sendInterest.
  ///
  /// In en, this message translates to:
  /// **'Send Interest'**
  String get sendInterest;

  /// No description provided for @interestSent.
  ///
  /// In en, this message translates to:
  /// **'Interest Sent'**
  String get interestSent;

  /// No description provided for @noProfilesFound.
  ///
  /// In en, this message translates to:
  /// **'No profiles found'**
  String get noProfilesFound;

  /// No description provided for @recommendedMatches.
  ///
  /// In en, this message translates to:
  /// **'Recommended Matches'**
  String get recommendedMatches;

  /// No description provided for @viewProfile.
  ///
  /// In en, this message translates to:
  /// **'View Profile'**
  String get viewProfile;

  /// No description provided for @years.
  ///
  /// In en, this message translates to:
  /// **'yrs'**
  String get years;

  /// No description provided for @age.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get age;

  /// No description provided for @height.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get height;

  /// No description provided for @weight.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get weight;

  /// No description provided for @location.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// No description provided for @education.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get education;

  /// No description provided for @occupation.
  ///
  /// In en, this message translates to:
  /// **'Occupation'**
  String get occupation;

  /// No description provided for @annualIncome.
  ///
  /// In en, this message translates to:
  /// **'Annual Income'**
  String get annualIncome;

  /// No description provided for @religion.
  ///
  /// In en, this message translates to:
  /// **'Religion'**
  String get religion;

  /// No description provided for @caste.
  ///
  /// In en, this message translates to:
  /// **'Caste'**
  String get caste;

  /// No description provided for @subCaste.
  ///
  /// In en, this message translates to:
  /// **'Sub Caste'**
  String get subCaste;

  /// No description provided for @maritalStatus.
  ///
  /// In en, this message translates to:
  /// **'Marital Status'**
  String get maritalStatus;

  /// No description provided for @motherTongue.
  ///
  /// In en, this message translates to:
  /// **'Mother Tongue'**
  String get motherTongue;

  /// No description provided for @gender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get gender;

  /// No description provided for @dateOfBirth.
  ///
  /// In en, this message translates to:
  /// **'Date of Birth'**
  String get dateOfBirth;

  /// No description provided for @city.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get city;

  /// No description provided for @state.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get state;

  /// No description provided for @country.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get country;

  /// No description provided for @received.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get received;

  /// No description provided for @sent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sent;

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @decline.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get decline;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @accepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get accepted;

  /// No description provided for @rejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejected;

  /// No description provided for @viewCompatibility.
  ///
  /// In en, this message translates to:
  /// **'View Compatibility'**
  String get viewCompatibility;

  /// No description provided for @interestAccepted.
  ///
  /// In en, this message translates to:
  /// **'Interest accepted'**
  String get interestAccepted;

  /// No description provided for @acceptInterest.
  ///
  /// In en, this message translates to:
  /// **'Accept Interest'**
  String get acceptInterest;

  /// No description provided for @interestRejected.
  ///
  /// In en, this message translates to:
  /// **'Interest Rejected'**
  String get interestRejected;

  /// No description provided for @noInterestsYet.
  ///
  /// In en, this message translates to:
  /// **'No interests yet'**
  String get noInterestsYet;

  /// No description provided for @interestSentSuccess.
  ///
  /// In en, this message translates to:
  /// **'Interest sent successfully!'**
  String get interestSentSuccess;

  /// No description provided for @matchDetails.
  ///
  /// In en, this message translates to:
  /// **'Match Details'**
  String get matchDetails;

  /// No description provided for @match.
  ///
  /// In en, this message translates to:
  /// **'Match'**
  String get match;

  /// No description provided for @compatibilitySummary.
  ///
  /// In en, this message translates to:
  /// **'Compatibility Summary'**
  String get compatibilitySummary;

  /// No description provided for @marriageCompatibility.
  ///
  /// In en, this message translates to:
  /// **'Marriage Compatibility (Porutham)'**
  String get marriageCompatibility;

  /// No description provided for @poruthamMatched.
  ///
  /// In en, this message translates to:
  /// **'{matched} / {total} Poruthams matched'**
  String poruthamMatched(int matched, int total);

  /// No description provided for @connectAstrologer.
  ///
  /// In en, this message translates to:
  /// **'Connect Astrologer'**
  String get connectAstrologer;

  /// No description provided for @compatibilityLocked.
  ///
  /// In en, this message translates to:
  /// **'Compatibility is locked'**
  String get compatibilityLocked;

  /// No description provided for @viewContact.
  ///
  /// In en, this message translates to:
  /// **'View Contact'**
  String get viewContact;

  /// No description provided for @horoscopeMatch.
  ///
  /// In en, this message translates to:
  /// **'Horoscope Match'**
  String get horoscopeMatch;

  /// No description provided for @myProfile.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get myProfile;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @createProfile.
  ///
  /// In en, this message translates to:
  /// **'Create Profile'**
  String get createProfile;

  /// No description provided for @completeProfile.
  ///
  /// In en, this message translates to:
  /// **'Complete your profile'**
  String get completeProfile;

  /// No description provided for @personalDetails.
  ///
  /// In en, this message translates to:
  /// **'Personal Details'**
  String get personalDetails;

  /// No description provided for @horoscopeDetails.
  ///
  /// In en, this message translates to:
  /// **'Horoscope Details'**
  String get horoscopeDetails;

  /// No description provided for @familyDetails.
  ///
  /// In en, this message translates to:
  /// **'Family Details'**
  String get familyDetails;

  /// No description provided for @partnerPreferences.
  ///
  /// In en, this message translates to:
  /// **'Partner Preferences'**
  String get partnerPreferences;

  /// No description provided for @subscriptionPlans.
  ///
  /// In en, this message translates to:
  /// **'Subscription Plans'**
  String get subscriptionPlans;

  /// No description provided for @upgradeToPremium.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Premium'**
  String get upgradeToPremium;

  /// No description provided for @premiumSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get unlimited access & free astrologer consultations'**
  String get premiumSubtitle;

  /// No description provided for @married.
  ///
  /// In en, this message translates to:
  /// **'Married'**
  String get married;

  /// No description provided for @aboutMe.
  ///
  /// In en, this message translates to:
  /// **'About Me'**
  String get aboutMe;

  /// No description provided for @basicInformation.
  ///
  /// In en, this message translates to:
  /// **'Basic Information'**
  String get basicInformation;

  /// No description provided for @religionCommunity.
  ///
  /// In en, this message translates to:
  /// **'Religion & Community'**
  String get religionCommunity;

  /// No description provided for @educationCareer.
  ///
  /// In en, this message translates to:
  /// **'Education & Career'**
  String get educationCareer;

  /// No description provided for @familyTree.
  ///
  /// In en, this message translates to:
  /// **'Family Tree'**
  String get familyTree;

  /// No description provided for @father.
  ///
  /// In en, this message translates to:
  /// **'Father'**
  String get father;

  /// No description provided for @mother.
  ///
  /// In en, this message translates to:
  /// **'Mother'**
  String get mother;

  /// No description provided for @brothers.
  ///
  /// In en, this message translates to:
  /// **'Brothers'**
  String get brothers;

  /// No description provided for @sisters.
  ///
  /// In en, this message translates to:
  /// **'Sisters'**
  String get sisters;

  /// No description provided for @familyType.
  ///
  /// In en, this message translates to:
  /// **'Family Type'**
  String get familyType;

  /// No description provided for @familyStatus.
  ///
  /// In en, this message translates to:
  /// **'Family Status'**
  String get familyStatus;

  /// No description provided for @jointFamily.
  ///
  /// In en, this message translates to:
  /// **'Joint Family'**
  String get jointFamily;

  /// No description provided for @nuclearFamily.
  ///
  /// In en, this message translates to:
  /// **'Nuclear Family'**
  String get nuclearFamily;

  /// No description provided for @familyDetailsNotAdded.
  ///
  /// In en, this message translates to:
  /// **'Family details not added'**
  String get familyDetailsNotAdded;

  /// No description provided for @addFamilyDetails.
  ///
  /// In en, this message translates to:
  /// **'Add Family Details'**
  String get addFamilyDetails;

  /// No description provided for @horoscope.
  ///
  /// In en, this message translates to:
  /// **'Horoscope'**
  String get horoscope;

  /// No description provided for @rasi.
  ///
  /// In en, this message translates to:
  /// **'Rasi'**
  String get rasi;

  /// No description provided for @nakshatra.
  ///
  /// In en, this message translates to:
  /// **'Nakshatra'**
  String get nakshatra;

  /// No description provided for @lagnam.
  ///
  /// In en, this message translates to:
  /// **'Lagnam'**
  String get lagnam;

  /// No description provided for @birthTime.
  ///
  /// In en, this message translates to:
  /// **'Birth Time'**
  String get birthTime;

  /// No description provided for @birthPlace.
  ///
  /// In en, this message translates to:
  /// **'Birth Place'**
  String get birthPlace;

  /// No description provided for @dosham.
  ///
  /// In en, this message translates to:
  /// **'Dosham'**
  String get dosham;

  /// No description provided for @freePlan.
  ///
  /// In en, this message translates to:
  /// **'Free Plan'**
  String get freePlan;

  /// No description provided for @premiumPlan.
  ///
  /// In en, this message translates to:
  /// **'Premium Plan'**
  String get premiumPlan;

  /// No description provided for @basicPlan.
  ///
  /// In en, this message translates to:
  /// **'Basic Plan'**
  String get basicPlan;

  /// No description provided for @mediumPlan.
  ///
  /// In en, this message translates to:
  /// **'Medium Plan'**
  String get mediumPlan;

  /// No description provided for @monthlySubscription.
  ///
  /// In en, this message translates to:
  /// **'Monthly Subscription'**
  String get monthlySubscription;

  /// No description provided for @currentPlan.
  ///
  /// In en, this message translates to:
  /// **'Current Plan'**
  String get currentPlan;

  /// No description provided for @choosePlan.
  ///
  /// In en, this message translates to:
  /// **'Choose a Plan'**
  String get choosePlan;

  /// No description provided for @subscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get subscribe;

  /// No description provided for @daysRemaining.
  ///
  /// In en, this message translates to:
  /// **'{days} days remaining'**
  String daysRemaining(int days);

  /// No description provided for @rating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get rating;

  /// No description provided for @experience.
  ///
  /// In en, this message translates to:
  /// **'Experience'**
  String get experience;

  /// No description provided for @reviews.
  ///
  /// In en, this message translates to:
  /// **'Reviews'**
  String get reviews;

  /// No description provided for @ratingsAndReviews.
  ///
  /// In en, this message translates to:
  /// **'Ratings & Reviews'**
  String get ratingsAndReviews;

  /// No description provided for @rateAstrologer.
  ///
  /// In en, this message translates to:
  /// **'Rate Astrologer'**
  String get rateAstrologer;

  /// No description provided for @editYourRating.
  ///
  /// In en, this message translates to:
  /// **'Edit Your Rating'**
  String get editYourRating;

  /// No description provided for @writeReview.
  ///
  /// In en, this message translates to:
  /// **'Write a Review'**
  String get writeReview;

  /// No description provided for @reviewOptional.
  ///
  /// In en, this message translates to:
  /// **'Review (optional)'**
  String get reviewOptional;

  /// No description provided for @submitReview.
  ///
  /// In en, this message translates to:
  /// **'Submit Review'**
  String get submitReview;

  /// No description provided for @noReviewsYet.
  ///
  /// In en, this message translates to:
  /// **'No reviews yet. Be the first to rate.'**
  String get noReviewsYet;

  /// No description provided for @completeProfileToRate.
  ///
  /// In en, this message translates to:
  /// **'Complete your profile to rate astrologers.'**
  String get completeProfileToRate;

  /// No description provided for @ratingSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Thank you! Your rating has been submitted.'**
  String get ratingSubmitted;

  /// No description provided for @ratingUpdated.
  ///
  /// In en, this message translates to:
  /// **'Your rating has been updated.'**
  String get ratingUpdated;

  /// No description provided for @couldNotSubmitRating.
  ///
  /// In en, this message translates to:
  /// **'Could not submit your rating. Please try again.'**
  String get couldNotSubmitRating;

  /// No description provided for @shareYourExperience.
  ///
  /// In en, this message translates to:
  /// **'Share your experience…'**
  String get shareYourExperience;

  /// No description provided for @selectStarRating.
  ///
  /// In en, this message translates to:
  /// **'Please select a star rating'**
  String get selectStarRating;

  /// No description provided for @servicesOffered.
  ///
  /// In en, this message translates to:
  /// **'Services Offered'**
  String get servicesOffered;

  /// No description provided for @languages.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get languages;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @verifiedAstrologer.
  ///
  /// In en, this message translates to:
  /// **'Verified Astrologer'**
  String get verifiedAstrologer;

  /// No description provided for @consultation.
  ///
  /// In en, this message translates to:
  /// **'Consultation'**
  String get consultation;

  /// No description provided for @bookConsultation.
  ///
  /// In en, this message translates to:
  /// **'Book Consultation'**
  String get bookConsultation;

  /// No description provided for @contactDetails.
  ///
  /// In en, this message translates to:
  /// **'Contact Details'**
  String get contactDetails;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @call.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get call;

  /// No description provided for @whatsapp.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get whatsapp;

  /// No description provided for @contactLocked.
  ///
  /// In en, this message translates to:
  /// **'Contact unlocks after your interest is accepted'**
  String get contactLocked;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @noNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get noNotifications;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @privacySettings.
  ///
  /// In en, this message translates to:
  /// **'Privacy Settings'**
  String get privacySettings;

  /// No description provided for @helpSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get helpSupport;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @termsConditions.
  ///
  /// In en, this message translates to:
  /// **'Terms & Conditions'**
  String get termsConditions;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @preferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferences;

  /// No description provided for @supportAndLegal.
  ///
  /// In en, this message translates to:
  /// **'Support & Legal'**
  String get supportAndLegal;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get logout;

  /// No description provided for @signOutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to sign out?'**
  String get signOutConfirm;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete your account and all data'**
  String get deleteAccountSubtitle;

  /// No description provided for @deleteAccountWarning.
  ///
  /// In en, this message translates to:
  /// **'This action is permanent and cannot be undone.\nAll your profile data, photos, interests, horoscope details and account information will be permanently deleted.'**
  String get deleteAccountWarning;

  /// No description provided for @couldNotDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Could not delete your account. Please try again.'**
  String get couldNotDeleteAccount;

  /// No description provided for @viewPhoto.
  ///
  /// In en, this message translates to:
  /// **'View Photo'**
  String get viewPhoto;

  /// No description provided for @changePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change Photo'**
  String get changePhoto;

  /// No description provided for @uploadPhoto.
  ///
  /// In en, this message translates to:
  /// **'Upload Photo'**
  String get uploadPhoto;

  /// No description provided for @removePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove Photo'**
  String get removePhoto;

  /// No description provided for @removePhotoConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove your profile photo?'**
  String get removePhotoConfirm;

  /// No description provided for @photoUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile photo updated'**
  String get photoUpdated;

  /// No description provided for @photoRemoved.
  ///
  /// In en, this message translates to:
  /// **'Photo removed'**
  String get photoRemoved;

  /// No description provided for @couldNotUpdatePhoto.
  ///
  /// In en, this message translates to:
  /// **'Could not update photo. Please try again.'**
  String get couldNotUpdatePhoto;

  /// No description provided for @couldNotRemovePhoto.
  ///
  /// In en, this message translates to:
  /// **'Could not remove photo. Please try again.'**
  String get couldNotRemovePhoto;

  /// No description provided for @family.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get family;

  /// No description provided for @noProfileYet.
  ///
  /// In en, this message translates to:
  /// **'No profile yet'**
  String get noProfileYet;

  /// No description provided for @profileUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Profile unavailable'**
  String get profileUnavailable;

  /// No description provided for @memberDetailsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This member\'s details could not be loaded.'**
  String get memberDetailsUnavailable;

  /// No description provided for @couldNotLoadFamilyDetails.
  ///
  /// In en, this message translates to:
  /// **'Could not load family details'**
  String get couldNotLoadFamilyDetails;

  /// No description provided for @addFamilyFromPersonalDetails.
  ///
  /// In en, this message translates to:
  /// **'Add your family details from Personal Details to see your family tree here.'**
  String get addFamilyFromPersonalDetails;

  /// No description provided for @memberNoFamilyDetails.
  ///
  /// In en, this message translates to:
  /// **'{name} hasn\'t shared family details yet.'**
  String memberNoFamilyDetails(String name);

  /// No description provided for @familyStatusRich.
  ///
  /// In en, this message translates to:
  /// **'Rich'**
  String get familyStatusRich;

  /// No description provided for @familyStatusUpperMiddle.
  ///
  /// In en, this message translates to:
  /// **'Upper Middle Class'**
  String get familyStatusUpperMiddle;

  /// No description provided for @familyStatusMiddle.
  ///
  /// In en, this message translates to:
  /// **'Middle Class'**
  String get familyStatusMiddle;

  /// No description provided for @familyStatusLowerMiddle.
  ///
  /// In en, this message translates to:
  /// **'Lower Middle Class'**
  String get familyStatusLowerMiddle;

  /// No description provided for @familyStatusLower.
  ///
  /// In en, this message translates to:
  /// **'Lower Class'**
  String get familyStatusLower;

  /// No description provided for @whoCreatingAccountFor.
  ///
  /// In en, this message translates to:
  /// **'Who are you creating\nan account for?'**
  String get whoCreatingAccountFor;

  /// No description provided for @chooseHowToUseApp.
  ///
  /// In en, this message translates to:
  /// **'Choose how you want to use the app'**
  String get chooseHowToUseApp;

  /// No description provided for @pressBackToExit.
  ///
  /// In en, this message translates to:
  /// **'Press back again to exit'**
  String get pressBackToExit;

  /// No description provided for @signInFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign in failed. Please check your credentials and try again.'**
  String get signInFailed;

  /// No description provided for @googleSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Google Sign-In failed. Please try again.'**
  String get googleSignInFailed;

  /// No description provided for @astrologerSignInHere.
  ///
  /// In en, this message translates to:
  /// **'Are you an Astrologer? Sign in here'**
  String get astrologerSignInHere;

  /// No description provided for @couldNotLoadReviews.
  ///
  /// In en, this message translates to:
  /// **'Could not load reviews.'**
  String get couldNotLoadReviews;

  /// No description provided for @certificates.
  ///
  /// In en, this message translates to:
  /// **'Certificates'**
  String get certificates;

  /// No description provided for @astrologerNotFound.
  ///
  /// In en, this message translates to:
  /// **'Astrologer not found'**
  String get astrologerNotFound;

  /// No description provided for @member.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get member;

  /// No description provided for @noReceivedInterests.
  ///
  /// In en, this message translates to:
  /// **'No interests received yet'**
  String get noReceivedInterests;

  /// No description provided for @noSentInterests.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t sent any interests yet'**
  String get noSentInterests;

  /// No description provided for @noAcceptedInterests.
  ///
  /// In en, this message translates to:
  /// **'No accepted interests yet'**
  String get noAcceptedInterests;

  /// No description provided for @noRejectedInterests.
  ///
  /// In en, this message translates to:
  /// **'No rejected interests'**
  String get noRejectedInterests;

  /// No description provided for @couldntLoadInterests.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load interests'**
  String get couldntLoadInterests;

  /// No description provided for @checkConnectionRetry.
  ///
  /// In en, this message translates to:
  /// **'Please check your connection and try again.'**
  String get checkConnectionRetry;

  /// No description provided for @interestStartHint.
  ///
  /// In en, this message translates to:
  /// **'Send or receive an interest to get started.'**
  String get interestStartHint;

  /// No description provided for @interestDeclined.
  ///
  /// In en, this message translates to:
  /// **'Interest declined'**
  String get interestDeclined;

  /// No description provided for @interestAcceptedMatch.
  ///
  /// In en, this message translates to:
  /// **'It\'s a match! Interest accepted 🎉'**
  String get interestAcceptedMatch;

  /// No description provided for @profileUnavailableMatch.
  ///
  /// In en, this message translates to:
  /// **'Profile unavailable for this match.'**
  String get profileUnavailableMatch;

  /// No description provided for @horoscopeUnavailableMember.
  ///
  /// In en, this message translates to:
  /// **'Horoscope match unavailable for this member.'**
  String get horoscopeUnavailableMember;

  /// No description provided for @sentAcceptedHint.
  ///
  /// In en, this message translates to:
  /// **'Accepted — open the Accepted tab to view contact.'**
  String get sentAcceptedHint;

  /// No description provided for @interestDeclinedStatus.
  ///
  /// In en, this message translates to:
  /// **'This interest was declined.'**
  String get interestDeclinedStatus;

  /// No description provided for @waitingForResponse.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a response…'**
  String get waitingForResponse;

  /// No description provided for @bookMatchAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Book Match Analysis'**
  String get bookMatchAnalysis;

  /// No description provided for @submitRequest.
  ///
  /// In en, this message translates to:
  /// **'Submit Request'**
  String get submitRequest;

  /// No description provided for @sending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get sending;

  /// No description provided for @reassignQuestion.
  ///
  /// In en, this message translates to:
  /// **'If the astrologer doesn\'t respond within 24 hours'**
  String get reassignQuestion;

  /// No description provided for @reassignWaitOnly.
  ///
  /// In en, this message translates to:
  /// **'Wait only for this astrologer'**
  String get reassignWaitOnly;

  /// No description provided for @reassignWaitOnlyDesc.
  ///
  /// In en, this message translates to:
  /// **'Keep waiting for this astrologer. You can take action manually later.'**
  String get reassignWaitOnlyDesc;

  /// No description provided for @reassignChooseLater.
  ///
  /// In en, this message translates to:
  /// **'Let me choose another astrologer later'**
  String get reassignChooseLater;

  /// No description provided for @reassignChooseLaterDesc.
  ///
  /// In en, this message translates to:
  /// **'We\'ll notify you so you can pick a new astrologer yourself.'**
  String get reassignChooseLaterDesc;

  /// No description provided for @reassignAllowAdmin.
  ///
  /// In en, this message translates to:
  /// **'Allow admin to assign another astrologer'**
  String get reassignAllowAdmin;

  /// No description provided for @reassignAllowAdminDesc.
  ///
  /// In en, this message translates to:
  /// **'Our team will assign another available astrologer for you.'**
  String get reassignAllowAdminDesc;

  /// No description provided for @statusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get statusExpired;

  /// No description provided for @statusReassigned.
  ///
  /// In en, this message translates to:
  /// **'Reassigned'**
  String get statusReassigned;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @statusAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get statusAccepted;

  /// No description provided for @statusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// No description provided for @statusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get statusRejected;

  /// No description provided for @expiredChooseAnotherMsg.
  ///
  /// In en, this message translates to:
  /// **'The selected astrologer did not respond within the required time. Please choose another astrologer.'**
  String get expiredChooseAnotherMsg;

  /// No description provided for @expiredAdminWillAssignMsg.
  ///
  /// In en, this message translates to:
  /// **'The selected astrologer did not respond in time. An admin will assign another astrologer to your booking.'**
  String get expiredAdminWillAssignMsg;

  /// No description provided for @expiredWaitOnlyMsg.
  ///
  /// In en, this message translates to:
  /// **'This astrologer hasn\'t responded within 24 hours. You can keep waiting or choose another astrologer.'**
  String get expiredWaitOnlyMsg;

  /// No description provided for @chooseAnotherAstrologer.
  ///
  /// In en, this message translates to:
  /// **'Choose Another Astrologer'**
  String get chooseAnotherAstrologer;

  /// No description provided for @expiredBookings.
  ///
  /// In en, this message translates to:
  /// **'Expired Bookings'**
  String get expiredBookings;

  /// No description provided for @assignBooking.
  ///
  /// In en, this message translates to:
  /// **'Assign Booking'**
  String get assignBooking;

  /// No description provided for @assign.
  ///
  /// In en, this message translates to:
  /// **'Assign'**
  String get assign;

  /// No description provided for @availableForAssignment.
  ///
  /// In en, this message translates to:
  /// **'Available for Assignment'**
  String get availableForAssignment;

  /// No description provided for @onLeave.
  ///
  /// In en, this message translates to:
  /// **'On Leave'**
  String get onLeave;

  /// No description provided for @available.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get available;

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get unavailable;

  /// No description provided for @reports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reports;

  /// No description provided for @astrology.
  ///
  /// In en, this message translates to:
  /// **'Astrology'**
  String get astrology;

  /// No description provided for @compatibleMatches.
  ///
  /// In en, this message translates to:
  /// **'Compatible Matches'**
  String get compatibleMatches;

  /// No description provided for @allMatches.
  ///
  /// In en, this message translates to:
  /// **'All Matches'**
  String get allMatches;

  /// No description provided for @viewMatchingStars.
  ///
  /// In en, this message translates to:
  /// **'View Matching Stars'**
  String get viewMatchingStars;

  /// No description provided for @compatibleNakshatras.
  ///
  /// In en, this message translates to:
  /// **'Compatible Nakshatras'**
  String get compatibleNakshatras;

  /// No description provided for @compatibleNakshatrasHint.
  ///
  /// In en, this message translates to:
  /// **'Nakshatras compatible with your star. Compatible Matches shows profiles from these stars that also fit your partner preferences.'**
  String get compatibleNakshatrasHint;

  /// No description provided for @matchingStarsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Add your Nakshatra (or date of birth) in Horoscope Details to see your matching stars.'**
  String get matchingStarsUnavailable;

  /// No description provided for @community.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get community;

  /// No description provided for @verified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get verified;

  /// No description provided for @profession.
  ///
  /// In en, this message translates to:
  /// **'Profession'**
  String get profession;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go Back'**
  String get goBack;

  /// No description provided for @noMatchingProfilesTitle.
  ///
  /// In en, this message translates to:
  /// **'No Matching Profiles Yet'**
  String get noMatchingProfilesTitle;

  /// No description provided for @noMatchingProfilesBody.
  ///
  /// In en, this message translates to:
  /// **'Suitable profiles for you are not available yet. New members are continuously joining. Matching profiles based on your partner preferences and horoscope compatibility will appear here soon.'**
  String get noMatchingProfilesBody;

  /// No description provided for @couldNotLoadMatches.
  ///
  /// In en, this message translates to:
  /// **'Could not load matches'**
  String get couldNotLoadMatches;

  /// No description provided for @expressInterest.
  ///
  /// In en, this message translates to:
  /// **'Express Interest'**
  String get expressInterest;

  /// No description provided for @matchedLabel.
  ///
  /// In en, this message translates to:
  /// **'Matched'**
  String get matchedLabel;

  /// No description provided for @notInterested.
  ///
  /// In en, this message translates to:
  /// **'Not Interested'**
  String get notInterested;

  /// No description provided for @createProfileFirst.
  ///
  /// In en, this message translates to:
  /// **'Create your profile first to send interest'**
  String get createProfileFirst;

  /// No description provided for @interestSentTo.
  ///
  /// In en, this message translates to:
  /// **'Interest sent to {name}'**
  String interestSentTo(String name);

  /// No description provided for @couldNotSendInterest.
  ///
  /// In en, this message translates to:
  /// **'Could not send interest. Please try again.'**
  String get couldNotSendInterest;

  /// No description provided for @youMatchedWith.
  ///
  /// In en, this message translates to:
  /// **'You matched with {name}'**
  String youMatchedWith(String name);

  /// No description provided for @couldNotAcceptInterest.
  ///
  /// In en, this message translates to:
  /// **'Could not accept interest. Please try again.'**
  String get couldNotAcceptInterest;

  /// No description provided for @dailyInterestLimitTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily interest limit reached'**
  String get dailyInterestLimitTitle;

  /// No description provided for @dailyInterestLimitMessage.
  ///
  /// In en, this message translates to:
  /// **'Free members can send {count} interests per day. Upgrade to Basic or Premium for unlimited interests.'**
  String dailyInterestLimitMessage(int count);

  /// No description provided for @newProfiles.
  ///
  /// In en, this message translates to:
  /// **'New Profiles'**
  String get newProfiles;

  /// No description provided for @noNewProfilesYet.
  ///
  /// In en, this message translates to:
  /// **'No new profiles yet.'**
  String get noNewProfilesYet;

  /// No description provided for @recommendedForYou.
  ///
  /// In en, this message translates to:
  /// **'Recommended for You'**
  String get recommendedForYou;

  /// No description provided for @nakshatraMatch.
  ///
  /// In en, this message translates to:
  /// **'Nakshatra Match'**
  String get nakshatraMatch;

  /// No description provided for @matchingProfile.
  ///
  /// In en, this message translates to:
  /// **'Matching Profile'**
  String get matchingProfile;

  /// No description provided for @comingSoonBody.
  ///
  /// In en, this message translates to:
  /// **'This feature is not available yet. We are working on it and it will be unlocked in an upcoming update. Stay tuned!'**
  String get comingSoonBody;

  /// No description provided for @featureMarriageFixed.
  ///
  /// In en, this message translates to:
  /// **'Marriage Fixed'**
  String get featureMarriageFixed;

  /// No description provided for @featureWeddingWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Marriage Workspace'**
  String get featureWeddingWorkspace;

  /// No description provided for @featureFamilyLogin.
  ///
  /// In en, this message translates to:
  /// **'Family Member Login'**
  String get featureFamilyLogin;

  /// No description provided for @featureMuhurthamCalendar.
  ///
  /// In en, this message translates to:
  /// **'Muhurtham Calendar'**
  String get featureMuhurthamCalendar;

  /// No description provided for @viewCalendar.
  ///
  /// In en, this message translates to:
  /// **'View Calendar'**
  String get viewCalendar;

  /// No description provided for @adminSignIn.
  ///
  /// In en, this message translates to:
  /// **'Admin sign-in'**
  String get adminSignIn;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOut;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'ta'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'ta': return AppLocalizationsTa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
