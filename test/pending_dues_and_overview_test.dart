import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentledger/core/theme/app_theme.dart';
import 'package:rentledger/domain/models/enums.dart';
import 'package:rentledger/domain/models/property.dart';
import 'package:rentledger/domain/models/tenant.dart';
import 'package:rentledger/presentation/screens/dashboard/dashboard_screen.dart';
import 'package:rentledger/presentation/screens/properties/property_detail_screen.dart';
import 'package:rentledger/providers/app_providers.dart';
import 'package:rentledger/providers/auth_providers.dart';
import 'package:rentledger/providers/property_providers.dart';
import 'package:rentledger/providers/tenant_providers.dart';
import 'package:rentledger/providers/transaction_providers.dart';

void main() {
  final now = DateTime(2026, 10, 20);

  final propertySm2 = Property(
    propertyId: 'p_sm2',
    propertyName: 'SM2',
    address: '123 Main St',
    city: 'Chennai',
    currentStatus: PropertyStatus.OCCUPIED,
    activeTenantId: 't_sm2',
    activeTenantName: 'Tenant SM2',
    baseRent: 15000,
    baseMaintenance: 1000,
    createdAt: now,
    updatedAt: now,
  );

  final tenantSm2 = Tenant(
    tenantId: 't_sm2',
    propertyId: 'p_sm2',
    ownerId: 'u1',
    name: 'Tenant SM2',
    phone: '9876543210',
    advanceDepositAmount: 15000,
    leaseStartDate: DateTime(2026, 10, 20),
    status: TenantStatus.ACTIVE,
    createdAt: now,
    updatedAt: now,
  );

  final properties = [propertySm2];
  final tenants = [tenantSm2];

  testWidgets('Test PropertyDetailScreen renders overview for SM2', (tester) async {
    final container = ProviderContainer(
      overrides: [
        currentUidProvider.overrideWithValue('u1'),
        propertiesProvider.overrideWith((ref) => Stream.value(properties)),
        allTenantsProvider.overrideWith((ref) => Stream.value(tenants)),
        propertyTenantsProvider('p_sm2').overrideWith((ref) => Stream.value(tenants)),
        propertyTransactionsProvider('p_sm2').overrideWith((ref) => Stream.value([])),
        allTransactionsProvider.overrideWith((ref) => Stream.value([])),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        recentLedgersProvider.overrideWith((ref) => Stream.value([])),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const PropertyDetailScreen(propertyId: 'p_sm2'),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    // Check if texts are on screen
    expect(find.text('SM2'), findsWidgets);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Tenant SM2'), findsWidgets);
    expect(find.text('Rent & maintenance'), findsOneWidget);
  });

  testWidgets('Test DashboardScreen renders pending dues cards with 6 tenants', (tester) async {
    final propertiesList = List.generate(
      6,
      (i) => Property(
        propertyId: 'p$i',
        propertyName: 'SM$i',
        address: 'Street $i',
        city: 'City $i',
        currentStatus: PropertyStatus.OCCUPIED,
        activeTenantId: 't$i',
        activeTenantName: 'Tenant $i',
        baseRent: 15000,
        baseMaintenance: 1000,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final tenantsList = List.generate(
      6,
      (i) => Tenant(
        tenantId: 't$i',
        propertyId: 'p$i',
        ownerId: 'u1',
        name: 'Tenant $i',
        phone: '987654321$i',
        advanceDepositAmount: 15000,
        leaseStartDate: DateTime(2026, 10, 1),
        status: TenantStatus.ACTIVE,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final container = ProviderContainer(
      overrides: [
        currentUidProvider.overrideWithValue('u1'),
        propertiesProvider.overrideWith((ref) => Stream.value(propertiesList)),
        allTenantsProvider.overrideWith((ref) => Stream.value(tenantsList)),
        allTransactionsProvider.overrideWith((ref) => Stream.value([])),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        recentLedgersProvider.overrideWith((ref) => Stream.value([])),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const DashboardScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    // Scroll to Pending Dues
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Pending dues'), findsWidgets);
    expect(find.text('6 tenants yet to pay'), findsOneWidget);

    // Verify tenant due tiles are rendered
    expect(find.text('Tenant 0'), findsWidgets);
    expect(find.text('SM0'), findsWidgets);
    expect(find.text('Call'), findsWidgets);
    expect(find.text('WhatsApp Remind'), findsWidgets);
  });
}
