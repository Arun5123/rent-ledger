import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/communication_utils.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/ledger_transaction.dart';
import '../../../domain/models/property.dart';
import '../../../domain/models/report.dart';
import '../../../domain/models/tenant.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/auth_providers.dart';
import '../../../providers/property_providers.dart';
import '../../../providers/tenant_providers.dart';
import '../../../providers/transaction_providers.dart';
import '../transactions/transaction_entry_sheet.dart';

/// Home screen: KPIs, occupancy, income trend, dues, activity and shortcuts.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(dashboardMetricsProvider);
    final loading = ref.watch(dashboardLoadingProvider);
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final properties =
        ref.watch(propertiesProvider).valueOrNull ?? const <Property>[];
    final tenants =
        ref.watch(allTenantsProvider).valueOrNull ?? const <Tenant>[];
    final transactions =
        ref.watch(allTransactionsProvider).valueOrNull ??
            const <LedgerTransaction>[];
    final offline = ref.watch(isOnlineProvider).valueOrNull == false;

    final name = profile?.name.trim() ?? '';
    final greeting = 'Hello, ${name.isEmpty ? 'Landlord' : name}';

    return Scaffold(
      appBar: AppBar(title: Text(greeting)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => _onAddEntry(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add entry'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _onRefresh(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: <Widget>[
            OfflineBanner(visible: offline),
            if (loading && properties.isEmpty)
              const SizedBox(height: 240, child: LoadingView())
            else
              ..._content(context, metrics, properties, transactions, tenants),
          ],
        ),
      ),
    );
  }

  Future<void> _onAddEntry(BuildContext context, WidgetRef ref) async {
    final properties =
        ref.read(propertiesProvider).valueOrNull ?? const <Property>[];
    if (properties.isEmpty) {
      context.push(AppRoutes.newProperty);
      return;
    }
    await showTransactionEntrySheet(
      context,
      propertyId: properties.first.propertyId,
    );
  }

  Future<void> _onRefresh(WidgetRef ref) async {
    ref.invalidate(propertiesProvider);
    ref.invalidate(allTenantsProvider);
    ref.invalidate(allTransactionsProvider);
    ref.invalidate(recentLedgersProvider);
    try {
      await ref.read(propertiesProvider.future);
    } catch (_) {
      // Failures are already surfaced through the providers themselves.
    }
  }

  List<Widget> _content(
    BuildContext context,
    DashboardMetrics metrics,
    List<Property> properties,
    List<LedgerTransaction> transactions,
    List<Tenant> tenants,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiringTenants = tenants.where((t) {
      if (t.status != TenantStatus.ACTIVE || t.leaseEndDate == null) return false;
      final days = t.leaseEndDate!.difference(today).inDays;
      return days <= 60;
    }).toList(growable: false)
      ..sort((a, b) => a.leaseEndDate!.compareTo(b.leaseEndDate!));

    return <Widget>[
      _kpiGrid(context, metrics),
      const SizedBox(height: 12),
      if (metrics.lastMonthIncome > 0 || metrics.incomeThisMonth > 0) ...[
        _deltaCaption(context, metrics),
        const SizedBox(height: 12),
      ],
      _occupancyCard(context, metrics),
      const SizedBox(height: 16),
      if (expiringTenants.isNotEmpty) ...[
        ..._leaseExpirySection(context, expiringTenants, properties),
        const SizedBox(height: 16),
      ],
      _trendCard(context, metrics),
      const SizedBox(height: 16),
      ..._pendingDuesSection(context, metrics),
      const SizedBox(height: 16),
      ..._recentActivitySection(context, properties, transactions),
      const SizedBox(height: 16),
      _quickActions(context),
    ];
  }

  Widget _kpiGrid(BuildContext context, DashboardMetrics m) {
    final colors = context.ledgerColors;
    return Column(
      children: <Widget>[
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: KpiCard(
                  label: 'Net this month',
                  value: Formatters.currency(m.netThisMonth, compact: true),
                  icon: Icons.account_balance_wallet_outlined,
                  tint: colors.income,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: KpiCard(
                  label: 'Collected this month',
                  value: Formatters.currency(m.incomeThisMonth, compact: true),
                  icon: Icons.savings_outlined,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: KpiCard(
                  label: 'Pending dues',
                  value: Formatters.currencyShort(m.pendingDues),
                  icon: Icons.schedule_outlined,
                  tint: colors.pending,
                  caption: '${m.pendingTenantCount} tenants',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: KpiCard(
                  label: 'Occupancy',
                  value: Formatters.percent(m.occupancyRate),
                  icon: Icons.home_work_outlined,
                  caption: '${m.occupiedCount}/${m.totalProperties} units',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _deltaCaption(BuildContext context, DashboardMetrics m) {
    final delta = m.incomeDeltaPercent;
    final positive = delta >= 0;
    final color =
        positive ? context.ledgerColors.income : context.ledgerColors.expense;
    return Row(
      children: <Widget>[
        Icon(
          positive ? Icons.arrow_upward : Icons.arrow_downward,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          '${positive ? '+' : ''}${delta.toStringAsFixed(1)}% vs last month',
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _occupancyCard(BuildContext context, DashboardMetrics m) {
    final theme = Theme.of(context);
    final colors = context.ledgerColors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              title: 'Occupancy',
              subtitle: '${m.occupiedCount} of ${m.totalProperties} units rented',
            ),
            const SizedBox(height: 14),
            RatioBar(ratio: m.occupancyRate / 100, height: 10),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                Formatters.percent(m.occupancyRate),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                _statChip(context, 'Occupied', m.occupiedCount, colors.income),
                const SizedBox(width: 8),
                _statChip(
                  context,
                  'Vacant',
                  m.vacantCount,
                  theme.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                _statChip(
                  context,
                  'Maintenance',
                  m.maintenanceCount,
                  colors.pending,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(
    BuildContext context,
    String label,
    int count,
    Color color,
  ) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: <Widget>[
            Text(
              '$count',
              style: theme.textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trendCard(BuildContext context, DashboardMetrics m) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              title: 'Income trend',
              subtitle: m.trend.length < 2
                  ? null
                  : 'Last ${m.trend.length} months',
            ),
            const SizedBox(height: 16),
            if (m.trend.length < 2)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'Add a few months of entries to see your income trend.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                height: 200,
                child: LineChart(_trendData(context, m.trend)),
              ),
          ],
        ),
      ),
    );
  }

  LineChartData _trendData(BuildContext context, List<TrendPoint> trend) {
    final incomeColor = Theme.of(context).colorScheme.primary;
    final expenseColor = context.ledgerColors.expense;

    final incomeSpots = <FlSpot>[];
    final expenseSpots = <FlSpot>[];
    var maxValue = 0.0;
    for (var i = 0; i < trend.length; i++) {
      final point = trend[i];
      incomeSpots.add(FlSpot(i.toDouble(), point.income));
      expenseSpots.add(FlSpot(i.toDouble(), point.expenses));
      if (point.income > maxValue) maxValue = point.income;
      if (point.expenses > maxValue) maxValue = point.expenses;
    }
    final maxY = maxValue <= 0 ? 1.0 : maxValue * 1.2;
    final labelStep = (trend.length / 4).ceil().clamp(1, trend.length).toInt();

    return LineChartData(
      minX: 0,
      maxX: (trend.length - 1).toDouble(),
      minY: 0,
      maxY: maxY,
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final index = value.round();
              if (index < 0 || index >= trend.length) {
                return const SizedBox.shrink();
              }
              if (index % labelStep != 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  Formatters.monthLabel(trend[index].period).split(' ').first,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      lineBarsData: <LineChartBarData>[
        LineChartBarData(
          spots: incomeSpots,
          isCurved: true,
          color: incomeColor,
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
        ),
        LineChartBarData(
          spots: expenseSpots,
          isCurved: true,
          color: expenseColor,
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
        ),
      ],
    );
  }

  List<Widget> _leaseExpirySection(
    BuildContext context,
    List<Tenant> expiringTenants,
    List<Property> properties,
  ) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    return <Widget>[
      SectionHeader(
        title: 'Lease expiry alerts',
        subtitle:
            '${expiringTenants.length} lease${expiringTenants.length == 1 ? '' : 's'} expiring soon or overdue',
      ),
      const SizedBox(height: 8),
      Card(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: theme.colorScheme.error.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          children: <Widget>[
            for (var i = 0; i < expiringTenants.length; i++) ...<Widget>[
              if (i > 0) const Divider(height: 1),
              _leaseExpiryTile(context, expiringTenants[i], properties, today),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _leaseExpiryTile(
    BuildContext context,
    Tenant tenant,
    List<Property> properties,
    DateTime today,
  ) {
    final theme = Theme.of(context);
    final days = tenant.leaseEndDate!.difference(
      DateTime(today.year, today.month, today.day),
    ).inDays;

    final String badgeText;
    final Color badgeColor;
    if (days < 0) {
      badgeText = 'Expired ${days.abs()}d ago';
      badgeColor = theme.colorScheme.error;
    } else if (days == 0) {
      badgeText = 'Expires today';
      badgeColor = Colors.orange;
    } else {
      badgeText = 'Expires in $days d';
      badgeColor = days <= 30 ? Colors.orange : theme.colorScheme.primary;
    }

    final propName = _propertyName(properties, tenant.propertyId);

    return InkWell(
      onTap: () => context.push(AppRoutes.property(tenant.propertyId)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        tenant.name,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$propName • Lease ends ${Formatters.date(tenant.leaseEndDate!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (tenant.phone.isNotEmpty) ...[
              IconButton(
                icon: const Icon(Icons.call, size: 18),
                tooltip: 'Call tenant',
                visualDensity: VisualDensity.compact,
                onPressed: () => CommunicationUtils.makePhoneCall(
                  context: context,
                  phone: tenant.phone,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chat, size: 18),
                tooltip: 'WhatsApp renewal reminder',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final msg =
                      'Hi ${tenant.name},\nThis is a reminder regarding your rental agreement for $propName. '
                      'Your lease is scheduled to end on ${Formatters.date(tenant.leaseEndDate!)}. '
                      'Please let us know if you wish to renew.';
                  CommunicationUtils.openWhatsApp(
                    context: context,
                    phone: tenant.phone,
                    message: msg,
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _pendingDuesSection(BuildContext context, DashboardMetrics m) {
    final theme = Theme.of(context);
    final dues = m.duesByTenant.take(5).toList(growable: false);
    return <Widget>[
      SectionHeader(
        title: 'Pending dues',
        subtitle: m.pendingTenantCount == 0
            ? null
            : '${m.pendingTenantCount} tenants yet to pay',
      ),
      const SizedBox(height: 8),
      Card(
        child: dues.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No pending dues — every tenant is up to date.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : Column(
                children: <Widget>[
                  for (var i = 0; i < dues.length; i++) ...<Widget>[
                    if (i > 0) const Divider(height: 1),
                    _dueTile(context, dues[i]),
                  ],
                ],
              ),
      ),
    ];
  }

  Widget _dueTile(BuildContext context, TenantDue due) {
    final theme = Theme.of(context);
    final pending = context.ledgerColors.pending;
    return InkWell(
      onTap: () => context.push(AppRoutes.property(due.propertyId)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        due.tenantName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        due.propertyName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AmountText(
                  text: Formatters.currencyShort(due.dueAmount),
                  color: pending,
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 10),
            RatioBar(ratio: due.progress, color: pending, height: 6),
            if (due.phone != null && due.phone!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 0),
                      textStyle: theme.textTheme.labelSmall,
                    ),
                    icon: const Icon(Icons.call, size: 14),
                    label: const Text('Call'),
                    onPressed: () => CommunicationUtils.makePhoneCall(
                      context: context,
                      phone: due.phone!,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 0),
                      textStyle: theme.textTheme.labelSmall,
                    ),
                    icon: const Icon(Icons.chat, size: 14),
                    label: const Text('WhatsApp Remind'),
                    onPressed: () {
                      final msg = CommunicationUtils.buildRentReminder(
                        tenantName: due.tenantName,
                        propertyName: due.propertyName,
                        amountDue: due.dueAmount,
                      );
                      CommunicationUtils.openWhatsApp(
                        context: context,
                        phone: due.phone!,
                        message: msg,
                      );
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _recentActivitySection(
    BuildContext context,
    List<Property> properties,
    List<LedgerTransaction> transactions,
  ) {
    final theme = Theme.of(context);
    final recent = <LedgerTransaction>[...transactions]
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    final items = recent.take(8).toList(growable: false);
    return <Widget>[
      const SectionHeader(title: 'Recent activity'),
      const SizedBox(height: 8),
      Card(
        child: items.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No entries yet. Tap Add entry to record your first payment.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : Column(
                children: <Widget>[
                  for (var i = 0; i < items.length; i++) ...<Widget>[
                    if (i > 0) const Divider(height: 1),
                    _activityTile(context, items[i], properties),
                  ],
                ],
              ),
      ),
    ];
  }

  Widget _activityTile(
    BuildContext context,
    LedgerTransaction txn,
    List<Property> properties,
  ) {
    final color =
        txn.isIncome ? context.ledgerColors.income : context.ledgerColors.expense;
    final propName = _propertyName(properties, txn.propertyId);

    return ListTile(
      onTap: () => context.push(AppRoutes.property(txn.propertyId)),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(
          txn.isIncome ? Icons.south_west : Icons.north_east,
          size: 18,
          color: color,
        ),
      ),
      title: Row(
        children: [
          Expanded(child: Text(txn.type.label)),
          if (txn.expenseCategory != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                txn.expenseCategory!.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '$propName · ${Formatters.date(txn.recordedAt)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AmountText(
            text: '${txn.isIncome ? '+' : '-'}'
                '${Formatters.currencyShort(txn.amount)}',
            color: color,
            size: 15,
          ),
          if (txn.isIncome) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.share_outlined, size: 18),
              tooltip: 'Share receipt',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                final text = CommunicationUtils.buildReceiptMessage(
                  tenantName: txn.tenantName ?? 'Tenant',
                  propertyName: propName,
                  amount: txn.amount,
                  typeLabel: txn.type.label,
                  date: txn.recordedAt,
                  paymentMethodLabel: txn.paymentMethod.label,
                );
                CommunicationUtils.shareText(
                  text: text,
                  subject: 'Payment receipt - $propName',
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  String _propertyName(List<Property> properties, String propertyId) {
    for (final property in properties) {
      if (property.propertyId == propertyId) return property.propertyName;
    }
    return 'Property';
  }

  Widget _quickActions(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: () => context.push(AppRoutes.newProperty),
            icon: const Icon(Icons.add_home_outlined, size: 18),
            label: const Text('Add property', style: TextStyle(fontSize: 13)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: () => context.go(AppRoutes.reports),
            icon: const Icon(Icons.bar_chart_outlined, size: 18),
            label: const Text('Reports', style: TextStyle(fontSize: 13)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: () => context.push(AppRoutes.history),
            icon: const Icon(Icons.history, size: 18),
            label: const Text('Past tenants', style: TextStyle(fontSize: 13)),
          ),
        ),
      ],
    );
  }
}
