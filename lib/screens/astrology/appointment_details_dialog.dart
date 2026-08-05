import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/phone_utils.dart';
import '../../core/utils/validators.dart';

/// The three details an astrology appointment needs from the visitor.
class AppointmentContactDetails {
  final String name;

  /// 10 digits, no country code — the format the rest of the app stores.
  final String phone;

  final DateTime dob;

  const AppointmentContactDetails({
    required this.name,
    required this.phone,
    required this.dob,
  });

  /// `dd/MM/yyyy` — how the DOB is persisted on the booking.
  String get dobText =>
      '${dob.day.toString().padLeft(2, '0')}/${dob.month.toString().padLeft(2, '0')}/${dob.year}';
}

/// Asks for **Name · Mobile Number · Date of Birth** before an astrology
/// appointment is confirmed (spec §8).
///
/// An appointment never requires a matrimony profile, so these three fields
/// cannot be assumed to exist anywhere. Whatever IS known — from the matrimony
/// profile, or from the Google/phone login — prefills the form; the visitor
/// only fills the gaps. Returns null when cancelled.
Future<AppointmentContactDetails?> showAppointmentDetailsDialog(
  BuildContext context, {
  String initialName = '',
  String initialPhone = '',
  DateTime? initialDob,
}) {
  return showDialog<AppointmentContactDetails>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AppointmentDetailsDialog(
      initialName: initialName,
      initialPhone: initialPhone,
      initialDob: initialDob,
    ),
  );
}

class _AppointmentDetailsDialog extends StatefulWidget {
  final String initialName;
  final String initialPhone;
  final DateTime? initialDob;

  const _AppointmentDetailsDialog({
    required this.initialName,
    required this.initialPhone,
    required this.initialDob,
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
  late DateTime? _dob = widget.initialDob;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'Select Date of Birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_dob == null) {
      setState(() {}); // surfaces the date-field error text
      return;
    }
    Navigator.pop(
      context,
      AppointmentContactDetails(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        dob: _dob!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dobMissing = _dob == null;
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
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDob,
                borderRadius: BorderRadius.circular(4),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Date of Birth',
                    prefixIcon: const Icon(Icons.cake_outlined),
                    border: const OutlineInputBorder(),
                    errorText: dobMissing ? 'Please select your date of birth' : null,
                  ),
                  child: Text(
                    _dob == null
                        ? 'Select date'
                        : '${_dob!.day.toString().padLeft(2, '0')}/'
                            '${_dob!.month.toString().padLeft(2, '0')}/${_dob!.year}',
                    style: TextStyle(
                      fontSize: 15,
                      color: _dob == null ? Colors.grey[600] : Colors.black87,
                    ),
                  ),
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
