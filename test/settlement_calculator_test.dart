import 'package:flutter_test/flutter_test.dart';
import 'package:rentledger/domain/models/enums.dart';
import 'package:rentledger/domain/models/ledger_transaction.dart';
import 'package:rentledger/domain/models/property.dart';
import 'package:rentledger/domain/models/tenant.dart';
import 'package:rentledger/domain/services/settlement_calculator.dart';

/// The two India-specific calculations the product is built on:
/// sub-meter electricity billing and the tenant exit settlement.
void main() {
  group('EbDetails.calculate', () {
    test('multiplies consumed units by the rate', () {
      final details = EbDetails.calculate(
        previousReading: 1000,
        currentReading: 1050,
        unitRate: 8,
      );

      expect(details.unitsConsumed, 50);
      expect(details.amount, 400);
      expect(details.isValid, isTrue);
    });

    test('never bills negative consumption when the meter is replaced', () {
      final details = EbDetails.calculate(
        previousReading: 1000,
        currentReading: 900,
        unitRate: 8,
      );

      expect(details.unitsConsumed, 0);
      expect(details.amount, 0);
      expect(details.isValid, isFalse);
    });
  });

  group('SettlementCalculator.calculate', () {
    final property = Property(
      propertyId: 'p1',
      propertyName: 'Flat 4B',
      address: '12 MG Road',
      city: 'Bengaluru',
      baseRent: 10000,
      baseMaintenance: 500,
      electricityBillingType: ElectricityBillingType.SUB_METER,
      currentEbMeterReading: 1000,
      ratePerUnit: 8,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    final tenant = Tenant(
      tenantId: 't1',
      propertyId: 'p1',
      ownerId: 'u1',
      name: 'Ravi',
      phone: '9876543210',
      advanceDepositAmount: 20000,
      leaseStartDate: DateTime(2026, 1, 1),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    final transactions = <LedgerTransaction>[
      _txn(TransactionType.RENT_PAYMENT, 10000, DateTime(2026, 1, 5)),
      _txn(TransactionType.RENT_PAYMENT, 10000, DateTime(2026, 2, 5)),
      _txn(TransactionType.MAINTENANCE_FEE, 500, DateTime(2026, 1, 5)),
      _txn(TransactionType.MAINTENANCE_FEE, 500, DateTime(2026, 2, 5)),
      _txn(TransactionType.EB_BILL, 800, DateTime(2026, 2, 5)),
    ];

    test('nets the advance against pending dues and the exit meter reading', () {
      final breakdown = SettlementCalculator.calculate(
        SettlementInput(
          property: property,
          tenant: tenant,
          transactions: transactions,
          exitDate: DateTime(2026, 3, 15),
          finalMeterReading: 1050,
        ),
      );

      // Jan, Feb and the exit month March are all billed.
      expect(breakdown.monthsBilled, 3);
      expect(breakdown.expectedRent, 30000);
      expect(breakdown.expectedMaintenance, 1500);

      expect(breakdown.pendingRent, 10000);
      expect(breakdown.pendingMaintenance, 500);

      // 50 units at ₹8 plus the ₹800 already billed, minus the ₹800 collected.
      expect(breakdown.unitsConsumedAtExit, 50);
      expect(breakdown.exitMeterCharge, 400);
      expect(breakdown.expectedEb, 1200);
      expect(breakdown.pendingEb, 400);

      expect(breakdown.totalPending, 10900);
      expect(breakdown.netSettlement, 9100);
      expect(breakdown.refundDue, 9100);
      expect(breakdown.dueFromTenant, 0);
    });

    test('reports money owed by the tenant when dues exceed the advance', () {
      final breakdown = SettlementCalculator.calculate(
        SettlementInput(
          property: property,
          tenant: tenant.copyWith(advanceDepositAmount: 2000),
          transactions: const <LedgerTransaction>[],
          exitDate: DateTime(2026, 3, 15),
          deductions: const <Deduction>[
            Deduction(label: 'Painting', amount: 1500),
          ],
        ),
      );

      expect(breakdown.totalDeductions, 1500);
      expect(breakdown.netSettlement, lessThan(0));
      expect(breakdown.refundDue, 0);
      expect(breakdown.dueFromTenant, breakdown.netSettlement.abs());

      // Test toExitDetails with tenant payment
      final totalDue = breakdown.dueFromTenant;
      final fullPaymentDetails = breakdown.toExitDetails(
        amountPaidByTenant: totalDue,
        paymentMethod: PaymentMethod.UPI,
      );
      expect(fullPaymentDetails.amountPaidByTenant, totalDue);
      expect(fullPaymentDetails.amountDueFromTenant, 0);
      expect(fullPaymentDetails.paymentMethod, PaymentMethod.UPI);
      expect(fullPaymentDetails.depositRefunded, 0);

      // JSON roundtrip
      final json = fullPaymentDetails.toJson();
      final fromJson = TenantExitDetails.fromJson(json);
      expect(fromJson.amountPaidByTenant, totalDue);
      expect(fromJson.amountDueFromTenant, 0);
      expect(fromJson.paymentMethod, PaymentMethod.UPI);

      // Partial payment
      final partialPaymentDetails = breakdown.toExitDetails(
        amountPaidByTenant: 1000,
        paymentMethod: PaymentMethod.CASH,
      );
      expect(partialPaymentDetails.amountPaidByTenant, 1000);
      expect(partialPaymentDetails.amountDueFromTenant, totalDue - 1000);
      expect(partialPaymentDetails.paymentMethod, PaymentMethod.CASH);
    });
  });
}

LedgerTransaction _txn(TransactionType type, double amount, DateTime at) =>
    LedgerTransaction(
      transactionId: '${type.name}-${at.millisecondsSinceEpoch}',
      propertyId: 'p1',
      ownerId: 'u1',
      tenantId: 't1',
      tenantName: 'Ravi',
      type: type,
      category: type.defaultCategory,
      amount: amount,
      billingPeriod: '${at.year}-${at.month.toString().padLeft(2, '0')}',
      recordedAt: at,
      createdBy: 'u1',
      createdAt: at,
    );
