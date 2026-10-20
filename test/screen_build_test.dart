import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentledger/domain/models/enums.dart';
import 'package:rentledger/domain/models/property.dart';
import 'package:rentledger/domain/models/tenant.dart';
import 'package:rentledger/presentation/screens/dashboard/dashboard_screen.dart';
import 'package:rentledger/providers/app_providers.dart';
import 'package:rentledger/providers/auth_providers.dart';
import 'package:rentledger/providers/property_providers.dart';
import 'package:rentledger/providers/tenant_providers.dart';
import 'package:rentledger/providers/transaction_providers.dart';

void main() {
  testWidgets('DashboardScreen renders content after scroll', (tester) async {
    final now = DateTime.now();
    final property = Property(
      propertyId: 'p1',
      propertyName: 'Flat 101',
      address: '123 Main St',
      city: 'Chennai',
      currentStatus: PropertyStatus.OCCUPIED,
      baseRent: 15000,
      baseMaintenance: 1000,
      createdAt: now,
      updatedAt: now,
    );
    final tenant = Tenant(
      tenantId: 't1',
      propertyId: 'p1',
      ownerId: 'u1',
      name: 'John Doe',
      phone: '9876543210',
      leaseStartDate: DateTime(now.year, now.month, 1),
      status: TenantStatus.ACTIVE,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue('u1'),
          propertiesProvider.overrideWith((ref) => Stream.value([property])),
          allTenantsProvider.overrideWith((ref) => Stream.value([tenant])),
          propertyTenantsProvider('p1').overrideWith((ref) => Stream.value([tenant])),
          allTransactionsProvider.overrideWith((ref) => Stream.value([])),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
          recentLedgersProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const MaterialApp(
          home: DashboardScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // Scroll down to see Pending Dues
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Flat 101'), findsWidgets);
    expect(find.text('John Doe'), findsWidgets);
  });
}
