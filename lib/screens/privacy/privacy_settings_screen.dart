import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/service_providers.dart';

class PrivacySettingsScreen extends ConsumerStatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  ConsumerState<PrivacySettingsScreen> createState() => _PrivacyState();
}

class _PrivacyState extends ConsumerState<PrivacySettingsScreen> {
  Map<String, bool> _settings = {
    'hidePhone': false,
    'hideAddress': false,
    'hideFamilyDetails': false,
    'hideSalary': false,
    'hideHoroscope': false,
    'hideAdditionalPhotos': false,
  };
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final userId = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
    if (userId == null) return;
    final user = await ref.read(authRepositoryProvider).getUserModel(userId);
    if (user != null && mounted) {
      setState(() => _settings = Map<String, bool>.from(user.privacySettings));
    }
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    final userId = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
    if (userId == null) return;
    await ref.read(firestoreServiceProvider).updateProfile('', {});
    // Update user document
    await ref.read(firestoreServiceProvider)
        .updateProfile('', {'privacySettings': _settings});
    setState(() => _loading = false);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Privacy settings saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Settings'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Control what information is visible to others. Your name is always visible.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          _PrivacyTile(
            title: 'Hide Phone Number',
            subtitle: 'Phone revealed only after mutual interest acceptance',
            value: _settings['hidePhone'] ?? false,
            onChanged: (v) => setState(() => _settings['hidePhone'] = v),
          ),
          _PrivacyTile(
            title: 'Hide Address',
            subtitle: 'City is visible; full address is hidden',
            value: _settings['hideAddress'] ?? false,
            onChanged: (v) => setState(() => _settings['hideAddress'] = v),
          ),
          _PrivacyTile(
            title: 'Hide Family Details',
            subtitle: 'Family information is not shown on your profile',
            value: _settings['hideFamilyDetails'] ?? false,
            onChanged: (v) => setState(() => _settings['hideFamilyDetails'] = v),
          ),
          _PrivacyTile(
            title: 'Hide Salary',
            subtitle: 'Annual income range will not be displayed',
            value: _settings['hideSalary'] ?? false,
            onChanged: (v) => setState(() => _settings['hideSalary'] = v),
          ),
          _PrivacyTile(
            title: 'Hide Horoscope Details',
            subtitle: 'Only Rasi and Nakshatra will be visible',
            value: _settings['hideHoroscope'] ?? false,
            onChanged: (v) => setState(() => _settings['hideHoroscope'] = v),
          ),
          _PrivacyTile(
            title: 'Hide Additional Photos',
            subtitle: 'Only your profile photo will be visible',
            value: _settings['hideAdditionalPhotos'] ?? false,
            onChanged: (v) => setState(() => _settings['hideAdditionalPhotos'] = v),
          ),
        ],
      ),
    );
  }
}

class _PrivacyTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PrivacyTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
