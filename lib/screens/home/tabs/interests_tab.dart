import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/interest_model.dart';
import '../../../providers/interest_provider.dart';

class InterestsTab extends ConsumerStatefulWidget {
  const InterestsTab({super.key});

  @override
  ConsumerState<InterestsTab> createState() => _InterestsTabState();
}

class _InterestsTabState extends ConsumerState<InterestsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final received = ref.watch(receivedInterestsProvider);
    final sent = ref.watch(sentInterestsProvider);

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Received'),
            Tab(text: 'Sent'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _InterestList(asyncValue: received, isSent: false),
              _InterestList(asyncValue: sent, isSent: true),
            ],
          ),
        ),
      ],
    );
  }
}

class _InterestList extends ConsumerWidget {
  final AsyncValue<List<InterestModel>> asyncValue;
  final bool isSent;

  const _InterestList({required this.asyncValue, required this.isSent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return asyncValue.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (interests) {
        if (interests.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite_border, size: 72, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  isSent ? 'No interests sent yet' : 'No interests received yet',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: interests.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final interest = interests[i];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: const Icon(Icons.person, color: AppColors.primary),
              ),
              title: Text(
                isSent ? interest.receiverProfileId : interest.senderProfileId,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(_statusText(interest.status)),
              trailing: _buildTrailing(context, ref, interest),
              onTap: () => context.push(
                  '/profile/${isSent ? interest.receiverProfileId : interest.senderProfileId}'),
            );
          },
        );
      },
    );
  }

  String _statusText(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return '✓ Accepted';
      case 'rejected':
        return '✗ Declined';
      default:
        return status;
    }
  }

  Widget? _buildTrailing(BuildContext context, WidgetRef ref, InterestModel interest) {
    if (!isSent && interest.status == 'pending') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.check_circle, color: Colors.green),
            onPressed: () => ref.read(interestNotifierProvider.notifier).acceptInterest(interest.id),
          ),
          IconButton(
            icon: const Icon(Icons.cancel, color: Colors.red),
            onPressed: () => ref.read(interestNotifierProvider.notifier).rejectInterest(interest.id),
          ),
        ],
      );
    }
    final color = interest.status == 'accepted'
        ? Colors.green
        : interest.status == 'rejected'
            ? Colors.red
            : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        interest.status.toUpperCase(),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
