import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Shimmer skeleton loaders shared across the app so loading never means a
/// bare spinner. Wrap any placeholder layout in [SkeletonShimmer]; the leaf
/// shapes ([SkeletonBox], [SkeletonLine], [SkeletonCircle]) are plain grey
/// boxes that the shimmer sweep animates.
class SkeletonShimmer extends StatelessWidget {
  final Widget child;
  const SkeletonShimmer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: dark ? Colors.white10 : const Color(0xFFEDE4E6),
      highlightColor: dark ? Colors.white24 : const Color(0xFFFAF5F6),
      child: child,
    );
  }
}

class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class SkeletonLine extends StatelessWidget {
  final double? width;
  final double height;
  const SkeletonLine({super.key, this.width, this.height = 12});

  @override
  Widget build(BuildContext context) =>
      SkeletonBox(width: width, height: height, radius: height / 2);
}

class SkeletonCircle extends StatelessWidget {
  final double size;
  const SkeletonCircle({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
    );
  }
}

/// A generic list-row skeleton: avatar + two lines. Use [SkeletonList] for a
/// whole column of them.
class SkeletonListTile extends StatelessWidget {
  final bool showAvatar;
  const SkeletonListTile({super.key, this.showAvatar = true});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (showAvatar) ...[
            const SkeletonCircle(size: 48),
            const SizedBox(width: 12),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(width: 140, height: 14),
                SizedBox(height: 8),
                SkeletonLine(height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SkeletonList extends StatelessWidget {
  final int items;
  final bool showAvatar;
  const SkeletonList({super.key, this.items = 6, this.showAvatar = true});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Column(
        children: [
          for (var i = 0; i < items; i++) SkeletonListTile(showAvatar: showAvatar),
        ],
      ),
    );
  }
}

/// Horizontal profile-card strip skeleton (matches the home "New Profiles"
/// rail: card width 164, photo-heavy top, two text lines below).
class SkeletonProfileRail extends StatelessWidget {
  final double height;
  final double cardWidth;
  final int items;
  const SkeletonProfileRail({
    super.key,
    this.height = 274,
    this.cardWidth = 164,
    this.items = 3,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: SkeletonShimmer(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, __) => SizedBox(
            width: cardWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: SkeletonBox(width: cardWidth, height: double.infinity, radius: 16)),
                const SizedBox(height: 10),
                const SkeletonLine(width: 100, height: 13),
                const SizedBox(height: 7),
                const SkeletonLine(width: 70, height: 11),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width card skeleton (titled section placeholder).
class SkeletonCard extends StatelessWidget {
  final double height;
  const SkeletonCard({super.key, this.height = 120});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SkeletonShimmer(child: SkeletonBox(height: height, radius: 16)),
    );
  }
}
