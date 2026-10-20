import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/property.dart';
import '../../../providers/property_providers.dart';
import '../../../providers/tenant_providers.dart';

/// Searchable, filterable list of the landlord's rental units.
class PropertiesScreen extends ConsumerWidget {
  const PropertiesScreen({super.key});

  static const List<(String, PropertyStatus?)> _statusFilters =
      <(String, PropertyStatus?)>[
    ('All', null),
    ('Occupied', PropertyStatus.OCCUPIED),
    ('Vacant', PropertyStatus.VACANT),
    ('Maintenance', PropertyStatus.UNDER_MAINTENANCE),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final propertiesAsync = ref.watch(propertiesProvider);
    final filtered = ref.watch(filteredPropertiesProvider);
    final filter = ref.watch(propertyListFilterProvider);
    final archived =
        ref.watch(archivedPropertiesProvider).valueOrNull ?? const <Property>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Properties')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => context.push(AppRoutes.newProperty),
        icon: const Icon(Icons.add),
        label: const Text('Add property'),
      ),
      body: Column(
        children: <Widget>[
          _filterHeader(context, ref, filter),
          Expanded(
            child: _body(context, ref, propertiesAsync, filtered, filter, archived),
          ),
        ],
      ),
    );
  }

  Widget _filterHeader(
    BuildContext context,
    WidgetRef ref,
    PropertyListFilter filter,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search by name, address or tenant',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            textInputAction: TextInputAction.search,
            onChanged: (value) =>
                ref.read(propertyListFilterProvider.notifier).setQuery(value),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (final option in _statusFilters) ...<Widget>[
                  FilterChip(
                    label: Text(option.$1),
                    selected: filter.status == option.$2,
                    onSelected: (_) => ref
                        .read(propertyListFilterProvider.notifier)
                        .setStatus(option.$2),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Property>> propertiesAsync,
    List<Property> filtered,
    PropertyListFilter filter,
    List<Property> archived,
  ) {
    if (propertiesAsync.isLoading && !propertiesAsync.hasValue) {
      return const LoadingView();
    }
    if (propertiesAsync.hasError && !propertiesAsync.hasValue) {
      return ErrorView(
        message: 'We could not load your properties.',
        onRetry: () => ref.invalidate(propertiesProvider),
      );
    }

    final filterActive =
        filter.query.trim().isNotEmpty || filter.status != null;
    final children = <Widget>[
      if (filtered.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: EmptyState(
            icon: filterActive ? Icons.search_off : Icons.home_work_outlined,
            title: filterActive
                ? 'No properties match your filter'
                : 'No properties yet',
            message: filterActive
                ? 'Try a different search term or status.'
                : 'Add your first property to start tracking rent.',
            action: filterActive
                ? null
                : FilledButton.icon(
                    onPressed: () => context.push(AppRoutes.newProperty),
                    icon: const Icon(Icons.add),
                    label: const Text('Add property'),
                  ),
          ),
        )
      else
        for (final property in filtered) ...<Widget>[
          _PropertyCard(property: property),
          const SizedBox(height: 12),
        ],
      if (archived.isNotEmpty) ...<Widget>[
        const SizedBox(height: 4),
        SectionHeader(
          title: 'Archived',
          subtitle: '${archived.length} hidden',
        ),
        const SizedBox(height: 8),
        for (final property in archived) ...<Widget>[
          _ArchivedTile(property: property),
          const SizedBox(height: 8),
        ],
      ],
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: children,
    );
  }
}

class _PropertyCard extends ConsumerWidget {
  const _PropertyCard({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = property;
    final tenant = ref.watch(activeTenantForPropertyProvider(p.propertyId));
    final tenantName = tenant?.name ?? p.activeTenantName;
    final statusColor = switch (p.currentStatus) {
      PropertyStatus.OCCUPIED => context.ledgerColors.income,
      PropertyStatus.VACANT => theme.colorScheme.outline,
      PropertyStatus.UNDER_MAINTENANCE => context.ledgerColors.pending,
    };

    return Card(
      child: InkWell(
        onTap: () => context.push(AppRoutes.property(p.propertyId)),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                          p.propertyName,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${p.address}, ${p.city}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (p.isOccupied && tenantName != null) ...<Widget>[
                          const SizedBox(height: 6),
                          Text(
                            'Rented to $tenantName',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: context.ledgerColors.income,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      _statusChip(p.currentStatus.label, statusColor),
                      const SizedBox(height: 10),
                      Text(
                        'Potential / month',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      AmountText(
                        text: Formatters.currencyShort(p.monthlyPotentialRent),
                        size: 15,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _moneyCell(
                      context,
                      'Rent / month',
                      Formatters.currencyShort(p.baseRent),
                    ),
                  ),
                  Expanded(
                    child: _moneyCell(
                      context,
                      'Maintenance',
                      Formatters.currencyShort(p.baseMaintenance),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _moneyCell(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _ArchivedTile extends StatelessWidget {
  const _ArchivedTile({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = property;
    return Opacity(
      opacity: 0.6,
      child: Card(
        child: InkWell(
          onTap: () => context.push(AppRoutes.property(p.propertyId)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.archive_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        p.propertyName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${p.address}, ${p.city}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
