import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/profile_provider.dart';

/// Personal Details — read-only view of the signed-in user's profile data.
/// Registered at `/personal-details`. Reached from Profile → "Personal Details".
class PersonalDetailsScreen extends ConsumerWidget {
  const PersonalDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[PersonalDetailsScreen] build — route /personal-details opened');
    final profileAsync = ref.watch(myProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Personal Details'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          profileAsync.maybeWhen(
            data: (p) => p == null
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => context.push('/profile/${p.id}/edit'),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => _Message(
          icon: Icons.error_outline,
          title: 'Could not load details',
          subtitle: '$e',
        ),
        data: (profile) {
          if (profile == null) {
            return _Message(
              icon: Icons.person_off_outlined,
              title: 'No profile yet',
              subtitle: 'Create your profile to see your personal details here.',
              actionLabel: 'Create Profile',
              onAction: () => context.push('/profile/create'),
            );
          }
          final f = profile.family;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Section(title: 'Basic Information', fields: [
                _Field('Full Name', profile.fullName),
                _Field('Gender', profile.gender),
                _Field('Date of Birth', _formatDate(profile.dateOfBirth)),
                _Field('Age', '${profile.age} yrs'),
                _Field('Height', profile.height),
                _Field('Weight', profile.weight),
                _Field('Marital Status', profile.maritalStatus),
                _Field('Mother Tongue', profile.motherTongue),
              ]),
              const SizedBox(height: 12),
              _Section(title: 'Religion & Community', fields: [
                _Field('Religion', profile.religion),
                _Field('Caste', profile.caste ?? ''),
                _Field('Sub Caste', profile.subCaste ?? ''),
              ]),
              const SizedBox(height: 12),
              _Section(title: 'Education & Career', fields: [
                _Field('Education', profile.education),
                _Field('Occupation', profile.occupation),
                _Field('Annual Income', profile.annualIncome),
              ]),
              const SizedBox(height: 12),
              _Section(title: 'Location', fields: [
                _Field('City', profile.city),
                _Field('State', profile.state),
                _Field('Country', profile.country),
              ]),
              const SizedBox(height: 12),
              _Section(title: 'Family', fields: [
                _Field('Father', _join(f.fatherName, f.fatherOccupation)),
                _Field('Mother', _join(f.motherName, f.motherOccupation)),
                _Field('Brothers', f.brothersCount.toString()),
                _Field('Sisters', f.sistersCount.toString()),
                _Field('Family Type', f.familyType),
                _Field('Family Status', f.familyStatus),
              ]),
              if ((profile.aboutMe ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                _Section(title: 'About Me', fields: [
                  _Field('', profile.aboutMe ?? ''),
                ]),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _join(String a, String b) {
    final left = a.trim();
    final right = b.trim();
    if (left.isEmpty && right.isEmpty) return '';
    if (right.isEmpty) return left;
    if (left.isEmpty) return right;
    return '$left ($right)';
  }

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
}

class _Field {
  final String label;
  final String value;
  const _Field(this.label, this.value);
}

class _Section extends StatelessWidget {
  final String title;
  final List<_Field> fields;
  const _Section({required this.title, required this.fields});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          const SizedBox(height: 8),
          ...fields.map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: f.label.isEmpty
                    ? Text(
                        f.value.trim().isEmpty ? '—' : f.value,
                        style: const TextStyle(fontSize: 13, height: 1.4),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              flex: 5,
                              child: Text(f.label,
                                  style: TextStyle(
                                      color: Colors.grey[600], fontSize: 13))),
                          Expanded(
                            flex: 6,
                            child: Text(
                              f.value.trim().isEmpty ? '—' : f.value,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
              )),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.primary.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600])),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
