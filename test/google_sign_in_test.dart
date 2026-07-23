// Regression tests for the Google Sign-In "stuck on the loading screen" bug.
//
// The failure was NOT a wrong credential: the account picker worked, the user
// chose an account, and then the app span forever because a step in the chain
// never completed and never threw. These tests pin the two guarantees that
// make that impossible:
//
//   1. `pickWithRecovery` always settles — it recovers a lost picker result,
//      and fails loudly if nothing at all comes back.
//   2. `AuthException.from` turns every realistic failure (cancel, network,
//      SHA-1/OAuth misconfiguration, Firebase errors) into an actionable
//      message instead of silence.

import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter_test/flutter_test.dart';
import 'package:jothida_matrimony/core/errors/auth_exception.dart';
import 'package:jothida_matrimony/core/utils/sign_in_watchdog.dart';

void main() {
  group('pickWithRecovery — the account picker can never hang forever', () {
    test('returns the picked account when the plugin behaves', () async {
      var probes = 0;
      final result = await pickWithRecovery<String>(
        pick: () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return 'picked@gmail.com';
        },
        recover: () async {
          probes++;
          return null;
        },
        probeAfter: const Duration(milliseconds: 200),
      );

      expect(result, 'picked@gmail.com');
      expect(probes, 0, reason: 'a healthy picker must never be probed');
    });

    test('propagates a cancelled picker as null', () async {
      final result = await pickWithRecovery<String>(
        pick: () async => null, // user dismissed the chooser
        recover: () async => 'stale@gmail.com',
        probeAfter: const Duration(milliseconds: 200),
      );

      expect(result, isNull);
    });

    test(
        'recovers the account when the picker result is lost '
        '(Activity recreated mid-chooser)', () async {
      // Reproduces the real defect: signIn()'s future is never completed
      // because the result was delivered to a recreated plugin instance.
      final lostForever = Completer<String?>();
      addTearDown(() {
        if (!lostForever.isCompleted) lostForever.complete(null);
      });

      final sw = Stopwatch()..start();
      final result = await pickWithRecovery<String>(
        pick: () => lostForever.future,
        recover: () async => 'recovered@gmail.com',
        probeAfter: const Duration(milliseconds: 50),
        probeInterval: const Duration(milliseconds: 20),
        timeout: const Duration(seconds: 5),
      );
      sw.stop();

      expect(result, 'recovered@gmail.com');
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)),
          reason: 'recovery must not wait for the overall timeout');
    });

    test('ignores probe failures while the picker is genuinely open', () async {
      // The plugin rejects concurrent operations while the chooser is up; that
      // must never abort the sign-in.
      var probes = 0;
      final result = await pickWithRecovery<String>(
        pick: () async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          return 'picked@gmail.com';
        },
        recover: () async {
          probes++;
          throw PlatformException(
              code: 'concurrent', message: 'Concurrent operations detected');
        },
        probeAfter: const Duration(milliseconds: 20),
        probeInterval: const Duration(milliseconds: 20),
      );

      expect(result, 'picked@gmail.com');
      expect(probes, greaterThan(0), reason: 'the watchdog should have probed');
    });

    test('throws TimeoutException when nothing ever comes back', () async {
      final lostForever = Completer<String?>();
      addTearDown(() {
        if (!lostForever.isCompleted) lostForever.complete(null);
      });

      await expectLater(
        pickWithRecovery<String>(
          pick: () => lostForever.future,
          recover: () async => null, // recovery finds nothing either
          probeAfter: const Duration(milliseconds: 20),
          probeInterval: const Duration(milliseconds: 20),
          timeout: const Duration(milliseconds: 200),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('a real error from the picker is surfaced, not swallowed', () async {
      await expectLater(
        pickWithRecovery<String>(
          pick: () async =>
              throw PlatformException(code: 'sign_in_failed', message: '10:'),
          recover: () async => null,
          probeAfter: const Duration(milliseconds: 200),
        ),
        throwsA(isA<PlatformException>()),
      );
    });

    test('a late picker result after recovery does not blow up', () async {
      final late = Completer<String?>();
      final result = await pickWithRecovery<String>(
        pick: () => late.future,
        recover: () async => 'recovered@gmail.com',
        probeAfter: const Duration(milliseconds: 20),
        probeInterval: const Duration(milliseconds: 20),
      );
      expect(result, 'recovered@gmail.com');

      // The abandoned native call finally lands. Completing an already-settled
      // flow must be a no-op rather than an uncaught "Future already completed".
      late.complete('picked@gmail.com');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  });

  group('AuthException.from — every failure gets an actionable message', () {
    test('a dismissed chooser is flagged as cancelled, not an error', () {
      final e =
          AuthException.from(PlatformException(code: 'sign_in_canceled'));
      expect(e.cancelled, isTrue);
    });

    test('ApiException 10 names the SHA-1 / OAuth client cause', () {
      final e = AuthException.from(PlatformException(
        code: 'sign_in_failed',
        message: 'com.google.android.gms.common.api.ApiException: 10: ',
      ));
      expect(e.code, 'sign_in_failed_10');
      expect(e.message, contains('SHA-1'));
      expect(e.cancelled, isFalse);
    });

    test('ApiException 12500 points at the OAuth consent screen', () {
      final e = AuthException.from(PlatformException(
        code: 'sign_in_failed',
        message: 'ApiException: 12500: ',
      ));
      expect(e.code, 'sign_in_failed_12500');
    });

    test('network failures are reported as network failures', () {
      expect(AuthException.from(PlatformException(code: 'network_error')).code,
          'network_error');
      expect(
          AuthException.from(
                  FirebaseAuthException(code: 'network-request-failed'))
              .code,
          'network-request-failed');
    });

    test('an invalid/expired credential is reported as such', () {
      final e =
          AuthException.from(FirebaseAuthException(code: 'invalid-credential'));
      expect(e.code, 'invalid-credential');
      expect(e.message, isNotEmpty);
    });

    test('Google provider disabled in Firebase is called out by name', () {
      final e = AuthException.from(
          FirebaseAuthException(code: 'operation-not-allowed'));
      expect(e.message, contains('Firebase Console'));
    });

    test('a timed-out step becomes a retryable error, never a silent hang', () {
      final e = AuthException.from(
          TimeoutException('no result', const Duration(seconds: 30)));
      expect(e.code, 'timeout');
      expect(e.cancelled, isFalse);
      expect(e.message, contains('try again'));
    });

    test('an unknown error still produces a non-empty message', () {
      final e = AuthException.from(StateError('boom'));
      expect(e.message, isNotEmpty);
      expect(e.cancelled, isFalse);
    });
  });
}
