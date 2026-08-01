import 'package:flutter/material.dart';

/// One required field in a form, in the order it appears on screen.
///
/// [id] links the check to the widget's anchor key ([InlineValidation.anchor])
/// and to the inline error text ([InlineValidation.errorOf]).
class FieldCheck {
  final String id;

  /// Whether the field currently holds an acceptable value.
  final bool valid;

  /// Inline message rendered in red directly BELOW the field when invalid.
  final String message;

  /// Optional node focused after scrolling, so the keyboard opens on the exact
  /// field that needs fixing.
  final FocusNode? focusNode;

  const FieldCheck({
    required this.id,
    required this.valid,
    required this.message,
    this.focusNode,
  });

  /// Convenience for the overwhelmingly common "must not be blank" case.
  factory FieldCheck.notEmpty(
    String id,
    String? value,
    String message, {
    FocusNode? focusNode,
  }) =>
      FieldCheck(
        id: id,
        valid: (value ?? '').trim().isNotEmpty,
        message: message,
        focusNode: focusNode,
      );
}

/// Shared "one consistent validation style" for EVERY form in the app (§10).
///
/// Behaviour on Save / Next:
///   1. every required field is checked in on-screen order;
///   2. an inline RED message appears under each invalid field — no snackbars,
///      no error text collected at the bottom of the page;
///   3. the page scrolls to the FIRST invalid field and focuses it;
///   4. once the member fixes it and presses Save again, the next invalid field
///      is scrolled to, and so on.
///
/// Usage inside a `State`:
/// ```dart
/// final _v = InlineValidation();
/// ...
/// SearchableWithOthersField(
///   key: _v.anchor('education'),
///   errorText: _v.errorOf('education'),
///   ...
/// )
/// ...
/// if (!_v.validate(context, [FieldCheck.notEmpty('education', _education, msg)],
///     onChanged: () => setState(() {}))) return;
/// ```
class InlineValidation {
  final Map<String, GlobalKey> _anchors = {};
  final Map<String, String> _errors = {};

  /// Stable anchor key for [id] — attach it to the field widget so the
  /// validator can scroll the field into view.
  GlobalKey anchor(String id) =>
      _anchors.putIfAbsent(id, () => GlobalKey(debugLabel: id));

  /// The inline error currently shown for [id], or null.
  String? errorOf(String id) => _errors[id];

  bool get hasErrors => _errors.isNotEmpty;

  /// Clears the error for [id] — call from a field's `onChanged` so the red
  /// message disappears as soon as the member starts fixing it.
  void clear(String id) => _errors.remove(id);

  void clearAll() => _errors.clear();

  /// Validates [checks] in order.
  ///
  /// Returns true when every check passes. Otherwise records the inline errors,
  /// scrolls to and focuses the first invalid field, calls [onChanged] so the
  /// caller can `setState`, and returns false.
  bool validate(
    BuildContext context,
    List<FieldCheck> checks, {
    VoidCallback? onChanged,
  }) {
    _errors.clear();
    FieldCheck? first;
    for (final check in checks) {
      if (check.valid) continue;
      _errors[check.id] = check.message;
      first ??= check;
    }
    onChanged?.call();
    if (first == null) return true;
    _revealAfterFrame(first);
    return false;
  }

  /// Scrolls to + focuses the first invalid field AFTER the frame that renders
  /// the error text, so the anchor has its final position.
  void _revealAfterFrame(FieldCheck check) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _anchors[check.id]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          // Leave a little breathing room above the field.
          alignment: 0.12,
        );
      }
      final node = check.focusNode;
      if (node != null && node.canRequestFocus) node.requestFocus();
    });
  }
}

/// Renders [error] as the standard inline red message used under every field.
///
/// Returns an empty box when there is nothing to show, so it can be dropped
/// into any column unconditionally.
class InlineFieldError extends StatelessWidget {
  final String? error;
  const InlineFieldError(this.error, {super.key});

  @override
  Widget build(BuildContext context) {
    final message = error;
    if (message == null || message.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline,
              size: 14, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
