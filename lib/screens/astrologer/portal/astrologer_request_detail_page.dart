import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_actions.dart';
import '../../../models/astrologer_request_model.dart';
import '../../../models/profile_model.dart';
import '../../../providers/astrology_team_provider.dart';
import '../../../providers/match_analysis_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../widgets/common/network_photo.dart';

/// Request details + report submission for the assigned astrologer (spec §9–§11).
///
/// Shows BOTH profiles (photo, DOB/TOB/POB, horoscope images + PDFs) and a
/// report-submission section (text + image + PDF) with Save Draft and a large
/// Submit Report button (validation: at least one of text/image/pdf).
class AstrologerRequestDetailPage extends ConsumerStatefulWidget {
  final String requestId;
  final AstrologerRequestModel? initial;
  const AstrologerRequestDetailPage({
    super.key,
    required this.requestId,
    this.initial,
  });

  @override
  ConsumerState<AstrologerRequestDetailPage> createState() =>
      _AstrologerRequestDetailPageState();
}

class _AstrologerRequestDetailPageState
    extends ConsumerState<AstrologerRequestDetailPage> {
  final _report = TextEditingController();
  final List<File> _newImages = [];
  final List<File> _newPdfs = [];
  List<String> _existingImages = const [];
  List<String> _existingPdfs = const [];
  bool _hydrated = false;
  bool _busy = false;

  @override
  void dispose() {
    _report.dispose();
    super.dispose();
  }

  void _hydrate(AstrologerRequestModel r) {
    if (_hydrated) return;
    _hydrated = true;
    _report.text = r.analysisText;
    _existingImages = [...r.analysisImages];
    _existingPdfs = [...r.analysisPdfs];
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

  bool get _hasAnyContent =>
      _report.text.trim().isNotEmpty ||
      _newImages.isNotEmpty ||
      _newPdfs.isNotEmpty ||
      _existingImages.isNotEmpty ||
      _existingPdfs.isNotEmpty;

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _saveDraft() async {
    if (!_hasAnyContent) {
      _snack('Nothing to save yet — add some analysis first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final res =
          await ref.read(matchAnalysisControllerProvider.notifier).saveDraft(
                requestId: widget.requestId,
                text: _report.text,
                newImages: _newImages,
                newPdfs: _newPdfs,
                existingImages: _existingImages,
                existingPdfs: _existingPdfs,
              );
      if (!mounted) return;
      setState(() {
        _existingImages = res.images;
        _existingPdfs = res.pdfs;
        _newImages.clear();
        _newPdfs.clear();
      });
      _snack('Draft saved. You can continue editing later.');
    } catch (_) {
      if (mounted) _snack('Could not save the draft. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_hasAnyContent) {
      _snack('Add a written analysis or at least one file before submitting.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(matchAnalysisControllerProvider.notifier).submitAnalysis(
            requestId: widget.requestId,
            text: _report.text,
            newImages: _newImages,
            newPdfs: _newPdfs,
            existingImages: _existingImages,
            existingPdfs: _existingPdfs,
          );
      if (!mounted) return;
      _snack('Report submitted. The user can now read it.');
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Could not submit the report. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(myAssignedRequestsProvider).valueOrNull ?? const [];
    AstrologerRequestModel? r;
    for (final x in list) {
      if (x.id == widget.requestId) {
        r = x;
        break;
      }
    }
    r ??= widget.initial;

    if (r == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Request'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    _hydrate(r);
    final completed = r.status == AstrologerRequestStatus.completed;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Request Details'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _requestHeader(r),
          const SizedBox(height: 14),
          if ((r.groomProfileId ?? '').isNotEmpty)
            _ProfileCard(
                title: 'Bride / Groom A',
                profileId: r.groomProfileId!,
                nameFallback: r.groomName ?? ''),
          if ((r.brideProfileId ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            _ProfileCard(
                title: 'Bride / Groom B',
                profileId: r.brideProfileId!,
                nameFallback: r.brideName ?? ''),
          ],
          const SizedBox(height: 18),
          if (completed)
            _completedNote()
          else
            _reportSection(),
        ],
      ),
    );
  }

  Widget _requestHeader(AstrologerRequestModel r) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Request ${r.id}',
                style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Text('Requested by ${r.userName}',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            if (r.message.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Note: ${r.message}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700])),
            ],
          ],
        ),
      );

  Widget _completedNote() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.verified, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text('Report submitted',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            if (_report.text.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_report.text, style: const TextStyle(fontSize: 13.5)),
            ],
            if (_existingImages.isNotEmpty || _existingPdfs.isNotEmpty) ...[
              const SizedBox(height: 10),
              _attachmentChips(_existingImages, _existingPdfs),
            ],
          ],
        ),
      );

  Widget _reportSection() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Submit Report',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Add a written analysis and/or attach images / PDFs.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
            const SizedBox(height: 12),
            TextField(
              controller: _report,
              minLines: 5,
              maxLines: 12,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Write the horoscope analysis here…',
                filled: true,
                fillColor: AppColors.scaffoldBg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pickImages,
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: Text('Images (${_newImages.length + _existingImages.length})'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pickPdfs,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: Text('PDFs (${_newPdfs.length + _existingPdfs.length})'),
                  ),
                ),
              ],
            ),
            if (_existingImages.isNotEmpty || _existingPdfs.isNotEmpty) ...[
              const SizedBox(height: 10),
              _attachmentChips(_existingImages, _existingPdfs),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _saveDraft,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    child: const Text('Save Draft'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Submit Report',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _attachmentChips(List<String> images, List<String> pdfs) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < images.length; i++)
            ActionChip(
              avatar: const Icon(Icons.image, size: 16),
              label: Text('Image ${i + 1}'),
              onPressed: () => openRemoteFile(context, images[i], pdf: false),
            ),
          for (var i = 0; i < pdfs.length; i++)
            ActionChip(
              avatar: const Icon(Icons.picture_as_pdf, size: 16),
              label: Text('PDF ${i + 1}'),
              onPressed: () => openRemoteFile(context, pdfs[i], pdf: true),
            ),
        ],
      );
}

