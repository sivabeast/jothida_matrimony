import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/phone_utils.dart';
import '../../core/utils/validators.dart';

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
/// City / District / State before an astrology appointment is confirmed.
///
/// Name and Mobile are required even for a signed-in member: whatever is known
/// — from a matrimony profile, or from the Google/phone login — only PREFILLS
/// the form, and the visitor still has to confirm it. A booking can never be
/// submitted without a name and a valid 10-digit mobile number, because the
/// office rings the customer to agree the exact visit time.
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
  late final TextEditingController _city =
      TextEditingController(text: widget.initialCity.trim());
  late final TextEditingController _district =
      TextEditingController(text: widget.initialDistrict.trim());
  late final TextEditingController _state =
      TextEditingController(text: widget.initialState.trim());

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _city.dispose();
    _district.dispose();
    _state.dispose();
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
        city: _city.text.trim(),
        district: _district.text.trim(),
        state: _state.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Your Details',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'We need your name and mobile number to confirm the '
                'appointment — the office calls you to agree the exact time. '
                'A Matrimony Profile is not required.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v ?? '').trim().length < 2
                    ? 'Please enter your name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                textInputAction: TextInputAction.next,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Mobile Number *',
                  prefixIcon: Icon(Icons.phone_outlined),
                  prefixText: '+91 ',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => AppValidators.isValidMobile(v)
                    ? null
                    : 'Enter a valid 10-digit mobile number',
              ),
              const SizedBox(height: 18),
              Text('WHERE YOU ARE FROM (OPTIONAL)',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                      color: Colors.grey[600])),
              const SizedBox(height: 10),
              TextFormField(
                controller: _city,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'City',
                  prefixIcon: Icon(Icons.location_city_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _district,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'District',
                  prefixIcon: Icon(Icons.map_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _state,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'State',
                  prefixIcon: Icon(Icons.public_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Confirm Booking'),
        ),
      ],
    );
  }
}
