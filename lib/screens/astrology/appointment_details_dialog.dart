import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/phone_utils.dart';
import '../../core/utils/validators.dart';

/// The two details an astrology appointment needs from the visitor.
class AppointmentContactDetails {
  final String name;

  /// 10 digits, no country code — the format the rest of the app stores.
  final String phone;

  const AppointmentContactDetails({
    required this.name,
    required this.phone,
  });
}

/// Asks for **Name · Mobile Number** before an astrology appointment is
/// confirmed.
///
/// Date of birth is deliberately NOT asked for: it is a matrimony-profile
/// field, and an astrology customer may never create one. The office takes any
/// birth details it needs for the chart at the visit itself, so demanding a DOB
/// here only stood between the customer and a booking.
///
/// Whatever IS known — from a matrimony profile, or from the Google/phone
/// login — prefills the form; the visitor only fills the gaps. Returns null
/// when cancelled.
Future<AppointmentContactDetails?> showAppointmentDetailsDialog(
  BuildContext context, {
  String initialName = '',
  String initialPhone = '',
}) {
  return showDialog<AppointmentContactDetails>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AppointmentDetailsDialog(
      initialName: initialName,
      initialPhone: initialPhone,
    ),
  );
}

class _AppointmentDetailsDialog extends StatefulWidget {
  final String initialName;
  final String initialPhone;

  const _AppointmentDetailsDialog({
    required this.initialName,
    required this.initialPhone,
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

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }


  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      AppointmentContactDetails(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
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
                'We need these to confirm your appointment. A Matrimony '
                'Profile is not required.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
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
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Mobile Number',
                  prefixIcon: Icon(Icons.phone_outlined),
                  prefixText: '+91 ',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => AppValidators.isValidMobile(v)
                    ? null
                    : 'Enter a valid 10-digit mobile number',
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
