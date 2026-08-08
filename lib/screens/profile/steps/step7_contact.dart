import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/inline_validation.dart';
import '../../../core/utils/l10n_ext.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/value_l10n.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/gradient_button.dart';

/// Contact step — Contact Person Name (req), Relationship (req), Mobile Number
/// (req) and an optional WhatsApp number with a "same as mobile" toggle.
/// Mirrors the website's "Contact" step. Contact details are stored in the
/// access-gated `contacts/{userId}` record and only revealed after a mutual
/// interest — never on the public profile. Advancing goes to the Review step.
class Step7Contact extends ConsumerStatefulWidget {
  final VoidCallback onNext;

  const Step7Contact({super.key, required this.onNext});

  @override
  ConsumerState<Step7Contact> createState() => _Step7State();
}

class _Step7State extends ConsumerState<Step7Contact> {
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _emailController = TextEditingController();
  final _v = InlineValidation();
  final _nameFocus = FocusNode();
  final _mobileFocus = FocusNode();
  final _whatsappFocus = FocusNode();
  final _emailFocus = FocusNode();
  String _relationship = 'Self';
  bool _sameAsAbove = false;
  // Contact-sharing choice (§17). Default Private (only after accepted interest).
  String _contactPrivacy = 'private';

  // Matches the website RELATIONSHIP list.
  static const _relationships = [
    'Self', 'Father', 'Mother', 'Brother', 'Sister', 'Guardian',
    'Relative', 'Friend',
  ];

