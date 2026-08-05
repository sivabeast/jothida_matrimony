// Spec §4 — the Requests module and the Appointments module must be
// COMPLETELY independent: no document may ever appear in both.
//
// `isReportRequest` is the single predicate the Requests module filters on
// (admin + employee alike) and `hasAppointment` is the one the Appointments
// module uses, so these two must be mutually exclusive for every shape of
// document the app can produce — including the legacy "report booked as an
// in-person visit" hybrid.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/models/astrologer_request_model.dart';
import 'package:jothida_matrimony/models/compatibility_report_model.dart';

AstrologerRequestModel _request({
  required AstrologerRequestType type,
  DateTime? visitDate,
  String session = '',
  int? slotStartMinutes,
}) =>
    AstrologerRequestModel(
      id: 'r1',
      astrologerId: 'a1',
      userId: 'u1',
      userName: 'Test User',
      type: type,
      createdAt: DateTime(2026, 8, 5),
      visitDate: visitDate,
      session: session,
      slotStartMinutes: slotStartMinutes,
    );

void main() {
  group('Requests vs Appointments (§4)', () {
    test('an online horoscope report is a report request, not an appointment',
        () {
      final r = _request(type: AstrologerRequestType.matching);
      expect(r.isReportRequest, isTrue);
      expect(r.hasAppointment, isFalse);
    });

    test('an office-visit consultation is an appointment, not a request', () {
      final r = _request(
        type: AstrologerRequestType.consultation,
        visitDate: DateTime(2026, 8, 12),
        session: AppointmentSession.morning,
        slotStartMinutes: AppointmentSession.morningStart,
      );
      expect(r.hasAppointment, isTrue);
      expect(r.isReportRequest, isFalse);
    });

    test('a LEGACY matching booking that carries a visit stays an appointment',
        () {
      // Documents written by the removed hybrid flow: type `matching` AND an
      // office visit. They must show up ONLY under Appointments — otherwise
      // the same booking appears in both modules.
      final r = _request(
        type: AstrologerRequestType.matching,
        visitDate: DateTime(2026, 8, 12),
        session: AppointmentSession.afternoon,
        slotStartMinutes: AppointmentSession.afternoonStart,
      );
      expect(r.hasAppointment, isTrue);
      expect(r.isReportRequest, isFalse,
          reason: 'a booking with an office visit is never a report request');
    });

    test('an inquiry is neither', () {
      final r = _request(type: AstrologerRequestType.inquiry);
      expect(r.isReportRequest, isFalse);
      expect(r.hasAppointment, isFalse);
    });
  });

  group('திசா சந்தி is a உண்டு / இல்லை answer (§1)', () {
    test('a stored answer round-trips', () {
      final report = CompatibilityReport(
        dasa: const [
          DoshamRow(bride: CompatAnswer.yes, groom: CompatAnswer.no),
          DoshamRow(bride: CompatAnswer.no, groom: CompatAnswer.yes),
        ],
      );
      final back = CompatibilityReport.fromMap(report.toMap());
      expect(back.dasaAt(0).bride, CompatAnswer.yes);
      expect(back.dasaAt(0).groom, CompatAnswer.no);
      expect(back.dasaAt(1).bride, CompatAnswer.no);
      expect(back.dasaAt(1).groom, CompatAnswer.yes);
    });

    test('legacy FREE TEXT reads back as "not answered", never as a verdict',
        () {
      // Drafts written while திசா சந்தி was a text field stored things like
      // "விருச்சிகம்". Those must not render as உண்டு/இல்லை — the employee is
      // asked to pick one before the report can be submitted.
      final legacy = CompatibilityReport.fromMap({
        'dasa': [
          {'bride': 'விருச்சிகம்', 'groom': 'மேஷம்'},
        ],
      });
      expect(legacy.dasaAt(0).bride, CompatAnswer.none);
      expect(legacy.dasaAt(0).groom, CompatAnswer.none);
    });

    test('answers survive a Firestore-shaped map with a Timestamp', () {
      final map = CompatibilityReport(
        status: CompatibilityReport.statusSubmitted,
        dasa: const [DoshamRow(bride: CompatAnswer.yes, groom: CompatAnswer.yes)],
        submittedAt: DateTime(2026, 8, 5),
      ).toMap();
      expect(map['submittedAt'], isA<Timestamp>());
      final back = CompatibilityReport.fromMap(map);
      expect(back.isSubmitted, isTrue);
      expect(back.dasaAt(0).bride, CompatAnswer.yes);
    });
  });
}
