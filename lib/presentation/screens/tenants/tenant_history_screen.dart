import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/communication_utils.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/tenant.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/auth_providers.dart';
import '../../../providers/tenant_providers.dart';

/// Read-only archive of every tenant that has vacated, newest exit first.
class TenantHistoryScreen extends ConsumerWidget {
  const TenantHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(tenantHistoryProvider);
    final tenantsAsync = ref.watch(allTenantsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Past tenants')),
      body: tenantsAsync.isLoading
          ? const LoadingView(message: 'Loading past tenants…')
          : history.isEmpty
              ? const EmptyState(
                  icon: Icons.history,
                  title: 'No past tenants yet',
                  message: 'Tenants are retained here after they vacate, '
                      'together with their rent history and settlement '
                      'statement.',
                )
              : _HistoryView(history: history),
    );
  }
}

class _HistoryView extends ConsumerStatefulWidget {
  const _HistoryView({required this.history});

  final List<TenantHistory> history;

  @override
  ConsumerState<_HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends ConsumerState<_HistoryView> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _busy = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  List<TenantHistory> _filtered() {
    final sorted = <TenantHistory>[...widget.history]..sort(_byExitDesc);
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return sorted;
    return sorted.where((item) {
      final propertyName = item.property?.propertyName ?? '';
      return item.tenant.name.toLowerCase().contains(needle) ||
          propertyName.toLowerCase().contains(needle);
    }).toList(growable: false);
  }

  int _byExitDesc(TenantHistory a, TenantHistory b) {
    final aDate = a.tenant.exitDetails?.exitedAt ?? a.tenant.updatedAt;
    final bDate = b.tenant.exitDetails?.exitedAt ?? b.tenant.updatedAt;
    return bDate.compareTo(aDate);
  }

  Future<void> _shareStatement(TenantHistory item) async {
    final tenant = item.tenant;
    final property = item.property;
    final exit = tenant.exitDetails;
    if (exit == null || property == null) return;

    setState(() => _busy = true);
    try {
      final currency = ref.read(userProfileProvider).valueOrNull?.currency ??
          AppConstants.defaultCurrency;
      final bytes = await ref
          .read(settlementStatementBuilderProvider)
          .buildStatement(
            property: property,
            tenant: tenant,
            details: exit,
            currency: currency,
          );
      final safe = tenant.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final fileName = 'exit_statement_${safe.isEmpty ? 'tenant' : safe}_'
          '${DateTime.now().millisecondsSinceEpoch}.pdf';
      final path = await ref
          .read(exportFileSaverProvider)
          .save(fileName: fileName, bytes: bytes);
      await ref.read(exportFileSaverProvider).share(
            filePath: path,
            subject: 'Tenant exit settlement — ${tenant.name}',
            text: 'Exit & deposit settlement statement for ${tenant.name}.',
          );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not generate or share statement PDF.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _promptSettlementPayment(Tenant tenant) async {
    final exit = tenant.exitDetails;
    if (exit == null) return;
    final result = await showDialog<
        ({double amount, PaymentMethod method, String notes})>(
      context: context,
      builder: (context) => _RecordSettlementDialog(
        dueAmount: exit.amountDueFromTenant,
      ),
    );
    if (!mounted || result == null) return;

    setState(() => _busy = true);
    final ok = await ref
        .read(tenantControllerProvider.notifier)
        .recordPostExitSettlement(
          tenant: tenant,
          amountPaid: result.amount,
          paymentMethod: result.method,
          notes: result.notes,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Recorded ${Formatters.currency(result.amount)} settlement payment from ${tenant.name}.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Could not record settlement payment. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered();
    final totalPaid = widget.history.fold<double>(
      0,
      (sum, item) => sum + item.lifetimePaid,
    );

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            children: <Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Past tenants',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: AmountText(
                                text: '${widget.history.length}',
                                size: 22,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 44,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Lifetime rent collected',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: AmountText(
                                  text: Formatters.currency(totalPaid),
                                  size: 22,
                                  color: context.ledgerColors.income,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search by tenant or property',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Clear search',
                          onPressed: _clearSearch,
                        ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? EmptyState(
                  icon: Icons.search_off,
                  title: 'No matching tenants',
                  message: 'No past tenant matches “$_query”.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) =>
                      _historyCard(context, filtered[index]),
                ),
        ),
      ],
    );
  }

