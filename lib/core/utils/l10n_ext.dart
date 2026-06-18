import 'package:flutter/widgets.dart';
import 'package:jothida_matrimony/l10n/app_localizations.dart';

/// Terse access to the generated localizations from any widget:
///
/// ```dart
/// Text(context.l10n.login)
/// ```
///
/// `AppLocalizations.of` is non-null here (l10n.yaml sets `nullable-getter:
/// false`), so callers never need a null check.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
