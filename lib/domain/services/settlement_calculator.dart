import 'dart:math' as math;

import '../../core/utils/formatters.dart';
import '../../core/utils/json_utils.dart';
import '../models/enums.dart';
import '../models/ledger_transaction.dart';
import '../models/property.dart';
import '../models/tenant.dart';

/// Inputs for a tenant exit settlement.
class SettlementInput {
  const SettlementInput({
    required this.property,
    required this.tenant,
    required this.transactions,
    required this.exitDate,
    this.finalMeterReading,
    this.deductions = const <Deduction>[],
    this.pendingOther = 0,
    this.ratePerUnitOverride,
    this.isProRataExitMonth = false,
    this.noticeDate,
    this.requiredNoticeDays = 30,
  });

  final Property property;
  final Tenant tenant;

  /// Every transaction recorded against this tenant.
  final List<LedgerTransaction> transactions;
  final DateTime exitDate;

  /// Sub-meter reading taken on the exit date (SUB_METER properties only).
  final double? finalMeterReading;
  final List<Deduction> deductions;
  final double pendingOther;
  final double? ratePerUnitOverride;

  /// Whether the exit month rent is calculated pro-rata based on actual days.
  final bool isProRataExitMonth;

  /// Date when tenant provided vacating notice (if any).
  final DateTime? noticeDate;

  /// Required notice period days in agreement (default 30).
  final int requiredNoticeDays;
}

/// Standard move-out deduction presets commonly used by apartment & house owners.
abstract final class MoveOutDeductionPresets {
  static const String paintingOneMonth = 'Painting & whitewashing (1 month rent)';
  static const String paintingCustom = 'Painting & whitewashing charges';
  static const String deepCleaning = 'House deep cleaning & sanitization';
  static const String plumbingRepair = 'Plumbing & sanitary fixture repairs';
  static const String carpentryRepair = 'Carpentry, door & lock repairs';
  static const String electricalRepair = 'Electrical fixtures & appliance repairs';
  static const String keyReplacement = 'Lost key & lock replacement';
  static const String societyMaintenance = 'Pending society maintenance dues';
  static const String noticeShortfall = 'Notice period shortfall';
}

/// Standard handover & inspection checklist items before returning deposit.
abstract final class HandoverChecklistItems {
  static const List<String> defaults = <String>[
    'All door, grill & wardrobe keys handed over',
    'Final electricity sub-meter reading recorded & photographed',
    'Electrical appliances (geyser, fans, AC remotes) verified working',
    'Walls, tiles & plumbing fixtures inspected for damage',
    'Society / Building Move-Out clearance (NOC) completed',
  ];
}

/// Fully explainable settlement breakdown.
///
/// The wizard shows every line so the landlord can justify the refund to the
/// tenant, and the same object is persisted into `exitDetails`.
class SettlementBreakdown {
  const SettlementBreakdown({
    required this.advanceDeposit,
    required this.monthsBilled,
    required this.expectedRent,
    required this.expectedMaintenance,
    required this.expectedEb,
    required this.paidRent,
    required this.paidMaintenance,
    required this.paidEb,
    required this.pendingRent,
    required this.pendingMaintenance,
    required this.pendingEb,
    required this.pendingOther,
    required this.deductions,
    required this.finalMeterReading,
    required this.previousMeterReading,
    required this.unitsConsumedAtExit,
    required this.exitMeterCharge,
    required this.rentPerMonth,
    required this.maintenancePerMonth,
    required this.ratePerUnit,
    this.isProRata = false,
    this.exitMonthDays = 0,
    this.daysInExitMonth = 0,
    this.exitMonthRent = 0,
    this.exitMonthMaintenance = 0,
  });

  final double advanceDeposit;
  final int monthsBilled;
  final double expectedRent;
  final double expectedMaintenance;
  final double expectedEb;
  final double paidRent;
  final double paidMaintenance;
  final double paidEb;
  final double pendingRent;
  final double pendingMaintenance;
  final double pendingEb;
  final double pendingOther;
  final List<Deduction> deductions;

  final double finalMeterReading;
  final double previousMeterReading;
  final double unitsConsumedAtExit;
  final double exitMeterCharge;

  final double rentPerMonth;
  final double maintenancePerMonth;
  final double ratePerUnit;

  final bool isProRata;
  final int exitMonthDays;
  final int daysInExitMonth;
  final double exitMonthRent;
  final double exitMonthMaintenance;

  double get totalPending =>
      pendingRent + pendingMaintenance + pendingEb + pendingOther;

  double get totalDeductions =>
      deductions.fold<double>(0, (sum, d) => sum + d.amount);

  /// Positive → refund payable to the tenant.
  double get netSettlement => advanceDeposit - totalPending - totalDeductions;

  double get refundDue => math.max(0, JsonUtils.money(netSettlement));

  double get dueFromTenant => math.max(0, JsonUtils.money(-netSettlement));

