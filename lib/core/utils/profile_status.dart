import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_colors.dart';

/// User/admin-facing label for a PROFILE's verification status.
///
/// The profile review queue IS the verification system — there is no second
/// one. The stored value stays `'approved'` (Firestore rules, indexes and the
/// Cloud Functions key off it), but everywhere a human reads it the wording is
/// "Verified" / "Pending Verification".
String profileStatusLabel(String? rawStatus) {
  switch ((rawStatus ?? '').trim().toLowerCase()) {
    case AppConstants.profileApproved:
      return 'Verified';
    case AppConstants.profilePending:
    case '':
      return 'Pending Verification';
    case AppConstants.profileRejected:
      return 'Rejected';
    case AppConstants.profileBlocked:
      return 'Blocked';
    default:
      return rawStatus!.trim();
  }
}

/// Brand colour for a profile verification status badge.
Color profileStatusColor(String? rawStatus) {
  switch ((rawStatus ?? '').trim().toLowerCase()) {
    case AppConstants.profileApproved:
      return AppColors.success;
    case AppConstants.profilePending:
    case '':
      return AppColors.warning;
    case AppConstants.profileRejected:
    case AppConstants.profileBlocked:
      return AppColors.error;
    default:
      return AppColors.info;
  }
}
