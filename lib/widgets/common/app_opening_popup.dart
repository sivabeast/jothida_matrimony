import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/app_popup_model.dart';
import '../../providers/app_popup_provider.dart';
import '../../providers/auth_provider.dart';
import 'network_photo.dart';

/// Shows the app-opening popup once per launch, then advances the rotation so
/// the NEXT launch shows the next active content (spec §14).
///
/// Drop this into the Home screen's tree. It renders nothing itself — it just
/// watches for a popup to become available and opens a dialog over whatever is
/// on screen, so Home and its navigation keep working normally underneath.
class AppOpeningPopupHost extends ConsumerStatefulWidget {
  final Widget child;
  const AppOpeningPopupHost({super.key, required this.child});

  @override
  ConsumerState<AppOpeningPopupHost> createState() =>
      _AppOpeningPopupHostState();
}

class _AppOpeningPopupHostState extends ConsumerState<AppOpeningPopupHost> {
  /// Guards against opening two dialogs if the provider re-emits while the
  /// first is still on screen.
  bool _opening = false;

  Future<void> _show(AppPopupModel popup) async {
    if (_opening || !mounted) return;
    _opening = true;
    // Marked BEFORE the dialog opens: the popup counts as shown for this
    // session even if the user dismisses it instantly, so nothing can loop.
    ref.read(popupShownThisSessionProvider.notifier).state = true;
    final uid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ?? 'guest';
    await PopupRotationStore(uid).advance();
    if (!mounted) {
      _opening = false;
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AppPopupDialog(popup: popup),
    );
    _opening = false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AppPopupModel?>>(nextPopupProvider, (_, next) {
      final popup = next.valueOrNull;
      if (popup != null) {
        // After the frame: opening a dialog during build is illegal, and Home
        // must be laid out underneath before anything covers it.
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _show(popup));
      }
    });
    // Also handle the case where the value is already available on first build
    // (a warm provider cache), which `listen` alone would miss.
    final initial = ref.watch(nextPopupProvider).valueOrNull;
    if (initial != null && !_opening) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _show(initial));
    }
    return widget.child;
  }
}

/// The popup itself: optional artwork, title, body and a clear close control.
class _AppPopupDialog extends StatelessWidget {
  final AppPopupModel popup;
  const _AppPopupDialog({required this.popup});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (popup.hasImage)
                    AspectRatio(
                      aspectRatio: 5 / 3,
                      child: NetworkPhoto(
                          url: popup.imageUrl,
                          fallbackIcon: Icons.auto_awesome,
                          fallbackIconSize: 40),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        20, popup.hasImage ? 16 : 44, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (popup.title.trim().isNotEmpty)
                          Text(popup.title,
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary)),
                        if (popup.title.trim().isNotEmpty &&
                            popup.content.trim().isNotEmpty)
                          const SizedBox(height: 10),
                        if (popup.content.trim().isNotEmpty)
                          Text(popup.content,
                              style: const TextStyle(
                                  fontSize: 14, height: 1.55)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(context.l10n.close),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // The "×" — always available, over the artwork when there is one.
            Positioned(
              top: 6,
              right: 6,
              child: Material(
                color: popup.hasImage
                    ? Colors.black.withValues(alpha: 0.35)
                    : Colors.transparent,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: context.l10n.close,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close,
                      color: popup.hasImage ? Colors.white : Colors.grey[700]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