  /// Converts an (optionally edited) breakdown into the persisted snapshot.
  TenantExitDetails toExitDetails({
    String? deductionReason,
    String? notes,
    String? exitStatementUrl,
    bool depositRefunded = false,
    double? refundAmount,
    PaymentMethod? refundPaymentMethod,
    String? refundTransactionRef,
    double amountPaidByTenant = 0,
    PaymentMethod? paymentMethod,
    String? meterPhotoUrl,
    double? overridePendingRent,
    double? overridePendingMaintenance,
    double? overridePendingEb,
    double? overridePendingOther,
    List<Deduction>? overrideDeductions,
    bool? isProRataRent,
    List<String>? handoverChecklist,
  }) {
    final rent = overridePendingRent ?? pendingRent;
    final maintenance = overridePendingMaintenance ?? pendingMaintenance;
    final eb = overridePendingEb ?? pendingEb;
    final other = overridePendingOther ?? pendingOther;
    final ded = overrideDeductions ?? deductions;
    final totalPending = rent + maintenance + eb + other;
    final totalDeductions = ded.fold<double>(0, (sum, d) => sum + d.amount);
    final net = advanceDeposit - totalPending - totalDeductions;
    final totalDue = net < 0 ? JsonUtils.money(-net) : 0.0;
    final paid = math.min(totalDue, JsonUtils.money(amountPaidByTenant));
    final remainingDue = math.max(0.0, totalDue - paid);

    final actualRefund = depositRefunded
        ? (refundAmount != null
            ? math.max(0.0, JsonUtils.money(refundAmount))
            : math.max(0.0, JsonUtils.money(net)))
        : 0.0;

    return TenantExitDetails(
      exitedAt: DateTime.now(),
      advanceDeposit: advanceDeposit,
      finalMeterReading: finalMeterReading,
      pendingRent: rent,
      pendingMaintenance: maintenance,
      pendingEb: eb,
      pendingOther: other,
      deductions: ded,
      depositRefunded: actualRefund,
      amountDueFromTenant: remainingDue,
      amountPaidByTenant: paid,
      paymentMethod: paymentMethod,
      refundPaymentMethod: refundPaymentMethod,
      refundTransactionRef: refundTransactionRef,
      isProRataRent: isProRataRent ?? isProRata,
      handoverChecklist: handoverChecklist ?? const <String>[],
      meterPhotoUrl: meterPhotoUrl,
      deductionReason: deductionReason,
      exitStatementUrl: exitStatementUrl,
      notes: notes,
    );
  }
}

