import 'package:flutter_test/flutter_test.dart';
import 'package:rentledger/domain/models/enums.dart';
import 'package:rentledger/domain/models/ledger_transaction.dart';
import 'package:rentledger/domain/models/property.dart';
import 'package:rentledger/domain/models/tenant.dart';
import 'package:rentledger/domain/services/ledger_calculator.dart';

void main() {
  group('LedgerCalculator dues calculation', () {
    final now = DateTime(2026, 10, 15);
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

    final activeTenant = Tenant(
      tenantId: 't1',
      propertyId: 'p1',
      ownerId: 'u1',
      name: 'John Doe',
      phone: '9876543210',
      leaseStartDate: DateTime(2026, 10, 1),
      status: TenantStatus.ACTIVE,
      createdAt: now,
      updatedAt: now,
    );

    test('calculates correct due when no payments recorded', () {
      final due = LedgerCalculator.dueForTenant(
        tenant: activeTenant,
        property: property,
        transactions: const [],
        month: now,
      );

      expect(due, isNotNull);
      expect(due!.expectedAmount, 16000.0);
      expect(due.paidAmount, 0.0);
      expect(due.dueAmount, 16000.0);

      final dashboard = LedgerCalculator.buildDashboard(
        properties: [property],
        tenants: [activeTenant],
        transactions: const [],
        now: now,
      );

      expect(dashboard.pendingDues, 16000.0);
      expect(dashboard.pendingTenantCount, 1);
      expect(dashboard.duesByTenant.length, 1);
      expect(dashboard.duesByTenant.first.tenantName, 'John Doe');
    });

    test('deducts payments matching billing period or current month', () {
      final payment = LedgerTransaction(
        transactionId: 'tx1',
        propertyId: 'p1',
        ownerId: 'u1',
        tenantId: 't1',
        type: TransactionType.RENT_PAYMENT,
        category: TransactionCategory.INCOME,
        amount: 10000,
        billingPeriod: '2026-10',
        recordedAt: DateTime(2026, 10, 5),
        createdBy: 'u1',
        createdAt: now,
      );

      final due = LedgerCalculator.dueForTenant(
        tenant: activeTenant,
        property: property,
        transactions: [payment],
        month: now,
      );

      expect(due, isNotNull);
      expect(due!.expectedAmount, 16000.0);
      expect(due.paidAmount, 10000.0);
      expect(due.dueAmount, 6000.0);
    });

    test('returns null when fully paid (nothing pending)', () {
      final rentPayment = LedgerTransaction(
        transactionId: 'tx1',
        propertyId: 'p1',
        ownerId: 'u1',
        tenantId: 't1',
        type: TransactionType.RENT_PAYMENT,
        category: TransactionCategory.INCOME,
        amount: 15000,
        billingPeriod: '2026-10',
        recordedAt: DateTime(2026, 10, 5),
        createdBy: 'u1',
        createdAt: now,
      );
      final maintPayment = LedgerTransaction(
        transactionId: 'tx2',
        propertyId: 'p1',
        ownerId: 'u1',
        tenantId: 't1',
        type: TransactionType.MAINTENANCE_FEE,
        category: TransactionCategory.INCOME,
        amount: 1000,
        billingPeriod: '2026-10',
        recordedAt: DateTime(2026, 10, 5),
        createdBy: 'u1',
        createdAt: now,
      );

      final due = LedgerCalculator.dueForTenant(
        tenant: activeTenant,
        property: property,
        transactions: [rentPayment, maintPayment],
        month: now,
      );

      // Fully paid months produce no pending due.
      expect(due, isNull);

      final dashboard = LedgerCalculator.buildDashboard(
        properties: [property],
        tenants: [activeTenant],
        transactions: [rentPayment, maintPayment],
        now: now,
      );

      expect(dashboard.pendingDues, 0.0);
      expect(dashboard.pendingTenantCount, 0);
      expect(dashboard.duesByTenant.isEmpty, isTrue);
    });

    test('surfaces dues carried over from previous months', () {
      // Lease started in September; reference date is mid-October.
      final overdueTenant = Tenant(
        tenantId: 't1',
        propertyId: 'p1',
        ownerId: 'u1',
        name: 'John Doe',
        phone: '9876543210',
        leaseStartDate: DateTime(2026, 9, 1),
        status: TenantStatus.ACTIVE,
        createdAt: now,
        updatedAt: now,
      );

      // Only October's rent was paid; September is still pending.
      final octPayment = LedgerTransaction(
        transactionId: 'tx_oct',
        propertyId: 'p1',
        ownerId: 'u1',
        tenantId: 't1',
        type: TransactionType.RENT_PAYMENT,
        category: TransactionCategory.INCOME,
        amount: 16000,
        billingPeriod: '2026-10',
        recordedAt: DateTime(2026, 10, 5),
        createdBy: 'u1',
        createdAt: now,
      );

      final due = LedgerCalculator.dueForTenant(
        tenant: overdueTenant,
        property: property,
        transactions: [octPayment],
        month: now,
      );

      expect(due, isNotNull);
      expect(due!.dueAmount, 16000.0);
      expect(due.monthlyRent, 16000.0);
      expect(due.expectedAmount, 32000.0);
      expect(due.paidAmount, 16000.0);
      expect(due.duePeriods, <String>['2026-09']);

      final dashboard = LedgerCalculator.buildDashboard(
        properties: [property],
        tenants: [overdueTenant],
        transactions: [octPayment],
        now: now,
      );

      expect(dashboard.pendingDues, 16000.0);
      expect(dashboard.pendingTenantCount, 1);
      expect(dashboard.duesByTenant.length, 1);
    });

    test('clears a past month when paid with a matching billing period', () {
      final overdueTenant = Tenant(
        tenantId: 't1',
        propertyId: 'p1',
        ownerId: 'u1',
        name: 'John Doe',
        phone: '9876543210',
        leaseStartDate: DateTime(2026, 9, 1),
        status: TenantStatus.ACTIVE,
        createdAt: now,
        updatedAt: now,
      );

      // September's rent is paid in October with September's billing period.
      final sepPayment = LedgerTransaction(
        transactionId: 'tx_sep',
        propertyId: 'p1',
        ownerId: 'u1',
        tenantId: 't1',
        type: TransactionType.RENT_PAYMENT,
        category: TransactionCategory.INCOME,
        amount: 16000,
        billingPeriod: '2026-09',
        recordedAt: DateTime(2026, 10, 10),
        createdBy: 'u1',
        createdAt: now,
      );

      final due = LedgerCalculator.dueForTenant(
        tenant: overdueTenant,
        property: property,
        transactions: [sepPayment],
        month: now,
      );

      expect(due, isNotNull);
      // September cleared; October still pending.
      expect(due!.dueAmount, 16000.0);
      expect(due.expectedAmount, 32000.0);
      expect(due.paidAmount, 16000.0);
      expect(due.duePeriods, <String>['2026-10']);
    });

    test('aggregates dues across all unpaid months', () {
      final neverPaid = Tenant(
        tenantId: 't1',
        propertyId: 'p1',
        ownerId: 'u1',
        name: 'Never Paid',
        phone: '9876543210',
        leaseStartDate: DateTime(2026, 9, 1),
        status: TenantStatus.ACTIVE,
        createdAt: now,
        updatedAt: now,
      );

      final due = LedgerCalculator.dueForTenant(
        tenant: neverPaid,
        property: property,
        transactions: const [],
        month: now,
      );

      expect(due, isNotNull);
      expect(due!.dueAmount, 32000.0);
      expect(due.expectedAmount, 32000.0);
      expect(due.paidAmount, 0.0);
      expect(due.monthlyRent, 16000.0);
      expect(due.duePeriods, <String>['2026-09', '2026-10']);
    });

    test('future lease tenant has no dues for current month', () {
      final futureTenant = Tenant(
        tenantId: 't2',
        propertyId: 'p1',
        ownerId: 'u1',
        name: 'Future Tenant',
        phone: '9876543211',
        leaseStartDate: DateTime(2026, 11, 1),
        status: TenantStatus.ACTIVE,
        createdAt: now,
        updatedAt: now,
      );

      final due = LedgerCalculator.dueForTenant(
        tenant: futureTenant,
        property: property,
        transactions: const [],
        month: now,
      );

      expect(due, isNull);
    });

    test('exited tenant has no dues in active dashboard', () {
      final exitedTenant = Tenant(
        tenantId: 't3',
        propertyId: 'p1',
        ownerId: 'u1',
        name: 'Exited Tenant',
        phone: '9876543212',
        leaseStartDate: DateTime(2026, 1, 1),
        leaseEndDate: DateTime(2026, 9, 30),
        status: TenantStatus.EXITED,
        createdAt: now,
        updatedAt: now,
      );

      final due = LedgerCalculator.dueForTenant(
        tenant: exitedTenant,
        property: property,
        transactions: const [],
        month: now,
      );

      expect(due, isNull);
    });
  });
}
