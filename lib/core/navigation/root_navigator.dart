import 'package:flutter/material.dart';

/// App-wide navigator + messenger keys, kept in their own tiny file so they can
/// be shared by the router and non-widget services (e.g. [FcmService]) without
/// creating an import cycle.
///
/// [rootNavigatorKey] is handed to the GoRouter so a push-notification tap can
/// deep-link into a booking from anywhere (foreground, background or cold
/// start). [rootScaffoldMessengerKey] lets the same service surface a foreground
/// in-app banner/SnackBar.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
