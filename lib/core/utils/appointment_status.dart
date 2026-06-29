import 'package:flutter/material.dart';

import '../../models/astrologer_request_model.dart';
import '../theme/app_colors.dart';

/// User-facing label for an APPOINTMENT's status (distinct from the
/// match-analysis labels): Pending Approval · Confirmed · Completed · Cancelled.
String appointmentStatusLabel(AstrologerRequestStatus status) {
  switch (status) {
    case AstrologerRequestStatus.pending:
      return 'Pending Approval';
    case AstrologerRequestStatus.accepted:
      return 'Confirmed';
    case AstrologerRequestStatus.completed:
      return 'Completed';
    case AstrologerRequestStatus.rejected:
      return 'Cancelled';
  }
}

/// Brand colour used for an appointment status badge.
Color appointmentStatusColor(AstrologerRequestStatus status) {
  switch (status) {
    case AstrologerRequestStatus.pending:
      return AppColors.warning;
    case AstrologerRequestStatus.accepted:
      return AppColors.success;
    case AstrologerRequestStatus.completed:
      return AppColors.info;
    case AstrologerRequestStatus.rejected:
      return AppColors.error;
  }
}

IconData appointmentStatusIcon(AstrologerRequestStatus status) {
  switch (status) {
    case AstrologerRequestStatus.pending:
      return Icons.hourglass_top_outlined;
    case AstrologerRequestStatus.accepted:
      return Icons.check_circle_outline;
    case AstrologerRequestStatus.completed:
      return Icons.verified_outlined;
    case AstrologerRequestStatus.rejected:
      return Icons.cancel_outlined;
  }
}

/// One-line message shown under the status in the user's appointment card.
String appointmentStatusMessage(AstrologerRequestStatus status) {
  switch (status) {
    case AstrologerRequestStatus.pending:
      return 'Your appointment request has been received and is awaiting '
          'confirmation.';
    case AstrologerRequestStatus.accepted:
      return 'Your appointment has been confirmed successfully.';
    case AstrologerRequestStatus.completed:
      return 'Your appointment has been completed. Thank you!';
    case AstrologerRequestStatus.rejected:
      return 'Your appointment has been cancelled.';
  }
}
