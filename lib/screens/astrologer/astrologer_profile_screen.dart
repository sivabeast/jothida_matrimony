import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_model.dart';
import '../../providers/astrologer_provider.dart';

/// Full astrologer profile: identity, services & pricing, reviews, and a
/// disabled "Astrologer Chat & Consultation — Coming Soon" section.
class AstrologerProfileScreen extends ConsumerWidget {
  final String astrologerId;
  const AstrologerProfileScreen({super.key, required this.astrologerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(astrologerByIdProvider(astrologerId));
    if (a == null) {
      return const Scaffold(body: Center(child: Text('Astrologer not found')));
    }
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 230,
            pinned: true,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: _headerBackground(a),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _statsRow(a),
                  const SizedBox(height: 16),
                  _section('About', Text(a.about, style: const TextStyle(height: 1.4))),
                  _section('Specializations', _chips(a.specializations)),
                  _section('Languages', _chips(a.languages)),
                  _section('Certifications',
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: a.certifications
                            .map((c) => Row(children: [
                                  const Icon(Icons.verified,
                                      size: 16, color: AppColors.success),
                                  const SizedBox(width: 6),
                                  Text(c),
                                ]))
                            .toList(),
                      )),
                  _section('Services & Pricing', _servicesList(a)),
                  _section('Reviews', _reviewsList(a)),
                  _comingSoonSection(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _bookingBar(context, a),
    );
  }

  Widget _headerBackground(Astrologer a) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primaryLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 10),
              CircleAvatar(
                radius: 46,
                backgroundColor: Colors.white,
                backgroundImage: NetworkImage(a.photoUrl),
                onBackgroundImageError: (_, __) {},
              ),
              const SizedBox(height: 10),
              Text(a.name,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: a.isAvailable ? AppColors.success : Colors.grey,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(a.isAvailable ? 'Available Now' : 'Offline',
                        style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _statsRow(Astrologer a) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _stat('${a.rating}', 'Rating', Icons.star, AppColors.gold),
            _stat('${a.reviewCount}', 'Reviews', Icons.reviews_outlined, AppColors.primary),
            _stat('${a.experienceYears} yrs', 'Experience', Icons.work_history_outlined,
                AppColors.info),
          ],
        ),
      );

  Widget _stat(String value, String label, IconData icon, Color color) => Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      );

  Widget _servicesList(Astrologer a) => Column(
        children: a.services
            .map((s) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (s.description.isNotEmpty)
                              Text(s.description,
                                  style:
                                      TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                      Text('₹${s.price}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppColors.primary)),
                    ],
                  ),
                ))
            .toList(),
      );

  Widget _reviewsList(Astrologer a) => Column(
        children: a.reviews
            .map((r) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: AppColors.primary.withOpacity(0.1),
                            child: Text(r.userName[0],
                                style: const TextStyle(
                                    color: AppColors.primary, fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          Text(r.userName,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          const Icon(Icons.star, size: 14, color: AppColors.gold),
                          Text(' ${r.rating}', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(r.comment,
                          style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                    ],
                  ),
                ))
            .toList(),
      );

  // ── Future feature placeholder ─────────────────────────────────────────
  // TODO(chat): implement real-time messaging, voice & video consultation
  // between users and astrologers (likely Firestore + a calling SDK).
  Widget _comingSoonSection() => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(Icons.chat_bubble_outline, size: 30, color: Colors.grey[500]),
            const SizedBox(height: 8),
            Text('Astrologer Chat & Consultation',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.grey[700])),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Coming Soon',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
            const SizedBox(height: 6),
            Text('Messaging, voice & video consultations will be available here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      );

  Widget _bookingBar(BuildContext context, Astrologer a) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Starting from', style: TextStyle(fontSize: 11)),
                  Text('₹${a.startingPrice}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: AppColors.primary)),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  // TODO(payment): wire to Razorpay consultation booking flow.
                  onPressed: () => _showBookingSheet(context, a),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Book Consultation'),
                ),
              ),
            ],
          ),
        ),
      );

  void _showBookingSheet(BuildContext context, Astrologer a) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select a Service',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...a.services.map((s) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.name),
                  subtitle: s.description.isNotEmpty ? Text(s.description) : null,
                  trailing: Text('₹${s.price}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: AppColors.primary)),
                  onTap: () {
                    Navigator.pop(context);
                    // TODO(payment): start Razorpay checkout for this service.
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Payment integration coming soon')),
                    );
                  },
                )),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );

  Widget _chips(List<String> items) => Wrap(
        spacing: 8,
        runSpacing: 4,
        children: items
            .map((e) => Chip(
                  label: Text(e),
                  backgroundColor: AppColors.primary.withOpacity(0.08),
                  side: BorderSide.none,
                ))
            .toList(),
      );
}
