import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/wedding_planning_template.dart';
import '../../core/theme/app_colors.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_section_pages.dart';

/// PLANNING — the template-driven starting point. Planning is NOT about
/// assigning people; it is only about SELECTING what this wedding needs.
///
/// The page shows research-backed categories (Venue, Food, Pooja, Jewellery…),
/// each with predefined items. Ticking an item AUTO-GENERATES a Task (no
/// manual typing for normal tasks). Un-ticking removes the auto-task if it has
/// no progress. Every category has exactly one "Add Custom Item", which is
/// also fed into a global learning system to improve the template over time.
class WeddingPlanningPage extends StatelessWidget {
  const WeddingPlanningPage({super.key});

  @override
  Widget build(BuildContext context) {
    return WeddingPageScaffold(
      title: 'Wedding Planning',
      builder: (_, __, wedding, identity) =>
          _PlanningBody(wedding: wedding, identity: identity),
    );
  }
}

class _PlanningBody extends ConsumerStatefulWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  const _PlanningBody({required this.wedding, required this.identity});

  @override
  ConsumerState<_PlanningBody> createState() => _PlanningBodyState();
}

class _PlanningBodyState extends ConsumerState<_PlanningBody> {
  // Which side these selections belong to: my side, or Common (=shared).
  late String _scope = 'shared';
  String _query = '';
  final _expanded = <String>{}; // expanded category keys

  WeddingModel get wedding => widget.wedding;
  WeddingIdentity get me => widget.identity;

  bool get _canSelect =>
      me.isSuperAdmin || me.can(WeddingPermissions.createTask);

  String _scopeLabel(String scope) => switch (scope) {
        'bride' => 'Bride',
        'groom' => 'Groom',
        _ => 'Common',
      };

  @override
  void initState() {
    super.initState();
    _scope = me.isSuperAdmin ? 'shared' : me.side;
  }

  @override
  Widget build(BuildContext context) {
    final template = ref.watch(weddingPlanTemplateProvider);
    final tasks = ref.watch(weddingChecklistProvider(wedding.id)).valueOrNull ??
        const <WeddingChecklistItem>[];
    // Selected template keys in the CURRENT scope.
    final selectedKeys = tasks
        .where((t) => t.scope == _scope && t.templateKey.isNotEmpty)
        .map((t) => t.templateKey)
        .toSet();

    final q = _query.trim().toLowerCase();
    final categories = q.isEmpty
        ? template
        : template
            .map((c) => WeddingPlanCategory(
                  key: c.key,
                  name: c.name,
                  icon: c.icon,
                  items: c.items
                      .where((i) =>
                          i.title.toLowerCase().contains(q) ||
                          c.name.toLowerCase().contains(q))
                      .toList(),
                ))
            .where((c) => c.items.isNotEmpty)
            .toList();

    final totalSelected = selectedKeys.length;

    return Column(
      children: [
        _scopeBar(),
        _searchBar(),
        if (totalSelected > 0) _selectionSummary(totalSelected),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (!_canSelect)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'You can browse the plan, but only members with the '
                    'Create Task permission can select items.',
                    style:
                        TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ),
              if (categories.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text('No planning items match "$_query".',
                        style: TextStyle(
                            color: Colors.grey[500], fontSize: 13)),
                  ),
                ),
              ...categories.map((c) => _categoryCard(c, selectedKeys)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Scope (Bride / Groom / Common) ────────────────────────────────────────

  Widget _scopeBar() {
    Widget chip(String scope, String label, String emoji) {
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
            child: Text('$emoji  $label',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : Colors.grey[700])),
          ),
        ),
      );
    }

    // A Super Admin can plan for either side or Common; a family member plans
    // for their own side or Common only.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          chip('shared', 'Common', '❤️'),
          const SizedBox(width: 8),
          if (me.isSuperAdmin || me.side == 'bride') ...[
            chip('bride', 'Bride', '👰'),
            const SizedBox(width: 8),
          ],
          if (me.isSuperAdmin || me.side == 'groom') chip('groom', 'Groom', '🤵'),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          hintText: 'Search planning items…',
          hintStyle: TextStyle(fontSize: 13, color: Colors.grey[500]),
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _selectionSummary(int count) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              size: 18, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count item${count == 1 ? '' : 's'} selected in '
              '${_scopeLabel(_scope)} — auto-added to Tasks.',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ── Category card (expandable, checkbox selection, progress) ──────────────

  Widget _categoryCard(WeddingPlanCategory category, Set<String> selectedKeys) {
    final expanded = _expanded.contains(category.key) || _query.isNotEmpty;
    final selectedInCat =
        category.items.where((i) => selectedKeys.contains(i.key)).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => expanded
                ? _expanded.remove(category.key)
                : _expanded.add(category.key)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        shape: BoxShape.circle),
                    child: Icon(category.icon,
                        color: AppColors.primary, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(category.name,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5)),
                        const SizedBox(height: 2),
                        Text(
                          selectedInCat == 0
                              ? '${category.items.length} items'
                              : '$selectedInCat selected · '
                                  '${category.items.length} items',
                          style: TextStyle(
                              color: selectedInCat > 0
                                  ? AppColors.success
                                  : Colors.grey[600],
                              fontSize: 11.5,
                              fontWeight: selectedInCat > 0
                                  ? FontWeight.w600
                                  : FontWeight.normal),
                        ),
                      ],
                    ),
                  ),
                  if (selectedInCat > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$selectedInCat',
                          style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.grey[500]),
                ],
              ),
            ),
          ),
          // Items
          if (expanded) ...[
            const Divider(height: 1),
            ...category.items.map((item) {
              final selected = selectedKeys.contains(item.key);
              return CheckboxListTile(
                value: selected,
                dense: true,
                activeColor: AppColors.primary,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(item.title,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal)),
                onChanged: _canSelect
                    ? (v) => _toggleItem(category, item, v ?? false)
                    : null,
              );
            }),
            // Exactly one "Add Custom Item" per category.
            if (_canSelect && me.can(WeddingPermissions.createTask))
              ListTile(
                dense: true,
                leading: const Icon(Icons.add_circle_outline,
                    color: AppColors.primary, size: 22),
                title: const Text('Add Custom Item',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
                onTap: () => _showAddCustom(category),
              ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleItem(
      WeddingPlanCategory category, WeddingPlanItem item, bool select) async {
    final controller = ref.read(weddingControllerProvider.notifier);
    if (select) {
      await controller.generatePlanTask(
        wedding.id,
        templateKey: item.key,
        title: item.title,
        category: category.name,
        scope: _scope,
        me: me,
      );
    } else {
      final removed = await controller.removePlanTask(
        wedding.id,
        templateKey: item.key,
        scope: _scope,
      );
      if (!removed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'This task is already assigned or completed — remove it from '
                'the Tasks page instead.')));
      }
    }
  }

  Future<void> _showAddCustom(WeddingPlanCategory category) async {
    final ctrl = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add to ${category.name}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Palm Leaf Umbrella (Kudai)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    await ref.read(weddingControllerProvider.notifier).addCustomPlanItem(
          wedding.id,
          categoryKey: category.key,
          categoryName: category.name,
          title: title,
          scope: _scope,
          me: me,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('"$title" added to ${category.name} and your Tasks.')));
    }
  }
}
