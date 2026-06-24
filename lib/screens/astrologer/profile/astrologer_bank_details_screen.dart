import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers/astrologer_session_provider.dart';

/// Astrologer "Bank & Fee Details" — payout bank account / UPI plus the flat
/// consultation & match-analysis fees. Used for the weekly settlement payout
/// (no real payout pipeline yet; this records the details).
class AstrologerBankDetailsScreen extends ConsumerStatefulWidget {
  const AstrologerBankDetailsScreen({super.key});

  @override
  ConsumerState<AstrologerBankDetailsScreen> createState() =>
      _AstrologerBankDetailsScreenState();
}

class _AstrologerBankDetailsScreenState
    extends ConsumerState<AstrologerBankDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _holder;
  late final TextEditingController _bank;
  late final TextEditingController _account;
  late final TextEditingController _ifsc;
  late final TextEditingController _upi;
  late final TextEditingController _consultFee;
  late final TextEditingController _analysisFee;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = ref.read(myAstrologerAccountProvider);
    _holder = TextEditingController(text: a?.accountHolderName ?? '');
    _bank = TextEditingController(text: a?.bankName ?? '');
    _account = TextEditingController(text: a?.accountNumber ?? '');
    _ifsc = TextEditingController(text: a?.ifscCode ?? '');
    _upi = TextEditingController(text: a?.upiId ?? '');
    _consultFee = TextEditingController(
        text: (a?.consultationFee ?? 0) > 0
            ? (a!.consultationFee).round().toString()
            : '');
    _analysisFee = TextEditingController(
        text: (a?.matchAnalysisFee ?? 0) > 0
            ? a!.matchAnalysisFee.toString()
            : '');
  }

  @override
  void dispose() {
    for (final c in [
      _holder,
      _bank,
      _account,
      _ifsc,
      _upi,
      _consultFee,
      _analysisFee
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final a = ref.read(myAstrologerAccountProvider);
    if (a == null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(myAstrologerAccountProvider.notifier).saveAccount(
            a.copyWith(
              accountHolderName: _holder.text.trim(),
              bankName: _bank.text.trim(),
              accountNumber: _account.text.trim(),
              ifscCode: _ifsc.text.trim().toUpperCase(),
              upiId: _upi.text.trim(),
              consultationFee:
                  double.tryParse(_consultFee.text.trim()) ?? a.consultationFee,
              matchAnalysisFee:
                  int.tryParse(_analysisFee.text.trim()) ?? a.matchAnalysisFee,
            ),
          );
      messenger.showSnackBar(
          const SnackBar(content: Text('Bank & fee details saved.')));
      navigator.pop();
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Could not save. Please try again.')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Bank & Fee Details'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('Fees'),
            _field(_consultFee, 'Consultation Fee (₹)',
                icon: Icons.payments_outlined, number: true),
            _field(_analysisFee, 'Match Analysis Fee (₹)',
                icon: Icons.insights_outlined, number: true),
            const SizedBox(height: 8),
            _sectionTitle('Bank Details'),
            _field(_holder, 'Account Holder Name',
                icon: Icons.person_outline),
            _field(_bank, 'Bank Name', icon: Icons.account_balance_outlined),
            _field(_account, 'Account Number',
                icon: Icons.numbers, number: true),
            _field(_ifsc, 'IFSC Code', icon: Icons.qr_code, caps: true),
            _field(_upi, 'UPI ID', icon: Icons.alternate_email),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline,
                      size: 18, color: AppColors.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Payouts are settled weekly to the account / UPI above. '
                      'Provide either full bank details or a UPI ID.',
                      style:
                          TextStyle(fontSize: 12.5, color: Colors.grey[800]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 10),
        child: Text(t,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.primary)),
      );

  Widget _field(TextEditingController c, String label,
          {IconData? icon, bool number = false, bool caps = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          textCapitalization:
              caps ? TextCapitalization.characters : TextCapitalization.none,
          inputFormatters:
              number ? [FilteringTextInputFormatter.digitsOnly] : null,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: icon == null ? null : Icon(icon),
            filled: true,
            fillColor: Colors.white,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
}
