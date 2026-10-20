import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/enums.dart';
import '../domain/models/property.dart';
import 'app_providers.dart';
import 'auth_providers.dart';

/// Every non-archived property owned by the signed-in user.
final propertiesProvider = StreamProvider<List<Property>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream<List<Property>>.value(const <Property>[]);
  return ref.watch(propertyRepositoryProvider).watchProperties(uid);
});

/// Archived (soft-deleted) properties, used by the "Archived" filter.
final archivedPropertiesProvider = StreamProvider<List<Property>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream<List<Property>>.value(const <Property>[]);
  return ref
      .watch(propertyRepositoryProvider)
      .watchProperties(uid, includeArchived: true)
      .map((all) => all.where((p) => p.isArchived).toList(growable: false));
});

/// Derived single property — avoids one Firestore listener per detail screen.
final propertyProvider = Provider.family<Property?, String>((ref, propertyId) {
  final properties = ref.watch(propertiesProvider).valueOrNull;
  if (properties != null) {
    for (final property in properties) {
      if (property.propertyId == propertyId) return property;
    }
  }
  final archived = ref.watch(archivedPropertiesProvider).valueOrNull;
  if (archived != null) {
    for (final property in archived) {
      if (property.propertyId == propertyId) return property;
    }
  }
  return null;
});

final vacantPropertiesProvider = Provider<List<Property>>(
  (ref) =>
      (ref.watch(propertiesProvider).valueOrNull ?? const <Property>[])
          .where((p) => p.isVacant)
          .toList(growable: false),
);

final occupiedPropertiesProvider = Provider<List<Property>>(
  (ref) =>
      (ref.watch(propertiesProvider).valueOrNull ?? const <Property>[])
          .where((p) => p.isOccupied)
          .toList(growable: false),
);

/// Search + status filter applied by the properties list screen.
class PropertyListFilter {
  const PropertyListFilter({this.query = '', this.status});

  final String query;
  final PropertyStatus? status;

  PropertyListFilter copyWith({String? query, PropertyStatus? status}) =>
      PropertyListFilter(
        query: query ?? this.query,
        status: status,
      );
}

final propertyListFilterProvider =
    NotifierProvider<PropertyListFilterNotifier, PropertyListFilter>(
  PropertyListFilterNotifier.new,
);

class PropertyListFilterNotifier extends Notifier<PropertyListFilter> {
  @override
  PropertyListFilter build() => const PropertyListFilter();

  void setQuery(String query) => state = state.copyWith(query: query);

  void setStatus(PropertyStatus? status) =>
      state = PropertyListFilter(query: state.query, status: status);
}

final filteredPropertiesProvider = Provider<List<Property>>((ref) {
  final filter = ref.watch(propertyListFilterProvider);
  final properties =
      ref.watch(propertiesProvider).valueOrNull ?? const <Property>[];
  final needle = filter.query.trim().toLowerCase();
  return properties.where((property) {
    if (filter.status != null && property.currentStatus != filter.status) {
      return false;
    }
    if (needle.isEmpty) return true;
    return property.propertyName.toLowerCase().contains(needle) ||
        property.address.toLowerCase().contains(needle) ||
        property.city.toLowerCase().contains(needle) ||
        (property.activeTenantName ?? '').toLowerCase().contains(needle);
  }).toList(growable: false);
});

/// Writes for properties: create, update, archive and cascade delete.
class PropertyController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<String?> create(Property property) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return null;
    state = const AsyncLoading();
    try {
      final id = await ref
          .read(propertyRepositoryProvider)
          .createProperty(uid, property);
      state = const AsyncData<void>(null);
      return id;
    } catch (error, stackTrace) {
      state = AsyncError<void>(error, stackTrace);
      return null;
    }
  }

  Future<bool> saveProperty(Property property) => _run(
        () => ref.read(propertyRepositoryProvider).updateProperty(
              ref.read(currentUidProvider)!,
              property,
            ),
      );

  Future<bool> setArchived(String propertyId, bool archived) => _run(
        () => ref.read(propertyRepositoryProvider).setArchived(
              ref.read(currentUidProvider)!,
              propertyId,
              archived,
            ),
      );

  /// Cascading hard delete — properties, tenants, transactions and Storage.
  Future<bool> deleteCascade(String propertyId) => _run(
        () => ref.read(propertyRepositoryProvider).deletePropertyCascade(
              ref.read(currentUidProvider)!,
              propertyId,
            ),
      );

  /// Mirrors an EB bill reading onto the property baseline.
  Future<bool> updateMeterReading(String propertyId, double reading) async {
    final uid = ref.read(currentUidProvider);
    final property = ref.read(propertyProvider(propertyId));
    if (uid == null || property == null) return false;
    return _run(
      () => ref.read(propertyRepositoryProvider).updateProperty(
            uid,
            property.copyWith(currentEbMeterReading: reading),
          ),
    );
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (ref.read(currentUidProvider) == null) return false;
    state = const AsyncLoading();
    try {
      await action();
      state = const AsyncData<void>(null);
      return true;
    } catch (error, stackTrace) {
      state = AsyncError<void>(error, stackTrace);
      return false;
    }
  }
}

final propertyControllerProvider =
    AsyncNotifierProvider<PropertyController, void>(PropertyController.new);