  @override
  void initState() {
    super.initState();
    final c = ref.read(profileCreationProvider).data['contactDetails'];
    if (c is Map) {
      _nameController.text = (c['contactPersonName'] as String?) ?? '';
      _relationship = (c['relationship'] as String?) ?? 'Self';
      _mobileController.text = (c['mobileNumber'] as String?) ?? '';
      final wa = (c['whatsappNumber'] as String?) ?? '';
      if (wa.isNotEmpty && wa == _mobileController.text) {
        _sameAsAbove = true;
      } else {
        _whatsappController.text = wa;
      }
      _emailController.text = (c['email'] as String?) ?? '';
    }
    _contactPrivacy =
        (ref.read(profileCreationProvider).data['contactPrivacy'] as String?) ??
            'private';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _whatsappController.dispose();
    _emailController.dispose();
    _nameFocus.dispose();
    _mobileFocus.dispose();
    _whatsappFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  void _saveAndNext() {
    final l10n = context.l10n;
    final v = context.validators;
    // Inline messages under each field + scroll to the first invalid one (§10).
    final nameError =
        v.requiredField(_nameController.text, l10n.contactPersonName);
    final mobileError = v.mobile(_mobileController.text);
    final whatsappError =
        _sameAsAbove ? null : v.optionalMobile(_whatsappController.text);
    final emailText = _emailController.text.trim();
    final emailError = emailText.isEmpty ? null : v.email(emailText);

    final checks = <FieldCheck>[
      FieldCheck(
          id: 'name',
          valid: nameError == null,
          message: nameError ?? '',
          focusNode: _nameFocus),
      FieldCheck(
          id: 'mobile',
          valid: mobileError == null,
          message: mobileError ?? '',
          focusNode: _mobileFocus),
      if (!_sameAsAbove)
        FieldCheck(
            id: 'whatsapp',
            valid: whatsappError == null,
            message: whatsappError ?? '',
            focusNode: _whatsappFocus),
      FieldCheck(
          id: 'email',
          valid: emailError == null,
          message: emailError ?? '',
          focusNode: _emailFocus),
    ];
    if (!_v.validate(context, checks, onChanged: () => setState(() {}))) return;

    ref.read(profileCreationProvider.notifier).updateData({
      'contactDetails': {
        'contactPersonName': _nameController.text.trim(),
        'relationship': _relationship,
        'mobileNumber': _mobileController.text.trim(),
        'whatsappNumber': _sameAsAbove
            ? _mobileController.text.trim()
            : _whatsappController.text.trim(),
        'email': _emailController.text.trim(),
      },
      'contactPrivacy': _contactPrivacy,
    });
    widget.onNext();
  }

  /// A selectable Private / Public contact-sharing option card.
  Widget _privacyOption({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _contactPrivacy == value;
    const maroon = Color(0xFF800020);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _contactPrivacy = value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? maroon.withValues(alpha: 0.06) : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? maroon : Colors.grey.shade300,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? maroon : Colors.grey[600], size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: selected ? maroon : Colors.black87)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? maroon : Colors.grey[400],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Builder(
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.contactDetails,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              l10n.contactStepSubtitle,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            AppTextField(
              key: _v.anchor('name'),
              controller: _nameController,
              focusNode: _nameFocus,
              label: '${l10n.contactPersonName} *',
              textCapitalization: TextCapitalization.words,
              errorText: _v.errorOf('name'),
              onChanged: (_) {
                if (_v.errorOf('name') != null) {
                  setState(() => _v.clear('name'));
                }
              },
            ),
            const SizedBox(height: 16),
            Text('${l10n.relationship} *',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _relationships
                  .map((r) => ChoiceChip(
                        // Stored value stays English; only the chip label is
                        // localized.
                        label: Text(context.localizeValue(r)),
                        selected: _relationship == r,
                        onSelected: (_) => setState(() => _relationship = r),
                        selectedColor: const Color(0xFF800020),
                        labelStyle: TextStyle(
                            color: _relationship == r
                                ? Colors.white
                                : Colors.black87),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            // Mobile Number (§4) — mandatory, digits ONLY, exactly 10.
            // `digitsOnly` strips letters/spaces/symbols as they are typed and
            // the length limiter caps at 10; the validator then refuses
            // anything shorter, so Continue is blocked until it is valid.
            AppTextField(
              key: _v.anchor('mobile'),
              controller: _mobileController,
              focusNode: _mobileFocus,
              label: '${l10n.mobileNumber} *',
              hint: '9876543210',
              keyboardType: TextInputType.number,
              prefixText: '+91 ',
              maxLength: 10,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              errorText: _v.errorOf('mobile'),
              onChanged: (_) {
                if (_v.errorOf('mobile') != null) {
                  setState(() => _v.clear('mobile'));
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: _sameAsAbove,
                  onChanged: (v) => setState(() => _sameAsAbove = v ?? false),
                ),
                Expanded(child: Text(l10n.whatsappSameAsMobile)),
              ],
            ),
            if (!_sameAsAbove) ...[
              AppTextField(
                key: _v.anchor('whatsapp'),
                controller: _whatsappController,
                focusNode: _whatsappFocus,
                label: l10n.whatsappNumber,
                hint: '9876543210',
                keyboardType: TextInputType.number,
                prefixText: '+91 ',
                maxLength: 10,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                // Optional field, but a partially-typed number is still invalid.
                errorText: _v.errorOf('whatsapp'),
                onChanged: (_) {
                  if (_v.errorOf('whatsapp') != null) {
                    setState(() => _v.clear('whatsapp'));
                  }
                },
              ),
            ],
            const SizedBox(height: 16),
            // Contact email (§5) — optional, and editable later from My
            // Profile like every other field.
            AppTextField(
              key: _v.anchor('email'),
              controller: _emailController,
              focusNode: _emailFocus,
              label: l10n.email,
              hint: 'name@example.com',
              keyboardType: TextInputType.emailAddress,
              errorText: _v.errorOf('email'),
              onChanged: (_) {
                if (_v.errorOf('email') != null) {
                  setState(() => _v.clear('email'));
                }
              },
            ),
            const SizedBox(height: 24),
            // ── Contact-sharing privacy choice (§17). Default Private. ──
            Text(
              context.l10n.contactSharingQuestion,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 10),
            _privacyOption(
              value: 'private',
              icon: Icons.lock_outline,
              title: context.l10n.contactPrivateTitle,
              subtitle: context.l10n.contactPrivateDesc,
            ),
            const SizedBox(height: 10),
            _privacyOption(
              value: 'public',
              icon: Icons.public,
              title: context.l10n.contactPublicTitle,
              subtitle: context.l10n.contactPublicDesc,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.security, color: Colors.green[600], size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.contactPrivacyNote,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                ),
              ],
            ),
            const SizedBox(height: 32),
            GradientButton(
                onPressed: _saveAndNext, text: l10n.continueLabel),
          ],
        ),
      ),
    );
  }
}
