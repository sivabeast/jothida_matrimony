import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/astrologer_session_provider.dart';

/// Edit the signed-in astrologer's profile: photo, experience, languages,
/// consultation fee, specializations and about. Persists via
/// `myAstrologerAccountProvider.saveProfile` (Firestore in prod).
class AstrologerEditProfileScreen extends ConsumerStatefulWidget {
  const AstrologerEditProfileScreen({super.key});

  @override
  ConsumerState<AstrologerEditProfileScreen> createState() =>
      _AstrologerEditProfileScreenState();
}

class _AstrologerEditProfileScreenState
    extends ConsumerState<AstrologerEditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _photo;
  late final TextEditingController _exp;
  late final TextEditingController _langs;
  late final TextEditingController _fee;
  late final TextEditingController _about;
  late Set<String> _specializations;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = ref.read(myAstrologerAccountProvider);
    _photo = TextEditingController(text: a?.photoUrl ?? '');
    _exp = TextEditingController(text: (a?.experienceYears ?? 0).toString());
    _langs = TextEditingController(text: (a?.languages ?? const []).join(', '));
    _fee = TextEditingController(
        text: (a?.consultationFee ?? 0).toStringAsFixed(0));
    _about = TextEditingController(text: a?.about ?? '');
    _specializations = {...?a?.expertise};
  }

  @override
  void dispose() {
    _photo.dispose();
    _exp.dispose();
    _langs.dispose();
    _fee.dispose();
    _about.dispose();
    super.dispose();
  }

  List<String> _splitCsv(String s) => s
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final account = ref.read(myAstrologerAccountProvider);
    if (account == null) return;

    setState(() => _saving = true);
    final updated = account.copyWith(
      photoUrl: _photo.text.trim(),
      experienceYears:
          int.tryParse(_exp.text.trim()) ?? account.experienceYears,
      languages: _splitCsv(_langs.text),
      consultationFee:
          double.tryParse(_fee.text.trim()) ?? account.consultationFee,
      about: _about.text.trim(),
      expertise: _specializations.toList(),
    );
    try {
      await ref
          .read(myAstrologerAccountProvider.notifier)
          .saveProfile(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated')));
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save — please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Union of the standard list and any custom specializations already set.
    final allSpecializations = <String>{
      ...AppConstants.astrologerSpecializations,
      ..._specializations,
    }.toList();

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Edit Profile'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field(_photo, 'Photo URL',
                hint: 'https://…', keyboard: TextInputType.url),
            if (_photo.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    backgroundImage: NetworkImage(_photo.text.trim()),
                    onBackgroundImageError: (_, __) {},
                  ),
                ),
              ),
            const SizedBox(height: 16),
            _field(_exp, 'Experience (years)',
                keyboard: TextInputType.number,
                digitsOnly: true,
                validator: (v) => int.tryParse(v?.trim() ?? '') == null
                    ? 'Enter a number'
                    : null),
            const SizedBox(height: 16),
            _field(_langs, 'Languages',
                hint: 'Comma separated, e.g. Tamil, English'),
            const SizedBox(height: 16),
            _field(_fee, 'Consultation Fee (₹)',
                keyboard: TextInputType.number,
                digitsOnly: true,
                validator: (v) => int.tryParse(v?.trim() ?? '') == null
                    ? 'Enter a number'
                    : null),
            const SizedBox(height: 20),
            const Text('Specializations',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in allSpecializations)
                  FilterChip(
                    label: Text(s, style: const TextStyle(fontSize: 12.5)),
                    selected: _specializations.contains(s),
                    selectedColor: AppColors.primary.withOpacity(0.15),
                    checkmarkColor: AppColors.primary,
                    onSelected: (sel) => setState(() {
                      if (sel) {
                        _specializations.add(s);
                      } else {
                        _specializations.remove(s);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _field(_about, 'About Me',
                hint: 'Tell users about your practice', maxLines: 4),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    int maxLines = 1,
    TextInputType? keyboard,
    bool digitsOnly = false,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        inputFormatters:
            digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
        validator: validator,
        onChanged: label == 'Photo URL' ? (_) => setState(() {}) : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
}
