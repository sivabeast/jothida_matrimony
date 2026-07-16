import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';

/// Standard Loading / Error(+Retry) / Data presentation for an [AsyncValue] —
/// so no screen can ever sit on an endless spinner. Loading shows a spinner
/// ONLY while genuinely loading; an error shows a friendly message with a
/// Retry action; data goes to [builder] (which renders its own empty state).
class AsyncStateView<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  /// Called by the Retry button (typically `() => ref.invalidate(provider)`).
  final VoidCallback? onRetry;

  /// Friendly error headline (the raw error is logged, never shown).
  final String errorTitle;

  const AsyncStateView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.errorTitle = 'Something went wrong',
  });

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) {
        debugPrint('[AsyncStateView] $errorTitle: $e');
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded,
                    size: 44, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(errorTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('Please check your connection and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
                if (onRetry != null) ...[
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
      data: builder,
    );
  }
}

/// A friendly centred empty/info state (icon + title + optional subtitle),
/// shared by list pages so "no data" never looks like a hang.
class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: AppColors.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w600)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
            ],
          ],
        ),
      ),
    );
  }
}
