import 'package:flutter/widgets.dart';

import 'l10n_ext.dart';
import '../../l10n/app_localizations.dart';

class AppValidators {
  static String? email(String? value) {
    if (value == null || value.isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(value)) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != password) return 'Passwords do not match';
    return null;
  }

  /// Mobile number rule (§4): MANDATORY, digits only, EXACTLY 10 digits — no
  /// alphabets, no spaces, no special characters, no +91 prefix (the field
  /// renders that separately). Anything else blocks the form.
  ///
  /// [isValidMobile] is the single source of truth; this wrapper only adds the
  /// English message. Localized screens should use [LocalizedValidators.mobile]
  /// so the error text follows the selected language.
  static String? phone(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Mobile number is required.';
    if (!isValidMobile(v)) {
      return 'Enter a valid 10-digit mobile number (digits only).';
    }
    return null;
  }

  /// Exactly ten digit characters and nothing else.
  static bool isValidMobile(String? value) =>
      RegExp(r'^\d{10}$').hasMatch((value ?? '').trim());

  static String? name(String? value) {
    if (value == null || value.isEmpty) return 'Name is required';
    if (value.trim().length < 2) return 'Name must be at least 2 characters';
    if (value.trim().length > 50) return 'Name must be less than 50 characters';
    return null;
  }

  static String? required(String? value, {String fieldName = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$fieldName is required';
    return null;
  }

  static String? otp(String? value) {
    if (value == null || value.isEmpty) return 'OTP is required';
    if (value.length != 6) return 'Enter a valid 6-digit OTP';
    return null;
  }

  static String? age(String? value) {
    if (value == null || value.isEmpty) return 'Age is required';
    final age = int.tryParse(value);
    if (age == null) return 'Enter a valid age';
    if (age < 18) return 'Minimum age is 18 years';
    if (age > 80) return 'Enter a valid age';
    return null;
  }

  static String? pincode(String? value) {
    if (value == null || value.isEmpty) return 'Pincode is required';
    if (value.length != 6) return 'Enter a valid 6-digit pincode';
    return null;
  }

  static String? about(String? value) {
    if (value == null || value.isEmpty) return null; // Optional
    if (value.length > 500) return 'About me must be less than 500 characters';
    return null;
  }
}

/// Alias used by screens that refer to `Validators.*`.
typedef Validators = AppValidators;

/// Form validators whose messages follow the selected app language (§20).
///
/// The RULES live in [AppValidators]; this only supplies localized text, so
/// English and Tamil can never disagree about what is valid.
class LocalizedValidators {
  final AppLocalizations l;
  const LocalizedValidators(this.l);

  /// Mobile number (§4): mandatory, digits only, exactly 10 digits.
  String? mobile(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return l.mobileNumberRequired;
    if (!AppValidators.isValidMobile(v)) return l.mobileNumberExactly10;
    return null;
  }

  /// Optional mobile field (e.g. a separate WhatsApp number): blank is fine,
  /// but anything entered must still be a valid 10-digit number.
  String? optionalMobile(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    return AppValidators.isValidMobile(v) ? null : l.mobileNumberExactly10;
  }

  String? name(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return l.pleaseEnterField(l.fullName);
    if (v.length < 2 || v.length > 50) return l.pleaseEnterField(l.fullName);
    return null;
  }

  String? requiredField(String? value, String fieldName) =>
      (value == null || value.trim().isEmpty)
          ? l.pleaseEnterField(fieldName)
          : null;

  String? email(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return l.pleaseEnterField(l.email);
    final re = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return re.hasMatch(v) ? null : l.invalidEmail;
  }
}

extension ValidatorsX on BuildContext {
  /// Localized validators for the current language.
  LocalizedValidators get validators => LocalizedValidators(l10n);
}
