/// Why saving a matrimony profile failed — and what the member is told.
///
/// Profile creation used to surface a raw Firebase error such as
/// `[cloud_firestore/permission-denied] The caller does not have permission to
/// execute the specified operation.` That string names neither the failing
/// step nor anything the member can do. Every failure is now classified here,
/// the member sees a translated sentence, and the developer log names the exact
/// Firestore operation (see [ProfileSaveException.operation]).
library;

import 'dart:async' show TimeoutException;
import 'dart:io' show SocketException;

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;

import '../../l10n/app_localizations.dart';
import '../../services/cloudinary/cloudinary_exception.dart';

enum ProfileSaveFailure {
  /// No signed-in (non-guest) account — nothing is written.
  notSignedIn,

  /// The session can no longer be used (revoked, expired, account disabled,
  /// or signed in to a different account than the one being saved).
  sessionExpired,

  /// The security rules refused a write or read.
  permissionDenied,

  /// The server could not be reached or did not confirm the write in time.
  network,

  /// Required profile details are missing.
  missingFields,

  /// The photo / horoscope upload failed (Cloudinary). Keeps its own messages.
  upload,

  unknown,
}

/// A profile-save failure that knows WHICH operation failed.
class ProfileSaveException implements Exception {
  final ProfileSaveFailure failure;

  /// e.g. `profiles/{id} create`, `users/{uid} isProfileComplete` — for logs
  /// and support, never shown as the whole message.
  final String operation;

  final Object? cause;

  const ProfileSaveException(this.failure, this.operation, [this.cause]);

  @override
  String toString() =>
      'ProfileSaveException(${failure.name} at "$operation"${cause == null ? '' : ': $cause'})';
}

/// Classifies any error thrown while saving a profile.
ProfileSaveFailure classifyProfileSaveError(Object error) {
  if (error is ProfileSaveException) return error.failure;
  if (error is CloudinaryUploadException) return ProfileSaveFailure.upload;
  if (error is TimeoutException || error is SocketException) {
    return ProfileSaveFailure.network;
  }
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'network-request-failed':
      case 'too-many-requests':
        return ProfileSaveFailure.network;
      default:
        // user-token-expired, invalid-user-token, user-disabled,
        // user-not-found, requires-recent-login…
        return ProfileSaveFailure.sessionExpired;
    }
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return ProfileSaveFailure.permissionDenied;
      case 'unauthenticated':
        return ProfileSaveFailure.sessionExpired;
      case 'unavailable':
      case 'deadline-exceeded':
      case 'network-request-failed':
        return ProfileSaveFailure.network;
    }
  }
  return ProfileSaveFailure.unknown;
}

/// The member-facing sentence for [failure] (English or Tamil).
String profileSaveMessage(AppLocalizations l10n, ProfileSaveFailure failure) {
  switch (failure) {
    case ProfileSaveFailure.notSignedIn:
      return l10n.profileSaveNotSignedIn;
    case ProfileSaveFailure.sessionExpired:
      return l10n.profileSaveSessionExpired;
    case ProfileSaveFailure.permissionDenied:
      return l10n.profileSavePermissionDenied;
    case ProfileSaveFailure.network:
      return l10n.profileSaveNetwork;
    case ProfileSaveFailure.missingFields:
      return l10n.profileSaveMissingFields;
    case ProfileSaveFailure.upload:
    case ProfileSaveFailure.unknown:
      return l10n.profileSaveFailedGeneric;
  }
}

/// Whether the signed-in account may write a profile for [targetUid].
///
/// A member saves only their OWN profile: the uid the wizard writes under must
/// be the uid Firebase Auth is signed in as. An admin writing on a member's
/// behalf ([onBehalfOfMember]) is authorised by the rules through the admin
/// role instead. Returns the failure to report, or null when the save may go
/// ahead.
ProfileSaveFailure? checkProfileSaveSession({
  required String targetUid,
  required String? signedInUid,
  required bool signedInIsGuest,
  required bool onBehalfOfMember,
}) {
  final signedIn = (signedInUid ?? '').trim();
  if (signedIn.isEmpty || signedInIsGuest) return ProfileSaveFailure.notSignedIn;
  if (targetUid.trim().isEmpty) return ProfileSaveFailure.notSignedIn;
  if (!onBehalfOfMember && targetUid.trim() != signedIn) {
    return ProfileSaveFailure.sessionExpired;
  }
  return null;
}

/// The required details a NEW profile must carry — the same ones the wizard
/// validates step by step, checked once more at submit so an incomplete
/// document is never sent (the security rules enforce name + gender too).
List<String> missingRequiredProfileFields(Map<String, dynamic> wizardData) {
  String s(Object? v) => '${v ?? ''}'.trim();
  return [
    if (s(wizardData['name']).isEmpty) 'name',
    if (s(wizardData['gender']).isEmpty) 'gender',
    if (s(wizardData['dateOfBirth']).isEmpty) 'dateOfBirth',
  ];
}

/// The admin-panel sentence for a failed account / profile action. Admin
/// screens are English-only. Never the raw Firebase text: the code is logged,
/// and the admin is told what it means and what to check.
String describeAdminActionError(Object error) {
  switch (classifyProfileSaveError(error)) {
    case ProfileSaveFailure.permissionDenied:
      return 'The database refused this action (permission denied). Check that '
          'you are signed in as an administrator and that the latest Firestore '
          'rules are deployed.';
    case ProfileSaveFailure.network:
      return 'Could not reach the server. Check the connection and try again.';
    case ProfileSaveFailure.sessionExpired:
    case ProfileSaveFailure.notSignedIn:
      return 'Your session has expired. Sign in again and retry.';
    case ProfileSaveFailure.missingFields:
    case ProfileSaveFailure.upload:
    case ProfileSaveFailure.unknown:
      return 'The action could not be completed. Please try again.';
  }
}