  Widget _historyCard(BuildContext context, TenantHistory item) {
    final theme = Theme.of(context);
    final tenant = item.tenant;
    final exit = tenant.exitDetails;
    final leaseEnd = tenant.leaseEndDate ?? exit?.exitedAt;
    final leaseWindow = '${Formatters.date(tenant.leaseStartDate)} – '
        '${leaseEnd == null ? 'present' : Formatters.date(leaseEnd)}';
    final propertyId = item.property?.propertyId ?? tenant.propertyId;

    return Card(
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: () => context.push(AppRoutes.property(propertyId)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                tenant.name,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _statusChip(context, tenant.status),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.property?.propertyName ?? 'Property',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          leaseWindow,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (exit != null)
                          Text(
                            'Exited ${Formatters.date(exit.exitedAt)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        if (tenant.phone.isNotEmpty ||
                            (tenant.email ?? '').isNotEmpty)
                          Text(
                            [
                              if (tenant.phone.isNotEmpty) tenant.phone,
                              if ((tenant.email ?? '').isNotEmpty)
                                tenant.email!,
                            ].join('  ·  '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        if (tenant.phone.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 6),
                          Row(
                            children: <Widget>[
                              InkWell(
                                borderRadius: BorderRadius.circular(4),
                                onTap: () => CommunicationUtils.openWhatsApp(
                                  context: context,
                                  phone: tenant.phone,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline,
                                      size: 14,
                                      color: context.ledgerColors.income,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'WhatsApp',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: context.ledgerColors.income,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              InkWell(
                                borderRadius: BorderRadius.circular(4),
                                onTap: () => CommunicationUtils.makePhoneCall(
                                  context: context,
                                  phone: tenant.phone,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.phone_outlined,
                                      size: 14,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Call',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (exit != null && item.property != null)
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      tooltip: 'Share settlement statement',
                      onPressed: _busy ? null : () => _shareStatement(item),
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit tenant details',
                    onPressed: () => context.push(
                      AppRoutes.editTenant(propertyId, tenant.tenantId),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.home_outlined),
                    tooltip: 'View property',
                    onPressed: () =>
                        context.push(AppRoutes.property(propertyId)),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            title: const Text('Settlement breakdown'),
            children: <Widget>[
              DetailRow(
                label: 'Lifetime paid',
                value: Formatters.currency(item.lifetimePaid),
                valueColor: context.ledgerColors.income,
              ),
              DetailRow(
                label: 'Transactions',
                value: '${item.transactionCount}',
              ),
              DetailRow(
                label: 'Advance deposit',
                value: Formatters.currency(exit?.advanceDeposit ?? 0),
              ),
              DetailRow(
                label: 'Deposit refunded',
                value: Formatters.currency(exit?.depositRefunded ?? 0),
                valueColor: context.ledgerColors.income,
              ),
              if ((exit?.amountPaidByTenant ?? 0) > 0)
                DetailRow(
                  label:
                      'Paid at exit (${exit?.paymentMethod?.label ?? 'Received'})',
                  value: Formatters.currency(exit!.amountPaidByTenant),
                  valueColor: context.ledgerColors.income,
                ),
              DetailRow(
                label: 'Due from tenant',
                value: Formatters.currency(exit?.amountDueFromTenant ?? 0),
                valueColor: context.ledgerColors.expense,
              ),
              if ((exit?.amountDueFromTenant ?? 0) > 0) ...<Widget>[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed:
                        _busy ? null : () => _promptSettlementPayment(tenant),
                    icon: const Icon(Icons.payment_outlined, size: 18),
                    label: const Text('Record settlement payment'),
                  ),
                ),
              ],
              if (exit != null) ...<Widget>[
                const Divider(),
                Text(
                  'Pending at exit',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                DetailRow(
                  label: 'Pending rent',
                  value: Formatters.currency(exit.pendingRent),
                ),
                DetailRow(
                  label: 'Pending maintenance',
                  value: Formatters.currency(exit.pendingMaintenance),
                ),
                DetailRow(
                  label: 'Pending electricity',
                  value: Formatters.currency(exit.pendingEb),
                ),
                if (exit.pendingOther > 0)
                  DetailRow(
                    label: 'Other dues',
                    value: Formatters.currency(exit.pendingOther),
                  ),
                DetailRow(
                  label: 'Total pending',
                  value: Formatters.currency(exit.totalPending),
                  emphasize: true,
                ),
                if (exit.deductions.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'Deductions',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  for (final deduction in exit.deductions)
                    DetailRow(
                      label: deduction.label.isEmpty
                          ? 'Deduction'
                          : deduction.label,
                      value: Formatters.currency(deduction.amount),
                    ),
                  DetailRow(
                    label: 'Total deductions',
                    value: Formatters.currency(exit.totalDeductions),
                    emphasize: true,
                  ),
                ],
                if (exit.deductionReason != null &&
                    exit.deductionReason!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'Reason: ${exit.deductionReason}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, TenantStatus status) {
    final isActive = status == TenantStatus.ACTIVE;
    final color = isActive
        ? context.ledgerColors.income
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _RecordSettlementDialog extends StatefulWidget {
  const _RecordSettlementDialog({required this.dueAmount});

  final double dueAmount;

  @override
  State<_RecordSettlementDialog> createState() =>
      _RecordSettlementDialogState();
}

class _RecordSettlementDialogState extends State<_RecordSettlementDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  final TextEditingController _notesController = TextEditingController();
  PaymentMethod _paymentMethod = PaymentMethod.UPI;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.dueAmount.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record settlement payment'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Total due: ${Formatters.currency(widget.dueAmount)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount received',
                  prefixText: '₹ ',
                ),
                validator: (val) {
                  final parsed = double.tryParse(val?.trim() ?? '');
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a valid amount';
                  }
                  if (parsed > widget.dueAmount) {
                    return 'Amount exceeds remaining due';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PaymentMethod>(
                initialValue: _paymentMethod,
                decoration: const InputDecoration(labelText: 'Payment method'),
                items: PaymentMethod.values.map((method) {
                  return DropdownMenuItem(
                    value: method,
                    child: Text(method.label),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _paymentMethod = val);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'e.g. Cleared EB & final dues',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final amount = double.parse(_amountController.text.trim());
            Navigator.pop(
              context,
              (
                amount: amount,
                method: _paymentMethod,
                notes: _notesController.text.trim(),
              ),
            );
          },
          child: const Text('Record'),
        ),
      ],
    );
  }
}
