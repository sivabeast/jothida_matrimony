import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/config/dev_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../models/astrologer_request_model.dart';
import '../../models/profile_model.dart';
import '../../providers/astrologer_session_provider.dart';
import '../../providers/match_analysis_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/rasi_chart.dart';
import '../../providers/service_providers.dart';

/// The astrologer's Match Analysis Workspace — opened from an ACCEPTED match
/// request. Shows the full GROOM and BRIDE details (incl. horoscope images &
/// PDFs) and lets the astrologer submit a report (text + images + PDFs), which
/// marks the request Completed.
class MatchWorkspaceScreen extends ConsumerStatefulWidget {
  final AstrologerRequestModel request;
  const MatchWorkspaceScreen({super.key, required this.request});

  @override
  ConsumerState<MatchWorkspaceScreen> createState() =>
      _MatchWorkspaceScreenState();
}

class _MatchWorkspaceScreenState extends ConsumerState<MatchWorkspaceScreen> {
  late final TextEditingController _report =
      TextEditingController(text: widget.request.analysisText);
  late final List<String> _existingImages = [...widget.request.analysisImages];
  late final List<String> _existingPdfs = [...widget.request.analysisPdfs];
  final List<File> _newImages = [];
  final List<File> _newPdfs = [];
  bool _submitting = false;
  bool _working = false; // accept / reject in flight

