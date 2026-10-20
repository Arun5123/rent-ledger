import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/communication_utils.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/services/ledger_calculator.dart';
import '../../../domain/models/ledger_transaction.dart';
import '../../../domain/models/property.dart';
import '../../../domain/models/tenant.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/auth_providers.dart';
import '../../../providers/property_providers.dart';
import '../../../providers/tenant_providers.dart';
import '../../../providers/transaction_providers.dart';
import '../transactions/transaction_entry_sheet.dart';

/// Full detail view for a single property: overview, transactions, tenant
/// history and documents, exposed as four tabs.
class PropertyDetailScreen extends ConsumerStatefulWidget {
  const PropertyDetailScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<PropertyDetailScreen> createState() =>
      _PropertyDetailScreenState();
}

/// Main shell with four tabs: overview, transactions, history, documents.
class _PropertyDetailScreenState extends ConsumerState<PropertyDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final property = ref.watch(propertyProvider(widget.propertyId));

    if (property == null) {
      final loading = ref.watch(propertiesProvider).isLoading;
      return Scaffold(
        appBar: AppBar(),
        body: loading
            ? const LoadingView()
            : const ErrorView(message: 'Property not found'),
      );
    }

    final activeTenant =
        ref.watch(activeTenantForPropertyProvider(widget.propertyId));

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(property.propertyName),
          actions: [
            PopupMenuButton<_PropertyMenuAction>(
              onSelected: (action) => _onMenu(action, property),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _PropertyMenuAction.edit,
                  child: Text('Edit property'),
                ),
                PopupMenuItem(
                  value: property.isArchived
                      ? _PropertyMenuAction.unarchive
                      : _PropertyMenuAction.archive,
                  child:
                      Text(property.isArchived ? 'Unarchive' : 'Archive'),
                ),
                const PopupMenuItem(
                  value: _PropertyMenuAction.delete,
                  child: Text('Delete permanently'),
                ),
              ],
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Transactions'),
              Tab(text: 'History'),
              Tab(text: 'Documents'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OverviewTab(property: property, activeTenant: activeTenant),
            _TransactionsTab(propertyId: widget.propertyId),
            _HistoryTab(property: property),
            _DocumentsTab(propertyId: widget.propertyId),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: null,
          onPressed: () => showTransactionEntrySheet(
            context,
            propertyId: widget.propertyId,
          ),
          icon: const Icon(Icons.add),
          label: const Text('Add entry'),
        ),
      ),
    );
  }

  void _onMenu(_PropertyMenuAction action, Property property) {
    switch (action) {
      case _PropertyMenuAction.edit:
        context.push(AppRoutes.editProperty(property.propertyId));
      case _PropertyMenuAction.archive:
      case _PropertyMenuAction.unarchive:
        _toggleArchive(property);
      case _PropertyMenuAction.delete:
        _confirmDelete(property);
    }
  }

  Future<void> _toggleArchive(Property property) async {
    final ok = await ref
        .read(propertyControllerProvider.notifier)
        .setArchived(property.propertyId, !property.isArchived);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? (property.isArchived
                ? '${property.propertyName} was restored.'
                : '${property.propertyName} was archived.')
            : 'Could not update the property. Please try again.'),
      ),
    );
  }

  Future<void> _confirmDelete(Property property) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) =>
          _DeletePropertyDialog(propertyName: property.propertyName),
    );
    if (confirmed != true || !mounted) return;

    final ok = await ref
        .read(propertyControllerProvider.notifier)
        .deleteCascade(property.propertyId);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${property.propertyName} was deleted.')),
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.properties);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete the property. Please try again.'),
        ),
      );
    }
  }
}

enum _PropertyMenuAction { edit, archive, unarchive, delete }

