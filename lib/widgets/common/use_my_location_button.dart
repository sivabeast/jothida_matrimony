import 'package:flutter/material.dart';
import '../../core/services/location_service.dart';
import '../../core/theme/app_colors.dart';

/// Reusable "📍 Use My Location" control.
///
/// Tapping requests permission and detects the device location, then calls
/// [onDetected] with the country/state/city/lat/lng so the host form can fill
/// its fields. On success it shows "📍 City, State" underneath; on denial or
/// failure it shows a friendly message and the user can still select manually.
class UseMyLocationButton extends StatefulWidget {
  final ValueChanged<DetectedLocation> onDetected;

  /// "Use My Location" for new entries, "Update My Location" when editing.
  final String label;

  const UseMyLocationButton({
    super.key,
    required this.onDetected,
    this.label = 'Use My Location',
  });

  @override
  State<UseMyLocationButton> createState() => _UseMyLocationButtonState();
}

class _UseMyLocationButtonState extends State<UseMyLocationButton> {
  bool _busy = false;
  String? _detected; // "City, State"
  String? _error;

  Future<void> _detect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final loc = await LocationService().detect();
      if (!mounted) return;
      widget.onDetected(loc);
      setState(() => _detected =
          loc.display.isEmpty ? 'Location detected' : loc.display);
    } on LocationException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Location access denied. Please select your location manually.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : _detect,
          icon: _busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location, size: 18),
          label: Text(_busy ? 'Detecting…' : widget.label),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            minimumSize: const Size.fromHeight(44),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        if (_detected != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Row(
              children: [
                const Icon(Icons.place, size: 16, color: AppColors.primary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(_detected!,
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(_error!,
                style: const TextStyle(color: AppColors.error, fontSize: 12.5)),
          ),
      ],
    );
  }
}
