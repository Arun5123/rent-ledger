import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../data/services/pdf_document_theme.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/property.dart';
import '../../../domain/models/report.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/property_providers.dart';
import '../../../providers/transaction_providers.dart';

/// Reports & exports: filter the ledger, review the roll-up, rebuild a month
/// and export a PDF / Excel / CSV statement.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late final TextEditingController _searchController;
  ExportFormat? _exporting;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(ledgerFilterProvider).search,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _currentFyStart() {
    final now = DateTime.now();
    return now.month >= 4 ? now.year : now.year - 1;
  }

  LedgerFilter _lastMonthFilter() {
    final now = DateTime.now();
    return LedgerFilter(
      from: DateTime(now.year, now.month - 1),
      to: DateTime(now.year, now.month, 0, 23, 59, 59),
    );
  }

  bool _sameRange(LedgerFilter a, LedgerFilter b) =>
      a.from == b.from && a.to == b.to;

  bool _isCustom(LedgerFilter filter) =>
      !_sameRange(filter, LedgerFilter.thisMonth()) &&
      !_sameRange(filter, _lastMonthFilter()) &&
      !_sameRange(filter, LedgerFilter.financialYear(_currentFyStart()));

  void _applyRange(LedgerFilter range) {
    ref.read(ledgerFilterProvider.notifier).setRange(range.from, range.to);
  }

  Future<void> _pickCustomRange() async {
    final current = ref.read(ledgerFilterProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
      initialDateRange: DateTimeRange(start: current.from, end: current.to),
      helpText: 'Select report range',
    );
    if (picked == null || !mounted) return;
    ref
        .read(ledgerFilterProvider.notifier)
        .setRange(
          picked.start,
          DateTime(
            picked.end.year,
            picked.end.month,
            picked.end.day,
            23,
            59,
            59,
          ),
        );
  }

  Future<void> _rebuild(String period) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(ledgerControllerProvider.notifier)
        .rebuild(period);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Recomputing ${Formatters.monthLabel(period)} on the server…'
              : 'Could not rebuild ${Formatters.monthLabel(period)}. Try again.',
        ),
      ),
    );
  }

  Future<void> _export(ExportFormat format) async {
    if (_exporting != null) return;
    setState(() => _exporting = format);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bundle = ref.read(reportBundleProvider);
      final bytes = await ref
          .read(reportExporterProvider(format))
          .build(
            bundle,
            propertyName: bundle.filter.propertyId == null
                ? null
                : bundle.propertyNameFor(bundle.filter.propertyId!),
          );
      final saver = ref.read(exportFileSaverProvider);
      final path = await saver.save(
        fileName: PdfBlocks.fileNameFor(bundle, format.extension),
        bytes: bytes,
      );
      await saver.share(
        filePath: path,
        subject: '${format.label} report',
        text: PdfBlocks.describeFilter(bundle, 'All properties'),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error is AppException
                ? error.message
                : 'Could not export the report. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.ledgerColors;
    final filter = ref.watch(ledgerFilterProvider);
    final bundle = ref.watch(reportBundleProvider);
    final properties =
        ref.watch(propertiesProvider).valueOrNull ?? const <Property>[];
    final ledgersAsync = ref.watch(recentLedgersProvider);

    final byProperty = <String, _PropertyTotals>{};
    for (final txn in bundle.transactions) {
      final totals = byProperty.putIfAbsent(
        txn.propertyId,
        () => _PropertyTotals(),
      );
      if (txn.isIncome) {
        totals.income += txn.amount;
      } else {
        totals.expense += txn.amount;
      }
    }
    final propertyRows = byProperty.entries.toList(growable: false)
      ..sort((a, b) => b.value.net.compareTo(a.value.net));

    final visibleTransactions = bundle.transactions
        .take(50)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Reports & exports')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          _buildFilterCard(theme, filter, properties),
          const SizedBox(height: 20),
          SectionHeader(
            title: 'Summary',
            subtitle: '${bundle.transactions.length} entries in range',
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: KpiCard(
                  label: 'Total income',
                  value: Formatters.currencyShort(bundle.totalIncome),
                  icon: Icons.trending_up,
                  tint: colors.income,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: KpiCard(
                  label: 'Total expenses',
                  value: Formatters.currencyShort(bundle.totalExpenses),
                  icon: Icons.trending_down,
                  tint: colors.expense,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  DetailRow(
                    label: 'Net income',
                    value: Formatters.currency(bundle.netIncome),
                    valueColor: bundle.netIncome >= 0
                        ? colors.income
                        : colors.expense,
                    emphasize: true,
                  ),
                  const Divider(height: 20),
                  DetailRow(
                    label: 'Rent collected',
                    value: Formatters.currency(bundle.totalRent),
                  ),
                  DetailRow(
                    label: 'Maintenance',
                    value: Formatters.currency(bundle.totalMaintenance),
                  ),
                  DetailRow(
                    label: 'Electricity',
                    value:
                        '${Formatters.currency(bundle.totalEb)} • '
                        '${Formatters.units(bundle.totalUnitsBilled)} units',
                  ),
                  DetailRow(
                    label: 'Water',
                    value: Formatters.currency(bundle.totalWater),
                  ),
                  DetailRow(
                    label: 'Advance received',
                    value: Formatters.currency(bundle.totalAdvanceReceived),
                  ),
                  DetailRow(
                    label: 'Advance refunded',
                    value: Formatters.currency(bundle.totalAdvanceRefund),
                  ),
                  DetailRow(
                    label: 'Property expenses',
                    value: Formatters.currency(bundle.totalPropertyExpense),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'By property'),
          const SizedBox(height: 12),
          if (propertyRows.isEmpty)
            Text(
              'No transactions match the current filters.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...propertyRows.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          bundle.propertyNameFor(entry.key),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DetailRow(
                          label: 'Income',
                          value: Formatters.currency(entry.value.income),
                          valueColor: colors.income,
                        ),
                        DetailRow(
                          label: 'Expense',
                          value: Formatters.currency(entry.value.expense),
                          valueColor: colors.expense,
                        ),
                        DetailRow(
                          label: 'Net',
                          value: Formatters.currency(entry.value.net),
                          emphasize: true,
                        ),
                        const SizedBox(height: 8),
                        RatioBar(
                          ratio: bundle.totalIncome <= 0
                              ? 0
                              : entry.value.income / bundle.totalIncome,
                          color: colors.income,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Share of income: '
                          '${Formatters.percent(bundle.totalIncome <= 0 ? 0 : (entry.value.income / bundle.totalIncome) * 100)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          const SectionHeader(title: 'Monthly ledgers'),
          const SizedBox(height: 4),
          Text(
            'Monthly ledgers are recomputed on the server. Tap rebuild to '
            'refresh a month after editing its entries.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          ledgersAsync.when(
            data: (ledgers) {
              final recent = ledgers.take(6).toList(growable: false);
              if (recent.isEmpty) {
                return Text(
                  'No monthly ledgers yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }
              return Column(
                children: recent
                    .map(
                      (ledger) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            isThreeLine: true,
                            title: Text(Formatters.monthLabel(ledger.period)),
                            subtitle: Text(
                              'Income ${Formatters.currencyShort(ledger.totalIncome)} • Expenses ${Formatters.currencyShort(ledger.totalExpensesIncurred)}\nNet ${Formatters.currencyShort(ledger.netOperatingIncome)} • Pending ${Formatters.currencyShort(ledger.pendingDues)}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.refresh),
                              tooltip: 'Rebuild',
                              onPressed: () => _rebuild(ledger.period),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) => Text(
              'Could not load monthly ledgers.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.expense,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Transactions'),
          const SizedBox(height: 12),
          if (bundle.isEmpty)
            const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No transactions',
              message:
                  'Adjust the filters above or add an entry to see it here.',
            )
          else
            ...visibleTransactions.map(
              (txn) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          (txn.isIncome ? colors.income : colors.expense)
                              .withValues(alpha: 0.12),
                      child: Icon(
                        txn.isIncome
                            ? Icons.arrow_downward
                            : Icons.arrow_upward,
                        size: 18,
                        color: txn.isIncome ? colors.income : colors.expense,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(child: Text(txn.type.label)),
                        if (txn.expenseCategory != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              txn.expenseCategory!.label,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(fontSize: 10),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      '${bundle.propertyNameFor(txn.propertyId)} • '
                      '${txn.tenantName ?? 'Owner'}\n'
                      '${Formatters.date(txn.recordedAt)}',
                    ),
                    isThreeLine: true,
                    trailing: AmountText(
                      text:
                          '${txn.isExpense ? '-' : '+'}'
                          '${Formatters.currency(txn.amount)}',
                      size: 15,
                      color: txn.isIncome ? colors.income : colors.expense,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SectionHeader(
                    title: 'Export',
                    subtitle: 'Download or share the current report',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      _exportButton(ExportFormat.PDF, !bundle.isEmpty),
                      const SizedBox(width: 8),
                      _exportButton(ExportFormat.EXCEL, !bundle.isEmpty),
                      const SizedBox(width: 8),
                      _exportButton(ExportFormat.CSV, !bundle.isEmpty),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterCard(
    ThemeData theme,
    LedgerFilter filter,
    List<Property> properties,
  ) {
    final notifier = ref.read(ledgerFilterProvider.notifier);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              title: 'Filters',
              subtitle:
                  '${Formatters.date(filter.from)} – ${Formatters.date(filter.to)}',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('This month'),
                  selected: _sameRange(filter, LedgerFilter.thisMonth()),
                  onSelected: (_) => _applyRange(LedgerFilter.thisMonth()),
                ),
                ChoiceChip(
                  label: const Text('Last month'),
                  selected: _sameRange(filter, _lastMonthFilter()),
                  onSelected: (_) => _applyRange(_lastMonthFilter()),
                ),
                ChoiceChip(
                  label: const Text('This FY'),
                  selected: _sameRange(
                    filter,
                    LedgerFilter.financialYear(_currentFyStart()),
                  ),
                  onSelected: (_) => _applyRange(
                    LedgerFilter.financialYear(_currentFyStart()),
                  ),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.date_range_outlined, size: 16),
                  label: const Text('Custom'),
                  selected: _isCustom(filter),
                  onSelected: (_) => _pickCustomRange(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              isExpanded: true,
              initialValue: filter.propertyId,
              decoration: const InputDecoration(labelText: 'Property'),
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All properties'),
                ),
                ...properties.map(
                  (property) => DropdownMenuItem<String?>(
                    value: property.propertyId,
                    child: Text(
                      property.propertyName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: notifier.setProperty,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('All'),
                  selected: filter.category == null,
                  onSelected: (_) => notifier.setCategory(null),
                ),
                ChoiceChip(
                  label: const Text('Income'),
                  selected: filter.category == TransactionCategory.INCOME,
                  onSelected: (_) =>
                      notifier.setCategory(TransactionCategory.INCOME),
                ),
                ChoiceChip(
                  label: const Text('Expense'),
                  selected: filter.category == TransactionCategory.EXPENSE,
                  onSelected: (_) =>
                      notifier.setCategory(TransactionCategory.EXPENSE),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Types',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: TransactionType.values
                  .map(
                    (type) => FilterChip(
                      label: Text(type.label),
                      selected: filter.types.contains(type),
                      onSelected: (selected) {
                        final next = Set<TransactionType>.from(filter.types);
                        if (selected) {
                          next.add(type);
                        } else {
                          next.remove(type);
                        }
                        notifier.setTypes(next);
                      },
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search',
                prefixIcon: Icon(Icons.search),
                hintText: 'Tenant, notes or type',
              ),
              onChanged: notifier.setSearch,
            ),
          ],
        ),
      ),
    );
  }

  Widget _exportButton(ExportFormat format, bool enabled) {
    final busy = _exporting == format;
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: (!enabled || _exporting != null)
            ? null
            : () => _export(format),
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(_iconFor(format), size: 18),
        label: Text(format.label),
      ),
    );
  }

  IconData _iconFor(ExportFormat format) => switch (format) {
    ExportFormat.PDF => Icons.picture_as_pdf_outlined,
    ExportFormat.EXCEL => Icons.grid_on_outlined,
    ExportFormat.CSV => Icons.description_outlined,
  };
}

/// Mutable accumulator used while grouping transactions per property.
class _PropertyTotals {
  double income = 0;
  double expense = 0;

  double get net => income - expense;
}