/// One profile block — photo + DOB/TOB/POB + horoscope images / PDFs (spec §9).
class _ProfileCard extends ConsumerWidget {
  final String title;
  final String profileId;
  final String nameFallback;
  const _ProfileCard({
    required this.title,
    required this.profileId,
    required this.nameFallback,
  });

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileByIdProvider(profileId));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: async.when(
        loading: () => const SizedBox(
            height: 80,
            child: Center(
                child: CircularProgressIndicator(color: AppColors.primary))),
        error: (_, __) => Text('Could not load ${nameFallback.isEmpty ? title : nameFallback}'),
        data: (p) => _body(context, p),
      ),
    );
  }

  Widget _body(BuildContext context, ProfileModel? p) {
    final h = p?.horoscope;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: NetworkPhoto(
                  url: p?.profilePhotoUrl ?? '', width: 54, height: 54),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.primary)),
                  Text(p?.fullName ?? (nameFallback.isEmpty ? '—' : nameFallback),
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _kv('Date of Birth', p == null ? '—' : _date(p.dateOfBirth)),
        _kv('Time of Birth', (h?.birthTime.isNotEmpty ?? false) ? h!.birthTime : '—'),
        _kv('Place of Birth',
            (h?.birthPlace.isNotEmpty ?? false) ? h!.birthPlace : '—'),
        if (h != null) ...[
          if (h.horoscopeImages.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Horoscope Images',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < h.horoscopeImages.length; i++)
                  GestureDetector(
                    onTap: () =>
                        openRemoteFile(context, h.horoscopeImages[i], pdf: false),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: NetworkPhoto(
                          url: h.horoscopeImages[i], width: 64, height: 64),
                    ),
                  ),
              ],
            ),
          ],
          if (_pdfs(h).isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _pdfs(h).length; i++)
                  ActionChip(
                    avatar: const Icon(Icons.picture_as_pdf, size: 16),
                    label: Text('Horoscope PDF ${i + 1}'),
                    onPressed: () =>
                        openRemoteFile(context, _pdfs(h)[i], pdf: true),
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  List<String> _pdfs(HoroscopeDetails h) => [
        ...h.horoscopePdfUrls,
        if ((h.horoscopePdfUrl ?? '').isNotEmpty &&
            !h.horoscopePdfUrls.contains(h.horoscopePdfUrl))
          h.horoscopePdfUrl!,
      ];

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 110,
                child: Text(k,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[600]))),
            Expanded(
                child: Text(v,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600))),
          ],
        ),
      );
}
