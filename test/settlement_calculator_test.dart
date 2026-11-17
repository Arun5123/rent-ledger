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

    test('computes pro-rata rent for exit month when isProRataExitMonth is true', () {
      final breakdown = SettlementCalculator.calculate(
        SettlementInput(
          property: property,
          tenant: tenant,
          transactions: transactions,
          exitDate: DateTime(2026, 3, 15),
          finalMeterReading: 1050,
          isProRataExitMonth: true,
        ),
      );

      // Jan and Feb are billed full (2 * 10,000 = 20,000).
      // March has 31 days. 15 days = (10,000 / 31) * 15 = 4838.71.
      expect(breakdown.isProRata, isTrue);
      expect(breakdown.exitMonthDays, 15);
      expect(breakdown.daysInExitMonth, 31);
      expect(breakdown.expectedRent, closeTo(24838.71, 0.05));
      expect(breakdown.expectedMaintenance, closeTo(1241.94, 0.05));
      // Paid rent was 20,000, so pending rent is ~4838.71.
      expect(breakdown.pendingRent, closeTo(4838.71, 0.05));
    });

    test('computes pro-rata rent when tenancy is entirely within the same month', () {
      final shortTenant = tenant.copyWith(
        leaseStartDate: DateTime(2026, 3, 5),
      );
      final breakdown = SettlementCalculator.calculate(
        SettlementInput(
          property: property,
          tenant: shortTenant,
          transactions: const <LedgerTransaction>[],
          exitDate: DateTime(2026, 3, 20),
          isProRataExitMonth: true,
        ),
      );

      // March 5 to March 20 = 16 days.
      // (10,000 / 31) * 16 = 5161.29.
      expect(breakdown.isProRata, isTrue);
      expect(breakdown.expectedRent, closeTo(5161.29, 0.05));
    });

    test('calculateNoticeShortfall computes shortfall rent when notice is unserved', () {
      final notice = DateTime(2026, 3, 1);
      final exit = DateTime(2026, 3, 15);
      // 14 days served out of 30 days required => 16 days shortfall.
      final result = SettlementCalculator.calculateNoticeShortfall(
        noticeDate: notice,
        exitDate: exit,
        requiredNoticeDays: 30,
        rentPerMonth: 15000,
      );

      expect(result.shortfallDays, 16);
      // 16 days * (15000 / 30) = 8000
      expect(result.shortfallRent, 8000.0);
    });

    test('calculateNoticeShortfall returns zero shortfall when full notice served', () {
      final notice = DateTime(2026, 2, 1);
      final exit = DateTime(2026, 3, 15); // > 40 days
      final result = SettlementCalculator.calculateNoticeShortfall(
        noticeDate: notice,
        exitDate: exit,
        requiredNoticeDays: 30,
        rentPerMonth: 15000,
      );

      expect(result.shortfallDays, 0);
      expect(result.shortfallRent, 0.0);
    });

    test('captures refund details, transaction ref, and handover checklist in TenantExitDetails', () {
      final breakdown = SettlementCalculator.calculate(
        SettlementInput(
          property: property,
          tenant: tenant,
          transactions: transactions,
          exitDate: DateTime(2026, 3, 15),
          finalMeterReading: 1050,
          deductions: const <Deduction>[
            Deduction(label: MoveOutDeductionPresets.paintingOneMonth, amount: 10000),
            Deduction(label: MoveOutDeductionPresets.deepCleaning, amount: 2500),
          ],
        ),
      );

      final checklist = [
        'All door, grill & wardrobe keys handed over',
        'Final electricity sub-meter reading recorded & photographed',
      ];

      final exitDetails = breakdown.toExitDetails(
        depositRefunded: true,
        refundAmount: 5000,
        refundPaymentMethod: PaymentMethod.BANK_TRANSFER,
        refundTransactionRef: 'HDFC12345678',
        deductionReason: 'Painting and deep cleaning deducted per agreement',
        handoverChecklist: checklist,
      );

      expect(exitDetails.depositRefunded, 5000);
      expect(exitDetails.refundPaymentMethod, PaymentMethod.BANK_TRANSFER);
      expect(exitDetails.refundTransactionRef, 'HDFC12345678');
      expect(exitDetails.handoverChecklist, checklist);
      expect(exitDetails.deductions.length, 2);

      // JSON serialization & deserialization roundtrip
      final json = exitDetails.toJson();
      final restored = TenantExitDetails.fromJson(json);

      expect(restored.depositRefunded, 5000);
      expect(restored.refundPaymentMethod, PaymentMethod.BANK_TRANSFER);
      expect(restored.refundTransactionRef, 'HDFC12345678');
      expect(restored.handoverChecklist, checklist);
      expect(restored.deductions.length, 2);
      expect(restored.deductionReason, 'Painting and deep cleaning deducted per agreement');
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