  @override
  void dispose() {
    _report.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty) return;
    setState(() => _newImages.addAll(picked.map((x) => File(x.path))));
  }

  Future<void> _pickPdfs() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
    );
    if (res == null) return;
    setState(() => _newPdfs.addAll(
        res.files.where((f) => f.path != null).map((f) => File(f.path!))));
  }

  Future<void> _submit() async {
    if (_report.text.trim().isEmpty &&
        _newImages.isEmpty &&
        _newPdfs.isEmpty &&
        _existingImages.isEmpty &&
        _existingPdfs.isEmpty) {
      _snack('Add a written analysis or at least one file before submitting.');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(matchAnalysisControllerProvider.notifier).submitAnalysis(
            requestId: widget.request.id,
            text: _report.text,
            newImages: _newImages,
            newPdfs: _newPdfs,
            existingImages: _existingImages,
            existingPdfs: _existingPdfs,
          );
      if (!mounted) return;
      _snack('Analysis submitted. The user can now read your report.');
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack('Could not submit the analysis. Please try again.');
    }
  }

  Future<void> _setStatus(AstrologerRequestStatus status) async {
    setState(() => _working = true);
    try {
      if (kBypassAuth) {
        ref
            .read(demoAstrologerRequestsProvider.notifier)
            .setStatus(widget.request.id, status);
      } else {
        await ref
            .read(astrologerServiceProvider)
            .updateRequestStatus(widget.request.id, status);
      }
      if (!mounted) return;
      _snack(status == AstrologerRequestStatus.accepted
          ? 'Request accepted — you can submit the analysis now.'
          : 'Request rejected.');
    } catch (_) {
      if (mounted) _snack('Could not update. Please try again.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _reject() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject request?'),
        content: const Text(
            'The user will see this request as rejected. You can\'t undo this.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Reject')),
        ],
      ),
    );
    if (ok == true) _setStatus(AstrologerRequestStatus.rejected);
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    // Live request (reflects accept/reject/complete), falling back to the
    // snapshot passed in when first opened.
    final r =
        ref.watch(astrologerRequestByIdProvider(widget.request.id)) ??
            widget.request;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Match Analysis'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _requesterCard(r),
          const SizedBox(height: 16),
          const _SectionTitle('🤵 Groom Details'),
          const SizedBox(height: 8),
          _PartyCard(profileId: r.groomProfileId, fallbackName: r.groomName),
          const SizedBox(height: 16),
          const _SectionTitle('👰 Bride Details'),
          const SizedBox(height: 8),
          _PartyCard(profileId: r.brideProfileId, fallbackName: r.brideName),
          const SizedBox(height: 16),
          const _SectionTitle('🔭 Compare Horoscopes'),
          const SizedBox(height: 8),
          _CompareSection(
              groomId: r.groomProfileId, brideId: r.brideProfileId),
          const SizedBox(height: 22),
          _actionSection(r),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  /// Status-aware action area: Accept/Reject while pending, the analysis editor
  /// once accepted (or completed), and a notice if rejected.
  Widget _actionSection(AstrologerRequestModel r) {
    switch (r.status) {
      case AstrologerRequestStatus.pending:
        return _pendingActions();
      case AstrologerRequestStatus.rejected:
        return _rejectedBanner();
      case AstrologerRequestStatus.accepted:
      case AstrologerRequestStatus.completed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle('🔮 Your Analysis'),
            const SizedBox(height: 8),
            _analysisEditor(r),
          ],
        );
    }
  }

  Widget _pendingActions() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Respond to this request',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 6),
            Text(
              'Review the groom & bride details above, then accept to start the '
              'analysis or reject the request.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _working ? null : _reject,
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _working
                        ? null
                        : () => _setStatus(AstrologerRequestStatus.accepted),
                    icon: _working
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check, size: 18),
                    label: const Text('Accept'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _rejectedBanner() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.error.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.cancel_outlined, color: AppColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text('You rejected this request.',
                  style: TextStyle(color: Colors.grey[800], fontSize: 13)),
            ),
          ],
        ),
      );

  Widget _requesterCard(AstrologerRequestModel r) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  backgroundImage: r.userPhotoUrl.isNotEmpty
                      ? NetworkImage(r.userPhotoUrl)
                      : null,
                  child: r.userPhotoUrl.isEmpty
                      ? const Icon(Icons.person, color: AppColors.primary)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Requested by ${r.userName}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(_statusLabel(r.status),
                          style: TextStyle(
                              fontSize: 12.5,
                              color: _statusColor(r.status),
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (r.amount > 0)
                  Text('₹${r.amount}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary)),
              ],
            ),
            if (r.message.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Note from user',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[600])),
                    const SizedBox(height: 4),
                    Text(r.message, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  Widget _analysisEditor(AstrologerRequestModel r) {
    final completed = r.status == AstrologerRequestStatus.completed;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (completed)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 16, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'Already submitted — you can update the report below.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[800])),
                  ),
                ],
              ),
            ),
          const Text('Detailed analysis',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _report,
            maxLines: 8,
            minLines: 5,
            decoration: InputDecoration(
              hintText:
                  'Write the porutham / compatibility analysis here…',
              filled: true,
              fillColor: Colors.grey[50],
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
          _attachmentSection(
            title: 'Images',
            icon: Icons.image_outlined,
            onAdd: _pickImages,
            existing: _existingImages,
            picked: _newImages,
            onRemoveExisting: (i) =>
                setState(() => _existingImages.removeAt(i)),
            onRemovePicked: (i) => setState(() => _newImages.removeAt(i)),
            isPdf: false,
          ),
          const SizedBox(height: 16),
          _attachmentSection(
            title: 'PDFs',
            icon: Icons.picture_as_pdf_outlined,
            onAdd: _pickPdfs,
            existing: _existingPdfs,
            picked: _newPdfs,
            onRemoveExisting: (i) => setState(() => _existingPdfs.removeAt(i)),
            onRemovePicked: (i) => setState(() => _newPdfs.removeAt(i)),
            isPdf: true,
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.task_alt),
              label: Text(_submitting
                  ? 'Submitting…'
                  : (completed ? 'Update Analysis' : 'Submit Analysis')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachmentSection({
    required String title,
    required IconData icon,
    required VoidCallback onAdd,
    required List<String> existing,
    required List<File> picked,
    required ValueChanged<int> onRemoveExisting,
    required ValueChanged<int> onRemovePicked,
    required bool isPdf,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const Spacer(),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ),
        if (existing.isEmpty && picked.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('No ${title.toLowerCase()} added yet.',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ),
        // Already-uploaded files (URLs).
        for (var i = 0; i < existing.length; i++)
          _fileChipRow(
            label: isPdf ? 'PDF ${i + 1}' : 'Image ${i + 1}',
            onRemove: () => onRemoveExisting(i),
          ),
        // Newly-picked local files (not uploaded yet).
        for (var i = 0; i < picked.length; i++)
          _fileChipRow(
            label: picked[i].path.split(Platform.pathSeparator).last,
            isNew: true,
            onRemove: () => onRemovePicked(i),
          ),
      ],
    );
  }

  Widget _fileChipRow({
    required String label,
    required VoidCallback onRemove,
    bool isNew = false,
  }) =>
      Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Icon(isNew ? Icons.upload_file_outlined : Icons.check_circle_outline,
                size: 16,
                color: isNew ? AppColors.info : AppColors.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5)),
            ),
            InkWell(
              onTap: onRemove,
              child: Icon(Icons.close, size: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );

  static String _statusLabel(AstrologerRequestStatus s) => s.label;
  static Color _statusColor(AstrologerRequestStatus s) {
    switch (s) {
      case AstrologerRequestStatus.pending:
        return AppColors.warning;
      case AstrologerRequestStatus.accepted:
        return AppColors.info;
      case AstrologerRequestStatus.completed:
        return AppColors.success;
      case AstrologerRequestStatus.rejected:
        return AppColors.error;
    }
  }
}

