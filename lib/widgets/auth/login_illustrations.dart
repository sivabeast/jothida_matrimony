import 'package:flutter/material.dart';

/// The bottom wave that shapes the login screen's header artwork.
///
/// This file used to hold a whole illustration set — a zodiac emblem, a Taj
/// Mahal skyline, ribbon badges and painted couple/family portraits — built for
/// a role-card login design that no longer exists. Only the wave survived the
/// redesign, so only the wave is kept.

class LoginWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()..moveTo(0, size.height * 0.22);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.05,
        size.width * 0.5, size.height * 0.14);
    path.quadraticBezierTo(
        size.width * 0.78, size.height * 0.24, size.width, size.height * 0.08);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