/// Rent + maintenance summary, tenant card and property metadata.
class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.property, required this.activeTenant});

  final Property property;
  final Tenant? activeTenant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref
            .watch(propertyTransactionsProvider(property.propertyId))
            .valueOrNull ??
        const <LedgerTransaction>[];
    final tenants = ref
            .watch(propertyTenantsProvider(property.propertyId))
            .valueOrNull ??
        const <Tenant>[];
    final offline = ref.watch(isOnlineProvider).valueOrNull == false;
    final theme = Theme.of(context);
    final active = activeTenant;
    final now = DateTime.now();
    final periodKey = Formatters.periodKey(now);

    final monthStart = Formatters.monthStart(now);
    final monthEnd = Formatters.monthEnd(now);

    double collectedThisMonth = 0;
    for (final txn in txns) {
      final at = txn.recordedAt;
      final matchesPeriod = (txn.billingPeriod.isNotEmpty && txn.billingPeriod == periodKey) ||
          (!at.isBefore(monthStart) && !at.isAfter(monthEnd));
      if (!matchesPeriod) continue;
      if (txn.isIncome) collectedThisMonth += txn.amount;
    }

    final double pendingThisMonth;
    if (active == null) {
      pendingThisMonth = 0;
    } else {
      pendingThisMonth = LedgerCalculator.dueForTenant(
            tenant: active,
            property: property,
            transactions: txns,
            month: now,
          )?.dueAmount ??
          0;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        OfflineBanner(visible: offline),
        _Card(
          onTap: active == null
              ? () => context.push(AppRoutes.newTenant(property.propertyId))
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                active == null ? 'No active tenant' : active.name,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                active == null
                    ? 'This unit is currently vacant.'
                    : [
                        if (active.phone.isNotEmpty) active.phone,
                        Formatters.date(active.leaseStartDate),
                      ].join('  ·  '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (active != null && active.phone.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      onPressed: () => CommunicationUtils.makePhoneCall(
                        context: context,
                        phone: active.phone,
                      ),
                      icon: const Icon(Icons.phone_outlined, size: 16),
                      label: const Text('Call'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      onPressed: () => CommunicationUtils.openWhatsApp(
                        context: context,
                        phone: active.phone,
                        message: pendingThisMonth > 0
                            ? CommunicationUtils.buildRentReminder(
                                tenantName: active.name,
                                propertyName: property.propertyName,
                                amountDue: pendingThisMonth,
                                billingPeriod:
                                    Formatters.monthLabel(periodKey),
                              )
                            : null,
                      ),
                      icon: Icon(
                        Icons.chat_bubble_outline,
                        size: 16,
                        color: context.ledgerColors.income,
                      ),
                      label: Text(
                        pendingThisMonth > 0
                            ? 'Remind on WhatsApp'
                            : 'WhatsApp',
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              if (active == null)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => context
                        .push(AppRoutes.newTenant(property.propertyId)),
                    icon: const Icon(Icons.person_add_outlined, size: 18),
                    label: const Text('Add tenant'),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push(
                          AppRoutes.editTenant(
                            property.propertyId,
                            active.tenantId,
                          ),
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit tenant'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => context.push(
                          AppRoutes.exitTenant(
                            property.propertyId,
                            active.tenantId,
                          ),
                        ),
                        icon: const Icon(Icons.logout, size: 18),
                        label: const Text('Exit'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        KpiCard(
          label: 'Collected · ${Formatters.monthLabel(periodKey)}',
          value: Formatters.currencyShort(collectedThisMonth),
          icon: Icons.savings_outlined,
          tint: context.ledgerColors.income,
        ),
        const SizedBox(height: 12),
        KpiCard(
          label: 'Pending · ${Formatters.monthLabel(periodKey)}',
          value: Formatters.currencyShort(pendingThisMonth),
          icon: Icons.schedule_outlined,
          tint: context.ledgerColors.pending,
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'Rent & maintenance'),
              const SizedBox(height: 8),
              DetailRow(
                  label: 'Status', value: property.currentStatus.label),
              DetailRow(
                  label: 'Rent / month',
                  value: Formatters.currency(property.baseRent)),
              DetailRow(
                  label: 'Maintenance / month',
                  value: Formatters.currency(property.baseMaintenance)),
              if (active != null)
                DetailRow(
                  label: 'Advance deposit',
                  value: Formatters.currency(active.advanceDepositAmount),
                ),
              DetailRow(
                label: 'Potential / month',
                value: Formatters.currency(property.monthlyPotentialRent),
                emphasize: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'Electricity'),
              const SizedBox(height: 8),
              DetailRow(
                  label: 'Billing',
                  value: property.electricityBillingType.label),
              if (property.electricityBillingType ==
                  ElectricityBillingType.SUB_METER) ...[
                DetailRow(
                  label: 'Last meter reading',
                  value: Formatters.units(property.currentEbMeterReading),
                ),
                DetailRow(
                  label: 'Rate / unit',
                  value: Formatters.currency(property.ratePerUnit),
                ),
              ],
              if (property.electricityBillingType ==
                  ElectricityBillingType.FIXED)
                DetailRow(
                  label: 'Fixed EB / month',
                  value: Formatters.currency(property.fixedEbAmount),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _updateMeterReading(context, ref),
                icon: const Icon(Icons.speed_outlined, size: 18),
                label: const Text('Update meter reading'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'Active tenant',
                trailing: active == null
                    ? null
                    : IconButton(
                        tooltip: 'Edit tenant details',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => context.push(
                          AppRoutes.editTenant(
                            property.propertyId,
                            active.tenantId,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              if (active == null)
                Text(
                  'Record the next occupant from the tenant card above.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DetailRow(label: 'Name', value: active.name),
                    DetailRow(
                        label: 'Phone',
                        value: active.phone.isEmpty ? '—' : active.phone),
                    if ((active.email ?? '').isNotEmpty)
                      DetailRow(label: 'Email', value: active.email!),
                    DetailRow(
                        label: 'Lease start',
                        value: Formatters.date(active.leaseStartDate)),
                    if (active.leaseEndDate != null)
                      DetailRow(
                          label: 'Lease end',
                          value: Formatters.date(active.leaseEndDate!)),
                    DetailRow(
                      label: 'Rent',
                      value:
                          Formatters.currency(active.rentFor(property.baseRent)),
                    ),
                    DetailRow(
                      label: 'Maintenance',
                      value: Formatters.currency(active.maintenanceFor(
                          property.baseMaintenance)),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => context.push(
                          AppRoutes.editTenant(
                            property.propertyId,
                            active.tenantId,
                          ),
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit tenant details'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: property.propertyName,
                subtitle:
                    '${property.address}, ${property.city} · ${property.type.label}',
              ),
              DetailRow(
                  label: 'Tenants on record', value: '${tenants.length}'),
              DetailRow(
                  label: 'Transactions', value: '${txns.length}'),
              if ((property.notes ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    property.notes!,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _updateMeterReading(
      BuildContext context, WidgetRef ref) async {
    final reading = await showDialog<double>(
      context: context,
      builder: (dialogContext) => _MeterReadingDialog(
          initialReading: property.currentEbMeterReading),
    );
    if (reading == null || !context.mounted) return;
    final ok = await ref
        .read(propertyControllerProvider.notifier)
        .updateMeterReading(property.propertyId, reading);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Meter reading updated.'
            : 'Could not update the reading. Please try again.'),
      ),
    );
  }
}
/// Latest-first ledger entries for this property, with edit and delete.
class _TransactionsTab extends ConsumerWidget {
  const _TransactionsTab({required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync =
        ref.watch(propertyTransactionsProvider(propertyId));
    final offline = ref.watch(isOnlineProvider).valueOrNull == false;

    return transactionsAsync.when(
      data: (transactions) {
        if (transactions.isEmpty) {
          return const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No entries yet',
            message: 'Record rent, maintenance and utility payments here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: transactions.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == 0) return OfflineBanner(visible: offline);
            final txn = transactions[index - 1];
            final theme = Theme.of(context);
            final color = txn.isIncome
                ? context.ledgerColors.income
                : context.ledgerColors.expense;
            return _Card(
              onTap: () => showTransactionEntrySheet(
                context,
                propertyId: propertyId,
                existing: txn,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${txn.type.label} · ${Formatters.date(txn.recordedAt)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if ((txn.tenantName ?? '').isNotEmpty) txn.tenantName!,
                      txn.paymentMethod.label,
                    ].join('  ·  '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AmountText(
                    text:
                        '${txn.isIncome ? '+' : '-'}${Formatters.currency(txn.amount)}',
                    color: color,
                    size: 17,
                  ),
                  if (txn.expenseCategory != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        txn.expenseCategory!.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  if (txn.meterPhotoUrl != null &&
                      txn.meterPhotoUrl!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => _DocumentViewerPage.open(
                        context,
                        title: 'Meter reading photo',
                        url: txn.meterPhotoUrl!,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.speed_outlined,
                              size: 14, color: theme.colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            'View meter photo',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if ((txn.notes ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      txn.notes!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => showTransactionEntrySheet(
                          context,
                          propertyId: propertyId,
                          existing: txn,
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit'),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          final prop = ref.read(propertyProvider(propertyId));
                          final propName = prop?.propertyName ?? 'Property';
                          final msg = CommunicationUtils.buildReceiptMessage(
                            tenantName: txn.tenantName ?? 'Tenant',
                            propertyName: propName,
                            amount: txn.amount,
                            typeLabel: txn.type.label,
                            date: txn.recordedAt,
                            paymentMethodLabel: txn.paymentMethod.label,
                            billingPeriod: txn.billingPeriod,
                          );
                          CommunicationUtils.shareText(
                            text: msg,
                            subject: 'Receipt: $propName - ${txn.type.label}',
                          );
                        },
                        icon: const Icon(Icons.share_outlined, size: 16),
                        label: const Text('Share'),
                      ),
                      TextButton.icon(
                        onPressed: () => _confirmDelete(context, ref, txn),
                        icon: Icon(Icons.delete_outline,
                            size: 16, color: theme.colorScheme.error),
                        label: Text('Delete',
                            style:
                                TextStyle(color: theme.colorScheme.error)),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const LoadingView(message: 'Loading entries…'),
      error: (error, _) => ErrorView(
        message: error is AppException
            ? error.message
            : 'Could not load entries.',
        onRetry: () =>
            ref.invalidate(propertyTransactionsProvider(propertyId)),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    LedgerTransaction txn,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
            'Delete the ${txn.type.label.toLowerCase()} entry of '
            '${Formatters.currency(txn.amount)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok =
        await ref.read(transactionControllerProvider.notifier).delete(txn);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Entry deleted.'
            : 'Could not delete the entry. Please try again.'),
      ),
    );
  }
}
/// Every tenant linked to this property, newest first.
class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantsAsync =
        ref.watch(propertyTenantsProvider(property.propertyId));
    final offline = ref.watch(isOnlineProvider).valueOrNull == false;

    return tenantsAsync.when(
      data: (tenants) {
        if (tenants.isEmpty) {
          return const EmptyState(
            icon: Icons.group_outlined,
            title: 'No tenants yet',
            message: 'Tenants appear here once they are onboarded.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: tenants.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == 0) return OfflineBanner(visible: offline);
            final tenant = tenants[index - 1];
            final theme = Theme.of(context);
            return _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tenant.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${tenant.status.label} · ${Formatters.date(tenant.leaseStartDate)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (tenant.phone.isNotEmpty || (tenant.email ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (tenant.phone.isNotEmpty) tenant.phone,
                        if ((tenant.email ?? '').isNotEmpty) tenant.email!,
                      ].join('  ·  '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  DetailRow(
                    label: 'Advance',
                    value: Formatters.currency(tenant.advanceDepositAmount),
                  ),
                  if (tenant.exitDetails != null) ...[
                    DetailRow(
                      label: 'Exited',
                      value: Formatters.date(tenant.exitDetails!.exitedAt),
                    ),
                    if (tenant.exitDetails!.depositRefunded > 0)
                      DetailRow(
                        label: 'Refunded',
                        value: Formatters.currency(
                            tenant.exitDetails!.depositRefunded),
                      ),
                    if (tenant.exitDetails!.amountPaidByTenant > 0)
                      DetailRow(
                        label: 'Paid at exit',
                        value: Formatters.currency(
                            tenant.exitDetails!.amountPaidByTenant),
                        valueColor: context.ledgerColors.income,
                      ),
                    if (tenant.exitDetails!.amountDueFromTenant > 0)
                      DetailRow(
                        label: 'Due from tenant',
                        value: Formatters.currency(
                            tenant.exitDetails!.amountDueFromTenant),
                        valueColor: context.ledgerColors.expense,
                      ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push(
                            AppRoutes.editTenant(
                              property.propertyId,
                              tenant.tenantId,
                            ),
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit details'),
                        ),
                      ),
                      if (tenant.isActive) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => context.push(
                              AppRoutes.exitTenant(
                                property.propertyId,
                                tenant.tenantId,
                              ),
                            ),
                            icon: const Icon(Icons.logout, size: 18),
                            label: const Text('Exit tenant'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const LoadingView(message: 'Loading tenants…'),
      error: (error, _) => ErrorView(
        message: error is AppException
            ? error.message
            : 'Could not load tenants.',
        onRetry: () =>
            ref.invalidate(propertyTenantsProvider(property.propertyId)),
      ),
    );
  }
}

/// Documents for one property — photos plus every tenant ID proof.
class _DocumentsTab extends ConsumerStatefulWidget {
  const _DocumentsTab({required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends ConsumerState<_DocumentsTab> {
  bool _uploading = false;
  @override
  Widget build(BuildContext context) {
    final property = ref.watch(propertyProvider(widget.propertyId));
    final tenants = ref
            .watch(propertyTenantsProvider(widget.propertyId))
            .valueOrNull ??
        const <Tenant>[];
    final photos = property?.photos ?? const <String>[];

    final allTenantDocs = <({Tenant tenant, TenantDocument doc})>[];
    for (final t in tenants) {
      final docUrls = <String>{};
      for (final d in t.documents) {
        docUrls.add(d.url);
        allTenantDocs.add((tenant: t, doc: d));
      }
      if (t.idProofUrl != null &&
          t.idProofUrl!.isNotEmpty &&
          !docUrls.contains(t.idProofUrl)) {
        allTenantDocs.add((
          tenant: t,
          doc: TenantDocument(
            id: 'legacy_id_proof',
            name: 'ID Proof',
            url: t.idProofUrl!,
            uploadedAt: t.createdAt,
          ),
        ));
      }
    }

    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Property photos',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _uploading ? null : _addPhoto,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text('Add photo'),
            ),
          ),
          const SizedBox(height: 12),
          if (photos.isEmpty)
            const _EmptyDocNote(
              icon: Icons.photo_library_outlined,
              text:
                  'No photos yet. Add pictures of the property for your records.',
            )
          else
            SizedBox(
              width: double.infinity,
              height: ((photos.length + 1) ~/ 2) * 170.0,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: photos.length,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.6,
                ),
                itemBuilder: (context, index) => _DocumentThumbWithRemove(
                  url: photos[index],
                  title: 'Property photo ${index + 1} of ${photos.length}',
                  onRemove: () => _removePhoto(index),
                ),
              ),
            ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tenant documents & agreements',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rental agreements, ID proofs, and tenancy verification.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (tenants.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _uploading ? null : _addTenantDocument,
                icon: const Icon(Icons.note_add_outlined, size: 18),
                label: const Text('Add document / agreement'),
              ),
            ),
          const SizedBox(height: 12),
          if (tenants.isEmpty)
            const _EmptyDocNote(
              icon: Icons.badge_outlined,
              text: 'No tenants yet. Onboard a tenant to add documents.',
            )
          else if (allTenantDocs.isEmpty)
            const _EmptyDocNote(
              icon: Icons.description_outlined,
              text:
                  'No tenant documents yet. Add a rental agreement, ID proof, or police verification.',
            )
          else
            ...allTenantDocs.map(
              (item) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    leading: _DocumentThumb(
                      url: item.doc.url,
                      title: '${item.tenant.name} — ${item.doc.name}',
                      borderRadius: 8,
                      width: 48,
                      height: 48,
                    ),
                    title: Text(
                      item.doc.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${item.tenant.name} (${item.tenant.status.label}) • '
                      '${Formatters.date(item.doc.uploadedAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          color: theme.colorScheme.error,
                          onPressed: () =>
                              _removeTenantDocument(item.tenant, item.doc),
                          tooltip: 'Remove document',
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () => _DocumentViewerPage.open(
                      context,
                      title: '${item.tenant.name} — ${item.doc.name}',
                      url: item.doc.url,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
  Future<void> _addPhoto() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    final source = await pickImageSource(context);
    if (source == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final picked = await pickImageSafely(
        context,
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) {
        if (mounted) setState(() => _uploading = false);
        return;
      }

      final bytes = await File(picked.path).readAsBytes();
      final url = await ref.read(storageRepositoryProvider).uploadBytes(
            path: 'users/$uid/properties/${widget.propertyId}/photos/'
                '${DateTime.now().millisecondsSinceEpoch}.jpg',
            bytes: bytes,
            contentType: 'image/jpeg',
          );

      final property = ref.read(propertyProvider(widget.propertyId));
      if (property == null) {
        if (mounted) setState(() => _uploading = false);
        return;
      }

      final ok = await ref
          .read(propertyControllerProvider.notifier)
          .saveProperty(property.copyWith(photos: [...property.photos, url]));
      if (!mounted) return;
      setState(() => _uploading = false);
      if (ok) {
        ref.invalidate(propertiesProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo added.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save the photo. Please try again.'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploading = false);
      final message = error is AppException
          ? error.message
          : 'Could not upload the photo. Please try again.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _removePhoto(int index) async {
    final property = ref.read(propertyProvider(widget.propertyId));
    if (property == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove photo?'),
        content: const Text(
          'This will remove the photo from the property. '
          'The file will no longer appear in the documents section.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _uploading = true);
    final storage = ref.read(storageRepositoryProvider);
    final photoUrl = property.photos[index];
    // Best-effort: remove the physical file from Cloudinary before the local
    // list is updated. Failures are silently ignored here because the asset
    // may already be gone from a previous run.
    try {
      await storage.deleteBytes(url: photoUrl);
    } catch (_) {
      // Ignore best-effort deletion failures.
    }
    final updatedPhotos = <String>[...property.photos]..removeAt(index);
    final ok = await ref
        .read(propertyControllerProvider.notifier)
        .saveProperty(property.copyWith(photos: updatedPhotos));
    if (!mounted) return;
    setState(() => _uploading = false);
    if (ok) {
      ref.invalidate(propertiesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo removed.')),
      );
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not remove photo.')));
    }
  }

  Future<void> _removeTenantDocument(Tenant tenant, TenantDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove "${doc.name}"?'),
        content: Text(
          'This will remove this document for ${tenant.name}. '
          'The tenant record itself will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    final storage = ref.read(storageRepositoryProvider);
    try {
      await storage.deleteBytes(url: doc.url);
    } catch (_) {
      // Ignore best-effort deletion failures.
    }

    setState(() => _uploading = true);
    final updatedDocs = tenant.documents
        .where((d) => d.id != doc.id && d.url != doc.url)
        .toList(growable: false);
    final clearId = tenant.idProofUrl == doc.url;
    final updated = tenant.copyWith(
      documents: updatedDocs,
      clearIdProof: clearId,
    );
    final ok =
        await ref.read(tenantControllerProvider.notifier).saveTenant(updated);
    if (!mounted) return;
    setState(() => _uploading = false);
    if (ok) {
      ref.invalidate(propertyTenantsProvider(widget.propertyId));
      ref.invalidate(allTenantsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document removed.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove document.')),
      );
    }
  }

  Future<void> _addTenantDocument() async {
    final tenants =
        ref.watch(propertyTenantsProvider(widget.propertyId)).valueOrNull ??
            const <Tenant>[];
    if (tenants.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tenants found for this property.')),
      );
      return;
    }

    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    Tenant? selectedTenant;
    if (tenants.length == 1) {
      selectedTenant = tenants.first;
    } else {
      selectedTenant = await showDialog<Tenant>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Select tenant for document'),
          children: tenants
              .map((t) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(dialogContext, t),
                    child: Text('${t.name} (${t.status.label})'),
                  ))
              .toList(growable: false),
        ),
      );
    }
    if (selectedTenant == null || !mounted) return;

    final docTitle = await _showDocumentTitleDialog(context, selectedTenant.name);
    if (docTitle == null || docTitle.trim().isEmpty || !mounted) return;

    final source = await pickImageSource(context);
    if (source == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final picked = await pickImageSafely(
        context,
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) {
        if (mounted) setState(() => _uploading = false);
        return;
      }

      final bytes = await File(picked.path).readAsBytes();
      final docId = DateTime.now().millisecondsSinceEpoch.toString();
      final url = await ref.read(storageRepositoryProvider).uploadBytes(
            path: 'users/$uid/properties/${widget.propertyId}/documents/'
                '${selectedTenant.tenantId}_$docId.jpg',
            bytes: bytes,
            contentType: 'image/jpeg',
          );

      final newDoc = TenantDocument(
        id: docId,
        name: docTitle.trim(),
        url: url,
        uploadedAt: DateTime.now(),
      );

      final isId = docTitle.toLowerCase().contains('id') ||
          docTitle.toLowerCase().contains('aadhaar');
      final updated = selectedTenant.copyWith(
        documents: [...selectedTenant.documents, newDoc],
        idProofUrl: (selectedTenant.idProofUrl == null || isId)
            ? url
            : selectedTenant.idProofUrl,
      );

      final ok =
          await ref.read(tenantControllerProvider.notifier).saveTenant(updated);
      if (!mounted) return;
      setState(() => _uploading = false);
      if (ok) {
        ref.invalidate(propertyTenantsProvider(widget.propertyId));
        ref.invalidate(allTenantsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document added.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save document.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not upload document: $error')),
      );
    }
  }

  Future<String?> _showDocumentTitleDialog(
    BuildContext context,
    String tenantName,
  ) async {
    const presets = [
      'Rental Agreement',
      'Aadhaar / ID Proof',
      'Police Verification',
      'PAN Card',
      'Electricity / Utility NOC',
    ];
    String selectedPreset = presets.first;
    final customCtrl = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Add document for $tenantName'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select document type:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ...presets.map((preset) {
                      final selected = selectedPreset == preset;
                      return ChoiceChip(
                        label: Text(preset),
                        selected: selected,
                        onSelected: (val) {
                          if (val) {
                            setDialogState(() {
                              selectedPreset = preset;
                            });
                          }
                        },
                      );
                    }),
                    ChoiceChip(
                      label: const Text('Other…'),
                      selected: selectedPreset == 'Other',
                      onSelected: (val) {
                        if (val) {
                          setDialogState(() {
                            selectedPreset = 'Other';
                          });
                        }
                      },
                    ),
                  ],
                ),
                if (selectedPreset == 'Other') ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: customCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Document title',
                      hintText: 'e.g. Cheque copy, NOC',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = selectedPreset == 'Other'
                    ? customCtrl.text.trim()
                    : selectedPreset;
                if (name.isEmpty) return;
                Navigator.pop(dialogCtx, name);
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thumbnail with a remove overlay button for property photos.
class _DocumentThumbWithRemove extends StatelessWidget {
  const _DocumentThumbWithRemove({
    required this.url,
    required this.title,
    required this.onRemove,
  });

  final String url;
  final String title;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        _DocumentThumb(
          url: url,
          title: title,
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
            ),
            child: IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white),
              onPressed: onRemove,
              tooltip: 'Remove photo',
            ),
          ),
        ),
      ],
    );
  }
}

/// Thumbnail for an uploaded file that opens the full-screen viewer on tap.
///
/// Uploads live in Cloudinary, so a refused or slow download is the usual
/// reason a picture "disappears" from the screen; the tile reports that
/// instead of silently drawing an unrelated icon.
class _DocumentThumb extends StatelessWidget {
  const _DocumentThumb({
    required this.url,
    required this.title,
    this.borderRadius = 12,
    this.width,
    this.height,
  });

  final String url;
  final String title;
  final double borderRadius;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: InkWell(
        onTap: () => _DocumentViewerPage.open(context, title: title, url: url),
        child: _DocumentImage(
          url: url,
          fit: BoxFit.cover,
          width: width,
          height: height,
        ),
      ),
    );
  }
}

/// Network image with a progress spinner and an explicit failure state.
class _DocumentImage extends StatelessWidget {
  const _DocumentImage({
    required this.url,
    required this.fit,
    this.width,
    this.height,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : _DocumentPlaceholder(
              width: width,
              height: height,
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: progress.expectedTotalBytes == null
                      ? null
                      : progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!,
                ),
              ),
            ),
      errorBuilder: (context, error, stackTrace) => _DocumentPlaceholder(
        width: width,
        height: height,
        child: const Icon(Icons.broken_image_outlined),
      ),
    );
  }
}

class _DocumentPlaceholder extends StatelessWidget {
  const _DocumentPlaceholder({required this.child, this.width, this.height});

  final Widget child;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: child,
      );
}

/// Full-screen viewer for an uploaded file, with a retry for failed downloads.
class _DocumentViewerPage extends StatefulWidget {
  const _DocumentViewerPage({required this.title, required this.url});

  final String title;
  final String url;

  static void open(
    BuildContext context, {
    required String title,
    required String url,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DocumentViewerPage(title: title, url: url),
      ),
    );
  }

  @override
  State<_DocumentViewerPage> createState() => _DocumentViewerPageState();
}

class _DocumentViewerPageState extends State<_DocumentViewerPage> {
  int _attempt = 0;

  Future<void> _retry() async {
    // Drop the failed entry so the cache replays a real request, not the error.
    await NetworkImage(widget.url).evict();
    if (mounted) setState(() => _attempt += 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.network(
            widget.url,
            key: ValueKey<int>(_attempt),
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const CircularProgressIndicator(),
            errorBuilder: (context, error, stackTrace) => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.broken_image_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'This file could not be loaded.',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.url,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  // The raw failure names the cause: an HTTP status means the
                  // asset was refused, a socket error means the device never
                  // reached Cloudinary.
                  Text(
                    '$error',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyDocNote extends StatelessWidget {
  const _EmptyDocNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- shared parts

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}

class _MeterReadingDialog extends StatefulWidget {
  const _MeterReadingDialog({required this.initialReading});

  final double initialReading;

  @override
  State<_MeterReadingDialog> createState() => _MeterReadingDialogState();
}

class _MeterReadingDialogState extends State<_MeterReadingDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: Formatters.units(widget.initialReading));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Update meter reading'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Current reading',
          suffixText: 'units',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final value = double.tryParse(_controller.text.trim());
            if (value != null) Navigator.of(context).pop(value);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DeletePropertyDialog extends StatefulWidget {
  const _DeletePropertyDialog({required this.propertyName});

  final String propertyName;

  @override
  State<_DeletePropertyDialog> createState() => _DeletePropertyDialogState();
}

class _DeletePropertyDialogState extends State<_DeletePropertyDialog> {
  final _controller = TextEditingController();
  bool _matches = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    final matches = _controller.text.trim() == widget.propertyName;
    if (matches != _matches) setState(() => _matches = matches);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Delete permanently?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently deletes the property and all of its tenants, '
            'transactions and documents. This cannot be undone.',
          ),
          const SizedBox(height: 16),
          Text(
            'Type "${widget.propertyName}" to confirm.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Property name'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
