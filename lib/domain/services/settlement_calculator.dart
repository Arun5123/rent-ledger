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
    double amountPaidByTenant = 0,
    PaymentMethod? paymentMethod,
    String? meterPhotoUrl,
    double? overridePendingRent,
    double? overridePendingMaintenance,
    double? overridePendingEb,
    double? overridePendingOther,
    List<Deduction>? overrideDeductions,
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

    return TenantExitDetails(
      exitedAt: DateTime.now(),
      advanceDeposit: advanceDeposit,
      finalMeterReading: finalMeterReading,
      pendingRent: rent,
      pendingMaintenance: maintenance,
      pendingEb: eb,
      pendingOther: other,
      deductions: ded,
      depositRefunded: depositRefunded ? math.max(0, JsonUtils.money(net)) : 0,
      amountDueFromTenant: remainingDue,
      amountPaidByTenant: paid,
      paymentMethod: paymentMethod,
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

    final expectedRent = rentPerMonth * months;
    final expectedMaintenance = maintenancePerMonth * months;

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
      ElectricityBillingType.FIXED => property.fixedEbAmount * months,
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
    );
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
