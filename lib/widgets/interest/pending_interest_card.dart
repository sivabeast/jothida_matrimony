import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';

/// Premium "someone is interested in you" card shown IN PLACE of the Send
/// Interest button whenever the viewed member already sent the signed-in user
/// a pending interest (spec: the receiver must only ever see Accept / Reject,
/// never a duplicate Send Interest).
///
/// Design notes:
///  • gold-gradient border + soft primary tint so it stands out from every
///    other action block;
///  • a subtle continuous pulse on the heart badge draws the eye without
///    being distracting;
///  • Reject and Accept Interest are EQUAL-width, equal-height buttons on one
///    balanced row — same corner radius, same 52pt target, one gutter between
///    them. Accept carries the brand gradient so it still reads as the primary
///    choice without stealing width from Reject.
class PendingInterestCard extends StatefulWidget {
  /// Display name of the member who sent the interest ('' → generic copy).
  final String name;

  /// When false the description line is hidden — for tight surfaces like the
  /// Matches swipe card.
  final bool compact;
  final Future<void> Function() onAccept;
  final Future<void> Function() onReject;

  const PendingInterestCard({
    super.key,
    required this.name,
    required this.onAccept,
    required this.onReject,
    this.compact = false,
  });

  @override
  State<PendingInterestCard> createState() => _PendingInterestCardState();
}

class _PendingInterestCardState extends State<PendingInterestCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = widget.name.trim().isEmpty
        ? l10n.pendingInterestTitleGeneric
        : l10n.pendingInterestTitle(widget.name.trim());

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
            offset: Offset(0, 14 * (1 - t)), child: child),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          gradient: AppColors.goldGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Container(
          padding: EdgeInsets.all(widget.compact ? 14 : 18),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkCard
                : const Color(0xFFFFFBF2),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Pulsing heart badge — the "notice me" element.
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) {
                      final v = Curves.easeInOut.transform(_pulse.value);
                      return Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.primaryGradient,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary
                                  .withValues(alpha: 0.25 + 0.30 * v),
                              blurRadius: 8 + 10 * v,
                              spreadRadius: 1 + 2 * v,
                            ),
                          ],
                        ),
                        child: Transform.scale(
                          scale: 1.0 + 0.10 * v,
                          child: const Icon(Icons.favorite,
                              color: Colors.white, size: 24),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.compact
                              ? l10n.awaitingYourResponse
                              : l10n.pendingInterestBody,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: widget.compact ? 14 : 18),
              // Balanced action row: two equal halves, identical height and
              // radius, one 12pt gutter. Nothing is wider or taller than its
              // partner — only colour separates primary from secondary.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Reject — present, readable, deliberately quiet.
                    Expanded(child: _rejectButton(l10n.reject)),
                    const SizedBox(width: 12),
                    // Accept Interest — same footprint, brand gradient.
                    Expanded(child: _acceptButton(l10n.acceptInterest)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const double _btnHeight = 52;
  static final BorderRadius _btnRadius = BorderRadius.circular(14);

  Widget _rejectButton(String label) => OutlinedButton(
        onPressed: _busy ? null : () => _run(widget.onReject),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          side: BorderSide(
              color: AppColors.textSecondary.withValues(alpha: 0.35),
              width: 1.4),
          minimumSize: const Size.fromHeight(_btnHeight),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: _btnRadius),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: 14.5,
          ),
        ),
      );

  Widget _acceptButton(String label) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: _btnRadius,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.32),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FilledButton(
          onPressed: _busy ? null : () => _run(widget.onAccept),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.transparent,
            disabledForegroundColor: Colors.white70,
            minimumSize: const Size.fromHeight(_btnHeight),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            shape: RoundedRectangleBorder(borderRadius: _btnRadius),
          ),
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite, size: 18),
                    const SizedBox(width: 7),
                    // Flexible so a long Tamil label shrinks the text rather
                    // than overflowing the equal-width half.
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      );
}