/// Side-by-side comparison of both parties' Rasi charts + key horoscope
/// attributes, so the astrologer can compare at a glance.
class _CompareSection extends ConsumerWidget {
  final String? groomId;
  final String? brideId;
  const _CompareSection({required this.groomId, required this.brideId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groom = (groomId == null || groomId!.isEmpty)
        ? null
        : ref.watch(profileByIdProvider(groomId!)).valueOrNull;
    final bride = (brideId == null || brideId!.isEmpty)
        ? null
        : ref.watch(profileByIdProvider(brideId!)).valueOrNull;
    if (groom == null && bride == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _chartCol('🤵 Groom', groom)),
              const SizedBox(width: 12),
              Expanded(child: _chartCol('👰 Bride', bride)),
            ],
          ),
          const SizedBox(height: 12),
          _compareRows(groom, bride),
        ],
      ),
    );
  }

  Widget _chartCol(String label, ProfileModel? p) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          if (p == null)
            Container(
                height: 80,
                alignment: Alignment.center,
                child: Text('Not available',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12)))
          else
            RasiChart(
                rasi: p.horoscope.rasi,
                lagnam: p.horoscope.lagnam,
                title: p.fullName),
        ],
      );

  Widget _compareRows(ProfileModel? g, ProfileModel? b) {
    Widget row(String label, String? gv, String? bv) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                    (gv ?? '').trim().isEmpty ? '—' : gv!.trim(),
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              Expanded(
                flex: 3,
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ),
              Expanded(
                flex: 4,
                child: Text(
                    (bv ?? '').trim().isEmpty ? '—' : bv!.trim(),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
    final gh = g?.horoscope, bh = b?.horoscope;
    return Column(
      children: [
        const Divider(),
        row('Rasi', gh?.rasi, bh?.rasi),
        row('Nakshatra', gh?.nakshatra, bh?.nakshatra),
        row('Lagnam', gh?.lagnam, bh?.lagnam),
        row('Dosham', gh?.dosham, bh?.dosham),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Poppins'));
}

/// Full detail card for one side of the match (groom or bride), with horoscope
/// images and PDFs the astrologer can open.
class _PartyCard extends ConsumerWidget {
  final String? profileId;
  final String? fallbackName;
  const _PartyCard({required this.profileId, this.fallbackName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (profileId == null || profileId!.isEmpty) {
      return _shell(child: Text(fallbackName ?? 'Profile unavailable'));
    }
    final async = ref.watch(profileByIdProvider(profileId!));
    return async.when(
      loading: () => _shell(
          child: const Center(
              child: Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(),
      ))),
      error: (_, __) => _shell(
          child: Text('Could not load ${fallbackName ?? 'profile'}')),
      data: (p) {
        if (p == null) {
          return _shell(
              child: Text(
                  '${fallbackName ?? 'This profile'} is no longer available.'));
        }
        return _shell(child: _details(context, p));
      },
    );
  }

  Widget _shell({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)
          ],
        ),
        child: child,
      );

  Widget _details(BuildContext context, ProfileModel p) {
    final h = p.horoscope;
    final dob = DateFormat('d MMM yyyy').format(p.dateOfBirth);
    final pdfs = h.allPdfUrls;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.primary.withOpacity(0.1),
              backgroundImage: (p.profilePhotoUrl ?? '').isNotEmpty
                  ? NetworkImage(p.profilePhotoUrl!)
                  : null,
              child: (p.profilePhotoUrl ?? '').isEmpty
                  ? const Icon(Icons.person, color: AppColors.primary)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(p.fullName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _row('Age', '${p.age} yrs'),
        _row('Date of Birth', dob),
        _row('Birth Time', h.birthTime),
        _row('Birth Place', h.birthPlace),
        _row('Rasi', h.rasi),
        _row('Nakshatra', h.nakshatra),
        if (h.lagnam.isNotEmpty) _row('Lagnam', h.lagnam),
        if (h.dosham.isNotEmpty) _row('Chevvai Dosham', h.dosham),
        _row('Education', p.education),
        _row('Occupation', p.occupation),
        const SizedBox(height: 12),
        _horoscopeFiles(context, h.horoscopeImages, pdfs),
        if (h.rasi.trim().isNotEmpty || h.lagnam.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          RasiChart(rasi: h.rasi, lagnam: h.lagnam),
        ],
      ],
    );
  }

  Widget _horoscopeFiles(
      BuildContext context, List<String> images, List<String> pdfs) {
    if (images.isEmpty && pdfs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('No horoscope files uploaded for this profile.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (images.isNotEmpty) ...[
          const Text('Horoscope Images',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
          const SizedBox(height: 6),
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => showImageGallery(context, images, initialIndex: i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    images[i],
                    width: 90,
                    height: 90,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 90,
                      height: 90,
                      color: AppColors.primary.withOpacity(0.08),
                      child: const Icon(Icons.broken_image_outlined,
                          color: AppColors.primary),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (pdfs.isNotEmpty) ...[
          const Text('Horoscope PDFs',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
          const SizedBox(height: 6),
          for (var i = 0; i < pdfs.length; i++)
            RemotePdfTile(
                url: pdfs[i], label: 'Horoscope PDF ${i + 1}', index: i),
        ],
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 110,
                child: Text(label,
                    style:
                        TextStyle(color: Colors.grey[600], fontSize: 12.5))),
            Expanded(
              child: Text(value.isEmpty ? '—' : value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13)),
            ),
          ],
        ),
      );
}
