import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_section_pages.dart';
import 'wedding_workspace_screen.dart' show weddingByLine;

/// DISCUSSION NOTES — planning discussions, side-private ('bride'/'groom')
/// until explicitly moved to Shared.
class WeddingNotesPage extends StatelessWidget {
  const WeddingNotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return WeddingPageScaffold(
      title: 'Discussion Notes',
      builder: (_, __, wedding, identity) =>
          _NotesBody(wedding: wedding, identity: identity),
    );
  }
}

class _NotesBody extends ConsumerStatefulWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  const _NotesBody({required this.wedding, required this.identity});

  @override
  ConsumerState<_NotesBody> createState() => _NotesBodyState();
}

class _NotesBodyState extends ConsumerState<_NotesBody> {
  late String _scope = widget.identity.side;

  WeddingModel get wedding => widget.wedding;
  WeddingIdentity get me => widget.identity;

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(weddingNotesProvider(wedding.id));
    final all = (notesAsync.valueOrNull ?? const <WeddingNote>[])
        .where((n) => me.visibleScopes.contains(n.scope))
        .toList();
    final notes = all.where((n) => n.scope == _scope).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'wedding_notes_fab',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('Add Note'),
        onPressed: () => _showNoteSheet(),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                _scopeChip(me.side,
                    me.side == 'groom' ? '🤵 Groom' : '👰 Bride'),
                const SizedBox(width: 10),
                _scopeChip('shared', '❤️ Shared'),
              ],
            ),
          ),
          Expanded(
            child: notesAsync.isLoading && all.isEmpty
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.primary))
                : notes.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.sticky_note_2_outlined,
                                  size: 56, color: Colors.grey[350]),
                              const SizedBox(height: 12),
                              Text(
                                _scope == 'shared'
                                    ? 'No shared notes yet — notes here are '
                                        'visible to both sides.'
                                    : 'No ${me.side}-side notes yet — these '
                                        'stay private until moved to Shared.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                        children: notes.map(_noteCard).toList(),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _scopeChip(String scope, String label) {
    final active = _scope == scope;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _scope = scope),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: active ? AppColors.primary : Colors.grey.shade300),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : Colors.grey[700])),
        ),
      ),
    );
  }

  Widget _noteCard(WeddingNote note) {
    final canManage = me.isSuperAdmin || note.createdByKey == me.key;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(note.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              if (canManage)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert,
                      size: 20, color: Colors.grey[500]),
                  onSelected: (v) {
                    switch (v) {
                      case 'edit':
                        _showNoteSheet(existing: note);
                      case 'share':
                        _confirmMoveToShared(note);
                      case 'delete':
                        _confirmDelete(note);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    if (note.scope != 'shared')
                      const PopupMenuItem(
                          value: 'share', child: Text('Move to Shared')),
                    const PopupMenuItem(
                        value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
          if (note.body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(note.body,
                style: TextStyle(
                    color: Colors.grey[800], fontSize: 12.5, height: 1.4)),
          ],
          const SizedBox(height: 8),
          Text('By ${weddingByLine(note.createdByName, note.updatedAt)}',
              style: TextStyle(color: Colors.grey[500], fontSize: 10.5)),
        ],
      ),
    );
  }

  Future<void> _confirmMoveToShared(WeddingNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to Shared?'),
        content:
            Text('"${note.title}" will become visible to BOTH sides.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Move to Shared'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(weddingControllerProvider.notifier)
        .moveNoteToShared(wedding.id, note, me);
  }

  Future<void> _confirmDelete(WeddingNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text('"${note.title}" will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(weddingControllerProvider.notifier)
        .deleteNote(wedding.id, note.id);
  }

  void _showNoteSheet({WeddingNote? existing}) {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final bodyCtrl = TextEditingController(text: existing?.body ?? '');
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existing == null ? 'Add Discussion Note' : 'Edit Note',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                existing != null
                    ? 'Editing "${existing.title}"'
                    : _scope == 'shared'
                        ? 'Visible to both sides.'
                        : 'Private to the ${me.side} side until moved to '
                            'Shared.',
                style: TextStyle(color: Colors.grey[600], fontSize: 11.5),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: titleCtrl,
                decoration: _input('Title'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a title' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: bodyCtrl,
                maxLines: 5,
                decoration: _input('Discussion / decision details'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    final navigator = Navigator.of(ctx);
                    await ref
                        .read(weddingControllerProvider.notifier)
                        .saveNote(
                          wedding.id,
                          noteId: existing?.id,
                          title: titleCtrl.text.trim(),
                          body: bodyCtrl.text.trim(),
                          scope: existing?.scope ?? _scope,
                          me: me,
                        );
                    navigator.pop();
                  },
                  child: Text(existing == null ? 'Add Note' : 'Save Note'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static InputDecoration _input(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}
