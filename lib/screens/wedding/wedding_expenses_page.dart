import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/wedding_model.dart';
import '../../providers/wedding_provider.dart';
import 'wedding_section_pages.dart';

/// EXPENSE TRACKER — a separate module (budget never lives in the Gallery):
/// overall Budget, Spent, Remaining, category-wise breakdown and the full
/// payment history. The couple sets the budget; everyone records payments.
class WeddingExpensesPage extends StatelessWidget {
  const WeddingExpensesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return WeddingPageScaffold(
      title: 'Expense Tracker',
      builder: (_, __, wedding, identity) =>
          _ExpensesBody(wedding: wedding, identity: identity),
    );
  }
}

class _ExpensesBody extends ConsumerWidget {
  final WeddingModel wedding;
  final WeddingIdentity identity;
  const _ExpensesBody({required this.wedding, required this.identity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(weddingExpensesProvider(wedding.id));
    final expenses = expensesAsync.valueOrNull ?? const <WeddingExpense>[];
    final spent = expenses.fold<num>(0, (sum, e) => sum + e.amount);
    final budget = wedding.totalBudget;
    final remaining = budget - spent;

    // Category-wise totals, largest first.
    final byCategory = <String, num>{};
    for (final e in expenses) {
      byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
    }
    final categoryEntries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'wedding_expenses_fab',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
        onPressed: () => _showExpenseSheet(context, ref),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          // ── Budget / Spent / Remaining ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Wedding Budget',
                          style: TextStyle(
                              color: Colors.white,
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5)),
                    ),
                    if (identity.isSuperAdmin)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.edit, size: 15),
                        label:
                            Text(budget <= 0 ? 'Set Budget' : 'Change'),
                        onPressed: () => _showBudgetDialog(context, ref),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _stat('Budget', '₹$budget')),
                    const SizedBox(width: 8),
                    Expanded(child: _stat('Spent', '₹$spent')),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _stat(
                            remaining >= 0 ? 'Remaining' : 'Over Budget',
                            '₹${remaining.abs()}')),
                  ],
                ),
                if (budget > 0) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (spent / budget).clamp(0.0, 1.0).toDouble(),
                      minHeight: 9,
                      backgroundColor: Colors.white.withOpacity(0.25),
                      valueColor: AlwaysStoppedAnimation<Color>(
                          spent <= budget
                              ? Colors.white
                              : AppColors.error),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Category-wise expense ──
          if (categoryEntries.isNotEmpty) ...[
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Category-wise Expense',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  const SizedBox(height: 10),
                  ...categoryEntries.map((e) {
                    final ratio =
                        spent <= 0 ? 0.0 : (e.value / spent).toDouble();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(e.key,
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600)),
                              ),
                              Text('₹${e.value}',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 6,
                              backgroundColor: Colors.grey[200],
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.primary),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ── Payment history ──
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 0, 2, 8),
            child: Text('Payment History',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ),
          if (expenses.isEmpty)
            _card(
              child: Text(
                'No payments recorded yet. Add every advance and payment '
                'here to track the wedding spend.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12.5),
              ),
            )
          else
            ...expenses.map((e) => _expenseCard(context, ref, e)),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.85), fontSize: 10.5)),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
          ],
        ),
        child: child,
      );

  Widget _expenseCard(
      BuildContext context, WidgetRef ref, WeddingExpense expense) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Text('💸', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13.5)),
                Text(
                  '${expense.category} · '
                  '${expense.date.day}/${expense.date.month}/${expense.date.year}'
                  '${expense.paidBy.isNotEmpty ? ' · paid by ${expense.paidBy}' : ''}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11.5),
                ),
                if (expense.notes.isNotEmpty)
                  Text(expense.notes,
                      style:
                          TextStyle(color: Colors.grey[500], fontSize: 11)),
              ],
            ),
          ),
          Text('₹${expense.amount}',
              style: const TextStyle(
                  fontSize: 14,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 19, color: Colors.grey[500]),
            onSelected: (v) {
              if (v == 'edit') {
                _showExpenseSheet(context, ref, existing: expense);
              } else {
                ref
                    .read(weddingControllerProvider.notifier)
                    .deleteExpense(wedding.id, expense.id);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showBudgetDialog(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(
        text: wedding.totalBudget > 0 ? '${wedding.totalBudget}' : '');
    final value = await showDialog<num>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wedding Budget'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              prefixText: '₹ ', labelText: 'Total Budget'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () =>
                Navigator.pop(ctx, num.tryParse(ctrl.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    await ref
        .read(weddingControllerProvider.notifier)
        .setBudget(wedding.id, value);
  }

  void _showExpenseSheet(BuildContext context, WidgetRef ref,
      {WeddingExpense? existing}) {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final amountCtrl = TextEditingController(
        text: existing != null ? '${existing.amount}' : '');
    final paidByCtrl = TextEditingController(text: existing?.paidBy ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    String category = existing?.category ?? WeddingExpense.categories.first;
    DateTime date = existing?.date ?? DateTime.now();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(existing == null ? 'Add Expense' : 'Edit Expense',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: titleCtrl,
                    decoration: _input('Title (e.g. Hall advance)'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter a title'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: amountCtrl,
                          keyboardType: TextInputType.number,
                          decoration: _input('Amount (₹)'),
                          validator: (v) =>
                              num.tryParse((v ?? '').trim()) == null
                                  ? 'Enter the amount'
                                  : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: category,
                          decoration: _input('Category'),
                          items: WeddingExpense.categories
                              .map((c) => DropdownMenuItem(
                                  value: c, child: Text(c)))
                              .toList(),
                          onChanged: (v) =>
                              setSheetState(() => category = v ?? category),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(now.year - 2),
                        lastDate: DateTime(now.year + 2),
                      );
                      if (picked != null) setSheetState(() => date = picked);
                    },
                    child: InputDecorator(
                      decoration: _input('Payment Date'),
                      child: Text('${date.day}/${date.month}/${date.year}',
                          style: const TextStyle(fontSize: 13.5)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: paidByCtrl,
                      decoration: _input('Paid By (optional)')),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: notesCtrl,
                      decoration: _input('Notes (optional)')),
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
                            .saveExpense(
                              wedding.id,
                              expenseId: existing?.id,
                              title: titleCtrl.text.trim(),
                              category: category,
                              amount:
                                  num.parse(amountCtrl.text.trim()),
                              paidBy: paidByCtrl.text.trim(),
                              notes: notesCtrl.text.trim(),
                              date: date,
                              me: identity,
                            );
                        navigator.pop();
                      },
                      child: Text(existing == null
                          ? 'Add Expense'
                          : 'Save Expense'),
                    ),
                  ),
                ],
              ),
            ),
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
