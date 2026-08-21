import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/astrologer_request_model.dart';
import '../theme/app_colors.dart';
import 'l10n_ext.dart';

/// User-facing label for an APPOINTMENT's status (distinct from the
/// match-analysis labels): Pending Approval · Confirmed · Completed · Cancelled.
///
/// Localized — pass the screen's [AppLocalizations] so the label follows the
/// app language (spec §17). Use [appointmentStatusLabelOf] when you have a
/// [BuildContext] to hand.
String appointmentStatusLabel(
    AppLocalizations l10n, AstrologerRequestStatus status) {
  switch (status) {
    case AstrologerRequestStatus.pending:
      return l10n.apptStatusPendingApproval;
    case AstrologerRequestStatus.accepted:
      return l10n.apptStatusConfirmed;
    case AstrologerRequestStatus.completed:
      return l10n.apptStatusCompleted;
    case AstrologerRequestStatus.rejected:
      return l10n.apptStatusCancelled;
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
String appointmentStatusMessage(
    AppLocalizations l10n, AstrologerRequestStatus status) {
  switch (status) {
    case AstrologerRequestStatus.pending:
      return l10n.apptMsgPending;
    case AstrologerRequestStatus.accepted:
      return l10n.apptMsgConfirmed;
    case AstrologerRequestStatus.completed:
      return l10n.apptMsgCompleted;
    case AstrologerRequestStatus.rejected:
      return l10n.apptMsgCancelled;
  }
}

/// True while a booking is still open — neither completed nor cancelled.
bool isOpenAppointment(AstrologerRequestStatus status) =>
    status != AstrologerRequestStatus.completed &&
    status != AstrologerRequestStatus.rejected;

/// The label a booking card shows in its top-right chip.
///
/// An OPEN booking whose visit date is still in the future reads "Upcoming"
/// (spec §2); everything else falls back to its own status label so a member
/// always sees Pending / Confirmed / Completed / Cancelled correctly.
String appointmentTimelineLabel(
    AppLocalizations l10n, AstrologerRequestModel appt) {
  final date = appt.visitDate;
  if (isOpenAppointment(appt.status) &&
      date != null &&
      !date.isBefore(DateTime(
          DateTime.now().year, DateTime.now().month, DateTime.now().day))) {
    return l10n.apptStatusUpcoming;
  }
  return appointmentStatusLabel(l10n, appt.status);
}

extension AppointmentStatusX on BuildContext {
  String appointmentStatusLabelOf(AstrologerRequestStatus s) =>
      appointmentStatusLabel(l10n, s);

  String appointmentStatusMessageOf(AstrologerRequestStatus s) =>
      appointmentStatusMessage(l10n, s);
}
