import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';

/// The profile VERIFICATION indicator shown beside a member's name.
///
/// It reflects the one and only verification system in the app — the admin
/// profile review queue ([ProfileModel.isProfileVerified], i.e. the profile
/// status the admin sets from Pending Verification to Verified). There is no
/// second verification concept.
///
///  • VERIFIED     → a GREEN tick.
///  • NOT VERIFIED → the SAME tick in a dark/disabled grey, so a viewer can see
///    at a glance that the profile has not been verified yet.
///
/// It is purely a status indicator: never tappable, never a button.
class VerificationTick extends StatelessWidget {
  /// Whether an admin has verified this profile.
  final bool verified;

  /// Icon size in logical pixels — callers match it to the adjacent name.
  final double size;

  const VerificationTick({super.key, required this.verified, this.size = 16});

  /// Convenience constructor reading the status straight off a profile.
  VerificationTick.forProfile(ProfileModel profile,
      {super.key, this.size = 16})
      : verified = profile.isProfileVerified;

  /// Dark/inactive tick colour for a profile that is not verified.
  static const Color unverifiedColor = Color(0xFF3A3A3A);

  @override
  Widget build(BuildContext context) => Semantics(
        label: verified ? 'Verified profile' : 'Profile not verified',
        child: Opacity(
          // A slightly muted, disabled appearance when not verified.
          opacity: verified ? 1 : 0.55,
          child: Icon(
            Icons.verified,
            size: size,
            color: verified ? AppColors.success : unverifiedColor,
          ),
        ),
      );
}