/// Pure functions that compute a tenant's exit settlement.
///
/// Expected rent/maintenance is derived from the lease window (inclusive of
/// both the start and the exit month) and offset by what was actually
/// collected. Electricity is the raised EB bills plus the final sub-meter
/// delta, so no consumption is ever lost at handover.
abstract final class SettlementCalculator {
  static SettlementBreakdown calculate(SettlementInput input) {
    final property = input.property;
    final tenant = input.tenant;

    final rentPerMonth = tenant.rentFor(property.baseRent);
    final maintenancePerMonth = tenant.maintenanceFor(property.baseMaintenance);
    final ratePerUnit = input.ratePerUnitOverride ?? property.ratePerUnit;

    final months = _inclusiveMonthCount(
      tenant.leaseStartDate,
      input.exitDate,
    );

    final daysInExitMonth =
        DateTime(input.exitDate.year, input.exitDate.month + 1, 0).day;
    final exitMonthDays = input.exitDate.day;

    final double expectedRent;
    final double expectedMaintenance;
    final double exitMonthRent;
    final double exitMonthMaintenance;

    if (input.isProRataExitMonth) {
      final start = tenant.leaseStartDate;
      final end = input.exitDate;
      final sameMonth = start.year == end.year && start.month == end.month;

      if (sameMonth) {
        final daysOccupied = math.max(1, end.difference(start).inDays + 1);
        final clampedDays = math.min(daysInExitMonth, daysOccupied);
        exitMonthRent = (rentPerMonth / daysInExitMonth) * clampedDays;
        exitMonthMaintenance =
            (maintenancePerMonth / daysInExitMonth) * clampedDays;
        expectedRent = exitMonthRent;
        expectedMaintenance = exitMonthMaintenance;
      } else {
        final priorFullMonths = math.max(
          0,
          (end.year - start.year) * 12 + (end.month - start.month),
        );
        exitMonthRent = (rentPerMonth / daysInExitMonth) * exitMonthDays;
        exitMonthMaintenance =
            (maintenancePerMonth / daysInExitMonth) * exitMonthDays;
        expectedRent = (priorFullMonths * rentPerMonth) + exitMonthRent;
        expectedMaintenance =
            (priorFullMonths * maintenancePerMonth) + exitMonthMaintenance;
      }
    } else {
      expectedRent = rentPerMonth * months;
      expectedMaintenance = maintenancePerMonth * months;
      exitMonthRent = rentPerMonth;
      exitMonthMaintenance = maintenancePerMonth;
    }

    final previousReading = property.currentEbMeterReading;
    final unitsConsumed = input.finalMeterReading == null
        ? 0.0
        : math.max(0.0, input.finalMeterReading! - previousReading);
    final exitMeterCharge =
        property.electricityBillingType == ElectricityBillingType.SUB_METER
            ? unitsConsumed * ratePerUnit
            : 0.0;

    final ebBillsRaised = _sum(
      input.transactions,
      (t) => t.type == TransactionType.EB_BILL && t.isIncome,
    );

    final expectedEb = switch (property.electricityBillingType) {
      ElectricityBillingType.SUB_METER => ebBillsRaised + exitMeterCharge,
      ElectricityBillingType.FIXED => input.isProRataExitMonth
          ? (property.fixedEbAmount * math.max(0, months - 1)) +
              (property.fixedEbAmount / daysInExitMonth) * exitMonthDays
          : property.fixedEbAmount * months,
      ElectricityBillingType.DIRECT_EB => 0.0,
    };

    final paidRent = _sum(
      input.transactions,
      (t) => t.type == TransactionType.RENT_PAYMENT && t.isIncome,
    );
    final paidMaintenance = _sum(
      input.transactions,
      (t) => t.type == TransactionType.MAINTENANCE_FEE && t.isIncome,
    );
    final paidEb = _sum(
      input.transactions,
      (t) =>
          (t.type == TransactionType.EB_BILL ||
              t.type == TransactionType.WATER_BILL) &&
          t.isIncome,
    );

    final pendingRent = math.max(0.0, expectedRent - paidRent);
    final pendingMaintenance =
        math.max(0.0, expectedMaintenance - paidMaintenance);

    /// Pending electricity is what was billed (including the exit reading)
    /// minus what has already been collected.
    final pendingEb = math.max(
      0.0,
      (property.electricityBillingType == ElectricityBillingType.DIRECT_EB
              ? 0
              : expectedEb) -
          paidEb,
    );

    return SettlementBreakdown(
      advanceDeposit: tenant.advanceDepositAmount,
      monthsBilled: months,
      expectedRent: JsonUtils.money(expectedRent),
      expectedMaintenance: JsonUtils.money(expectedMaintenance),
      expectedEb: JsonUtils.money(expectedEb),
      paidRent: JsonUtils.money(paidRent),
      paidMaintenance: JsonUtils.money(paidMaintenance),
      paidEb: JsonUtils.money(paidEb),
      pendingRent: JsonUtils.money(pendingRent),
      pendingMaintenance: JsonUtils.money(pendingMaintenance),
      pendingEb: JsonUtils.money(pendingEb),
      pendingOther: JsonUtils.money(input.pendingOther),
      deductions: input.deductions,
      finalMeterReading: input.finalMeterReading ?? previousReading,
      previousMeterReading: previousReading,
      unitsConsumedAtExit: JsonUtils.money(unitsConsumed),
      exitMeterCharge: JsonUtils.money(exitMeterCharge),
      rentPerMonth: rentPerMonth,
      maintenancePerMonth: maintenancePerMonth,
      ratePerUnit: ratePerUnit,
      isProRata: input.isProRataExitMonth,
      exitMonthDays: exitMonthDays,
      daysInExitMonth: daysInExitMonth,
      exitMonthRent: JsonUtils.money(exitMonthRent),
      exitMonthMaintenance: JsonUtils.money(exitMonthMaintenance),
    );
  }

  /// Computes any shortfall in notice period and the corresponding rent deduction.
  ///
  /// Rental agreements typically require 30 days notice. If a tenant serves
  /// fewer days, the landlord is entitled to deduct rent for the unserved shortfall.
  static ({int shortfallDays, double shortfallRent}) calculateNoticeShortfall({
    required DateTime noticeDate,
    required DateTime exitDate,
    required int requiredNoticeDays,
    required double rentPerMonth,
  }) {
    if (requiredNoticeDays <= 0) {
      return (shortfallDays: 0, shortfallRent: 0.0);
    }
    final daysServed = exitDate.difference(noticeDate).inDays;
    final shortfallDays = math.max(0, requiredNoticeDays - daysServed);
    final dailyRate = rentPerMonth / 30.0;
    final shortfallRent = JsonUtils.money(shortfallDays * dailyRate);
    return (shortfallDays: shortfallDays, shortfallRent: shortfallRent);
  }

  /// How many rent cycles a tenant has completed, counting the exit month.
  static int _inclusiveMonthCount(DateTime start, DateTime end) {
    final from = Formatters.monthStart(start);
    final to = Formatters.monthStart(end);
    final months = (to.year - from.year) * 12 + (to.month - from.month) + 1;
    return months < 1 ? 1 : months;
  }

  static double _sum(
    List<LedgerTransaction> transactions,
    bool Function(LedgerTransaction) test,
  ) =>
      transactions.where(test).fold<double>(0, (sum, t) => sum + t.amount);
}
