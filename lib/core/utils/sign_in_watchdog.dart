import 'dart:async';

/// Runs an *interactive* operation ([pick]) that the user paces — here, the
/// native Google account chooser — while a watchdog checks whether its result
/// has already landed somewhere else ([recover]).
///
/// ## Why this exists
///
/// `GoogleSignIn.signIn()` on Android is implemented with
/// `startActivityForResult`: the plugin stores a "pending operation" and
/// completes the Dart future from `onActivityResult`. If Android destroys and
/// recreates the host Activity while the chooser is on screen — low-memory
/// devices, "Don't keep activities", or a configuration change — the result is
/// delivered to a *new* plugin instance whose pending operation is null. The
/// original future is then **never completed and never fails**: the app sits on
/// its login spinner forever ("I picked my account and it just kept loading").
///
/// A plain `.timeout()` cannot fix that on its own, because the picker is
/// user-paced: a timeout short enough to be useful would cut off a user who is
/// simply reading the account list.
///
/// The recovery works because, by the time the result is lost, Play Services
/// has *already* cached the chosen account — so `signInSilently()` returns it
/// immediately. While the plugin is healthy the probe is a harmless no-op: the
/// plugin rejects concurrent operations, the probe's error is swallowed, and we
/// keep waiting for the real result.
///
/// Callers must ensure there is no *stale* cached account before starting (the
/// caller signs out of Google first), otherwise a probe firing while the user
/// is still choosing could resolve to the previous account.
///
/// Returns whatever [pick] (or the recovery) produced — `null` means the user
/// dismissed the chooser. Throws [TimeoutException] if nothing at all happens
/// within [timeout], so the caller can always clear its loading state.
Future<T?> pickWithRecovery<T>({
  required Future<T?> Function() pick,
  required Future<T?> Function() recover,
  Duration probeAfter = const Duration(seconds: 12),
  Duration probeInterval = const Duration(seconds: 5),
  Duration timeout = const Duration(minutes: 3),
  void Function(String message)? log,
}) async {
  final completer = Completer<T?>();
  var settled = false;

  void complete(T? value) {
    if (settled) return;
    settled = true;
    completer.complete(value);
  }

  void fail(Object error, [StackTrace? stackTrace]) {
    if (settled) return;
    settled = true;
    completer.completeError(error, stackTrace ?? StackTrace.current);
  }

  // The real interactive call. A late result after we have already recovered is
  // simply dropped (`settled` guard) instead of crashing on a double-complete.
  unawaited(pick().then<void>(
    complete,
    onError: (Object e, StackTrace st) => fail(e, st),
  ));

  final deadline = Timer(timeout, () {
    log?.call('no result after ${timeout.inSeconds}s — giving up');
    fail(TimeoutException('Interactive sign-in produced no result', timeout));
  });

  // Watchdog: only starts probing after `probeAfter`, so a user who takes a few
  // seconds to choose an account is never interfered with.
  unawaited(() async {
    await Future<void>.delayed(probeAfter);
    while (!settled) {
      try {
        final recovered = await recover();
        if (recovered != null) {
          log?.call('picker result was lost — recovered it silently');
          complete(recovered);
          break;
        }
      } catch (e) {
        // Expected while the picker is genuinely still open: the plugin refuses
        // concurrent operations. Never fatal.
        log?.call('recovery probe ignored: $e');
      }
      if (settled) break;
      await Future<void>.delayed(probeInterval);
    }
  }());

  try {
    return await completer.future;
  } finally {
    deadline.cancel();
  }
}
