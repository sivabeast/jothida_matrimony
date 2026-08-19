import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jothida_matrimony/models/profile_model.dart';
import 'package:jothida_matrimony/providers/profile_provider.dart';

ProfileModel _profile(String userId) => ProfileModel.fromMap({
      'id': 'p_$userId',
      'userId': userId,
      'fullName': 'Member $userId',
    });

/// Guards the account-switch bug: logging into one account and seeing the
/// other account's profile, or the old profile staying on screen until the app
/// is force-closed.
void main() {
  group('profile stream is scoped to one account', () {
    test('emits null first so a retained profile is dropped at once', () async {
      // A stream that never produces anything stands in for the moment right
      // after a switch, when the new account's snapshot has not arrived yet.
      final events = <ProfileModel?>[];
      final sub =
          scopeToAccount(const Stream<ProfileModel?>.empty(), 'userB').listen(
        events.add,
      );
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(events, isNotEmpty,
          reason: 'consumers must be told to clear immediately');
      expect(events.first, isNull);
    });

    test('passes through the profile that belongs to this account', () async {
      final mine = _profile('userB');
      final events =
          await scopeToAccount(Stream.value(mine), 'userB').toList();

      expect(events, [null, mine]);
    });

    test('drops a late snapshot belonging to the PREVIOUS account', () async {
      // The old listener was already in flight when the member switched; its
      // document must never land in the new account's state.
      final stale = _profile('userA');
      final mine = _profile('userB');
      final events = await scopeToAccount(
        Stream.fromIterable([stale, mine]),
        'userB',
      ).toList();

      expect(events, [null, mine]);
      expect(events.contains(stale), isFalse);
    });

    test('a signed-out account still clears to null', () async {
      final events =
          await scopeToAccount(Stream.value(null), 'userB').toList();

      expect(events, [null, null]);
    });

    test('every emission belongs to the requested account', () async {
      final seen = await scopeToAccount(
        Stream.fromIterable([
          _profile('userA'),
          _profile('userC'),
          _profile('userB'),
        ]),
        'userB',
      ).toList();

      final ids = [for (final p in seen) p?.userId].whereType<String>();
      expect(ids, isNotEmpty);
      expect(ids, everyElement('userB'));
    });
  });
}
