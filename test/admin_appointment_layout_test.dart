// Layout regression tests for the admin Appointment Management card (spec §19).
//
// The card used to squeeze each label AND its value into half the card width,
// so ordinary values ("Consultation", "In-Person · Office Visit") wrapped one
// word — sometimes one character — per line on a phone. These tests pin the
// fixed structure: no overflow at phone widths, and every value laid out with
// enough width to wrap on word boundaries.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jothida_matrimony/screens/admin/admin_appointments_screen.dart';

/// The narrowest phone the app supports, and a couple of common widths.
const _widths = <double>[320, 360, 412];

Widget _host(Widget child, double width) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );

void main() {
  group('appointment details layout', () {
    testWidgets('never overflows at phone widths', (tester) async {
      for (final w in _widths) {
        tester.view.physicalSize = Size(w, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_host(
          const Padding(
            padding: EdgeInsets.all(14),
            child: AppointmentDetailsGrid(items: [
              (Icons.category_outlined, 'Appointment Type', 'Consultation'),
              (Icons.place_outlined, 'Meeting Type', 'In-Person · Office Visit'),
              (Icons.event_outlined, 'Date', 'Wed, 12 Aug 2026'),
              (Icons.schedule_outlined, 'Time', 'Morning'),
              (Icons.payments_outlined, 'Payment', 'Free'),
              (
                Icons.history_toggle_off_outlined,
                'Created',
                '12 Aug 2026, 10:24 AM'
              ),
            ]),
          ),
          w,
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'the appointment details grid overflowed at ${w}px');
      }
    });

    testWidgets('gives each value enough width to wrap on word boundaries',
        (tester) async {
      // 320px is the narrowest supported phone: the grid must collapse to a
      // single column there rather than halving an already-tight card.
      tester.view.physicalSize = const Size(320, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(
        const Padding(
          padding: EdgeInsets.all(14),
          child: AppointmentDetailsGrid(items: [
            (Icons.place_outlined, 'Meeting Type', 'In-Person · Office Visit'),
          ]),
        ),
        320,
      ));
      await tester.pumpAndSettle();

      final value = tester.renderObject<RenderBox>(
          find.text('In-Person · Office Visit'));
      // "In-Person" alone is ~70px at 12.5sp; anything under that would mean a
      // column so narrow that words break apart.
      expect(value.size.width, greaterThan(120),
          reason: 'the value column is too narrow to wrap on word boundaries');
    });

    testWidgets('an empty value renders a dash, not a blank gap',
        (tester) async {
      await tester.pumpWidget(_host(
        const Padding(
          padding: EdgeInsets.all(14),
          child: AppointmentDetailsGrid(items: [
            (Icons.event_outlined, 'Date', ''),
          ]),
        ),
        360,
      ));
      await tester.pumpAndSettle();
      expect(find.text('—'), findsOneWidget);
    });
  });
}
