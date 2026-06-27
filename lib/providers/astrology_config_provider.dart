import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/astrology_service_config.dart';
import '../services/firebase/astrology_config_service.dart';

/// Singleton service for the internal astrology service config.
final astrologyConfigServiceProvider =
    Provider<AstrologyConfigService>((ref) => AstrologyConfigService());

/// Live internal astrology service config (`astrology_service/config`), with
/// built-in defaults until the admin saves one. Powers the service details
/// page, the appointment booking (slots + charge) and the confirmation screen.
final astrologyServiceConfigProvider =
    StreamProvider<AstrologyServiceConfig>((ref) {
  return ref.watch(astrologyConfigServiceProvider).watch();
});

/// Synchronous best-effort accessor — the current config or defaults. Handy in
/// imperative flows (e.g. the booking controller) that just need the latest
/// known value without awaiting.
final astrologyServiceConfigValueProvider =
    Provider<AstrologyServiceConfig>((ref) {
  return ref.watch(astrologyServiceConfigProvider).valueOrNull ??
      AstrologyServiceConfig.defaults;
});
