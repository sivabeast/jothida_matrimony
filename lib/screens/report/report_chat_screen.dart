import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/dev_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../core/utils/value_l10n.dart';
import '../../models/report_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';
import '../../widgets/common/network_photo.dart';

/// Report a conversation (spec §7). Reached from the chat screen's overflow
/// menu. Registered at `/report-chat/:threadId` with `extra` carrying the other
/// participant's uid + name.
class ReportChatScreen extends ConsumerStatefulWidget {
  final String threadId;
  final String otherUid;
  final String otherName;

  const ReportChatScreen({
    super.key,
    required this.threadId,
    required this.otherUid,
    required this.otherName,
  });

  @override
  ConsumerState<ReportChatScreen> createState() => _ReportChatScreenState();
}

class _ReportChatScreenState extends ConsumerState<ReportChatScreen> {
  String? _reason;
  final TextEditingController _descCtrl = TextEditingController();
  String _screenshotUrl = '';
  bool _uploading = false;
  bool _submitting = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickScreenshot() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final url = await ref.read(storageServiceProvider).uploadChatAttachment(
          threadId: 'chat_report_media', file: File(picked.path), isImage: true);
      if (mounted) setState(() => _screenshotUrl = url);
    } catch (_) {
      _toast('Upload failed — please try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    if (_reason == null) {
      _toast(context.l10n.pleaseSelectReportReason);
      return;
    }
    setState(() => _submitting = true);
    final me = ref.read(currentUserProvider).valueOrNull;
    final myProfile = ref.read(myProfileProvider).valueOrNull;
    final report = ReportModel(
      id: 'chat_${DateTime.now().millisecondsSinceEpoch}',
      type: ReportModel.typeChat,
      reporterUserId: me?.uid ?? myProfile?.userId ?? 'unknown',
      reporterName: me?.displayName ?? myProfile?.name ?? 'Anonymous',
      reportedUserId: widget.otherUid,
      reportedProfileId: '',
      reportedName: widget.otherName,
      reason: _reason!,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      chatThreadId: widget.threadId,
      screenshotUrl: _screenshotUrl.isEmpty ? null : _screenshotUrl,
      alertLevel: 'normal',
      createdAt: DateTime.now(),
    );
    try {
      if (!kBypassAuth) {
        await ref.read(firestoreServiceProvider).submitReport(report);
      }
      if (mounted) {
        _toast(context.l10n.reportSubmittedChat);
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('[ReportChat] submit error: $e');
      if (mounted) _toast(context.l10n.couldNotSubmitReport);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(context.l10n.reportChatTitle),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.error.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.flag_outlined, color: AppColors.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.l10n.reportingChatInfo(widget.otherName),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(context.l10n.whyReportChat,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          ...AppConstants.chatReportReasons.map((r) => RadioListTile<String>(
                value: r,
                groupValue: _reason,
                activeColor: AppColors.primary,
                contentPadding: EdgeInsets.zero,
                title: Text(context.localizeValue(r)),
                onChanged: (v) => setState(() => _reason = v),
              )),
          const SizedBox(height: 8),
          Text(context.l10n.screenshotOptional,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          _screenshotRow(),
          const SizedBox(height: 16),
          TextField(
            controller: _descCtrl,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: context.l10n.additionalDetailsOptional,
              alignLabelWithHint: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: Text(_submitting
                  ? context.l10n.submittingLabel
                  : context.l10n.submitReport),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _screenshotRow() {
    if (_screenshotUrl.isNotEmpty) {
      return Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: NetworkPhoto(url: _screenshotUrl, width: 64, height: 64),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(context.l10n.screenshotAttached,
              style: const TextStyle(fontSize: 13, color: AppColors.success)),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: AppColors.error),
          onPressed: () => setState(() => _screenshotUrl = ''),
        ),
      ]);
    }
    return OutlinedButton.icon(
      onPressed: _uploading ? null : _pickScreenshot,
      icon: _uploading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.image_outlined, size: 18),
      label: Text(context.l10n.attachScreenshot),
      style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary)),
    );
  }
}
