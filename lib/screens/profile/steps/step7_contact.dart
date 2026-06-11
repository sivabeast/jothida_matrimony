import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/validators.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';

class Step7Contact extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final bool isLoading;

  /// Overall upload progress (0..1) while [isLoading] is true.
  final double uploadProgress;

  /// Status text shown under the progress bar, e.g. "Uploading photo...".
  final String? uploadStatus;

  const Step7Contact({
    super.key,
    required this.onNext,
    this.isLoading = false,
    this.uploadProgress = 0,
    this.uploadStatus,
  });

  @override
  ConsumerState<Step7Contact> createState() => _Step7State();
}

class _Step7State extends ConsumerState<Step7Contact> {
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _relationship = 'Self';
  bool _sameAsAbove = false;

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  void _saveAndNext() {
    if (!_formKey.currentState!.validate()) return;
    ref.read(profileCreationProvider.notifier).updateData({
      'contactDetails': {
        'contactPersonName': _nameController.text.trim(),
        'relationship': _relationship,
        'mobileNumber': _mobileController.text.trim(),
        'whatsappNumber': _sameAsAbove
            ? _mobileController.text.trim()
            : _whatsappController.text.trim(),
      },
    });
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Contact Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Contact details are only shared after interest is mutually accepted.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            AppTextField(
              controller: _nameController,
              label: 'Contact Person Name *',
              validator: Validators.name,
            ),
            const SizedBox(height: 16),
            const Text('Relationship', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['Self', 'Father', 'Mother', 'Brother', 'Sister', 'Guardian']
                  .map((r) => ChoiceChip(
                        label: Text(r),
                        selected: _relationship == r,
                        onSelected: (_) => setState(() => _relationship = r),
                        selectedColor: const Color(0xFF800020),
                        labelStyle: TextStyle(
                            color: _relationship == r ? Colors.white : Colors.black87),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _mobileController,
              label: 'Mobile Number *',
              hint: '9876543210',
              keyboardType: TextInputType.number,
              prefixText: '+91 ',
              maxLength: 10,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              validator: Validators.phone,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: _sameAsAbove,
                  onChanged: (v) => setState(() => _sameAsAbove = v ?? false),
                ),
                const Text('WhatsApp same as mobile'),
              ],
            ),
            if (!_sameAsAbove) ...[
              AppTextField(
                controller: _whatsappController,
                label: 'WhatsApp Number',
                hint: '9876543210',
                keyboardType: TextInputType.number,
                prefixText: '+91 ',
                maxLength: 10,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                validator: Validators.phone,
              ),
            ],
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.security, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your phone number and address are hidden by default. They are only revealed when both parties accept each other\'s interest.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            if (widget.isLoading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: widget.uploadProgress > 0 ? widget.uploadProgress : null,
                  minHeight: 6,
                  backgroundColor: Colors.grey[200],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.uploadStatus ??
                    (widget.uploadProgress > 0
                        ? '${(widget.uploadProgress * 100).round()}%'
                        : 'Submitting...'),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
            GradientButton(
              onPressed: widget.isLoading ? null : _saveAndNext,
              isLoading: widget.isLoading,
              text: 'Submit Profile',
            ),
          ],
        ),
      ),
    );
  }
}
