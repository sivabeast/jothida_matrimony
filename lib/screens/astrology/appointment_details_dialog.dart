import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/phone_utils.dart';
import '../../core/utils/validators.dart';
import '../../models/location_model.dart';
import '../../widgets/common/place_picker_field.dart';

/// The details an astrology appointment needs from the visitor.
class AppointmentContactDetails {
  /// REQUIRED. Never empty — the form cannot be submitted without it.
  final String name;

  /// REQUIRED. 10 digits, no country code — the format the rest of the app
  /// stores. Never empty and always a valid Indian mobile number.
  final String phone;

  /// OPTIONAL location hierarchy, prefilled from the matrimony profile when the
  /// visitor has one. An astrology-only customer can leave these blank.
  final String city;
  final String district;
  final String state;

  const AppointmentContactDetails({
    required this.name,
    required this.phone,
    this.city = '',
    this.district = '',
    this.state = '',
  });
}

/// Asks for **Name · Mobile Number** (both MANDATORY) plus an optional
/// location before an astrology appointment is confirmed.
///
/// Everything the app already knows PREFILLS the form (spec §18): the
/// matrimony profile's name, mobile and location, falling back to the
/// Google/phone login. The visitor can edit any of it for THIS booking — and
/// those edits are used for the booking only; the member's profile is never
/// overwritten (spec §19).
///
/// Name and Mobile stay required even for a signed-in member: a booking can
/// never be submitted without a name and a valid 10-digit mobile number,
/// because the office rings the customer to agree the exact visit time.
///
/// Date of birth is deliberately NOT asked for: it is a matrimony-profile
/// field, and an astrology customer may never create one. The office takes any
/// birth details it needs for the chart at the visit itself.
///
/// Returns null when cancelled.
Future<AppointmentContactDetails?> showAppointmentDetailsDialog(
  BuildContext context, {
  String initialName = '',
  String initialPhone = '',
  String initialCity = '',
  String initialDistrict = '',
  String initialState = '',
}) {
  return showDialog<AppointmentContactDetails>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AppointmentDetailsDialog(
      initialName: initialName,
      initialPhone: initialPhone,
      initialCity: initialCity,
      initialDistrict: initialDistrict,
      initialState: initialState,
    ),
  );
}

class _AppointmentDetailsDialog extends StatefulWidget {
  final String initialName;
  final String initialPhone;
  final String initialCity;
  final String initialDistrict;
  final String initialState;

  const _AppointmentDetailsDialog({
    required this.initialName,
    required this.initialPhone,
    required this.initialCity,
    required this.initialDistrict,
    required this.initialState,
  });

  @override
  State<_AppointmentDetailsDialog> createState() =>
      _AppointmentDetailsDialogState();
}

/// The bare 10-digit local part of any stored form (`+91…`, `91…`, `0…`).
/// Returns '' when there is no usable 10-digit number.
String _localTenDigits(String raw) {
  final n = normalizeIndianPhone(raw);
  if (n.length == 12 && n.startsWith('91')) return n.substring(2);
  return n.length == 10 ? n : '';
}

class _AppointmentDetailsDialogState extends State<_AppointmentDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName.trim());
  // Normalised to the bare 10 local digits, so a stored '+91…' prefills
  // cleanly into a field that only accepts ten digits.
  late final TextEditingController _phone =
      TextEditingController(text: _localTenDigits(widget.initialPhone));
  /// The booking's location, prefilled from the profile and editable here.
  /// Held in local state so an edit never touches the profile document.
  late PlaceSelection _place = PlaceSelection(
    city: widget.initialCity.trim(),
    cityEn: widget.initialCity.trim(),
    district: widget.initialDistrict.trim(),
    districtEn: widget.initialDistrict.trim(),
    state: widget.initialState.trim().isEmpty
        ? TnState.nameEn
        : widget.initialState.trim(),
  );

  /// True when the profile/login supplied any of these values, which is what
  /// the "filled in from your profile" note refers to.
  bool get _prefilled =>
      widget.initialName.trim().isNotEmpty ||
      _localTenDigits(widget.initialPhone).isNotEmpty ||
      widget.initialCity.trim().isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _submit() {
    // The form validators are the ONLY gate: an invalid or empty name/mobile
    // can never reach the booking call.
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      AppointmentContactDetails(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        city: _place.city.trim(),
        district: _place.district.trim(),
        state: _place.city.trim().isEmpty ? '' : _place.state.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(context.l10n.yourDetailsTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.bookingContactIntro,
                style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
              ),
              // Auto-filled is not locked: the member may change any of it for
              // this booking, and their profile stays as it was (spec §19).
              if (_prefilled) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(context.l10n.bookingContactPrefilledNote,
                            style: TextStyle(
                                fontSize: 11.5,
                                height: 1.4,
                                color: Colors.grey[800])),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: context.l10n.nameRequiredLabel,
                  prefixIcon: const Icon(Icons.person_outline),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => (v ?? '').trim().length < 2
                    ? context.l10n.pleaseEnterYourName
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                textInputAction: TextInputAction.next,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: context.l10n.mobileNumberRequiredLabel,
                  prefixIcon: const Icon(Icons.phone_outlined),
                  prefixText: '+91 ',
                  counterText: '',
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => AppValidators.isValidMobile(v)
                    ? null
                    : context.l10n.enterValidMobile,
              ),
              const SizedBox(height: 18),
              Text(context.l10n.whereYouAreFrom,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                      color: Colors.grey[600])),
              const SizedBox(height: 10),
              // The app's ONE place picker (spec §31): City/Village + District
              // + State, so the office knows exactly where the visitor is from.
              PlacePickerField(
                label: context.l10n.location,
                value: _place.city.trim().isEmpty ? null : _place.display,
                onChanged: (p) => setState(() => _place = p),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: Text(context.l10n.confirmBooking),
        ),
      ],
    );
  }
}
