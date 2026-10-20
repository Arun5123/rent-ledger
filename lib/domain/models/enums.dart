/// Pure Dart enums for the domain layer (no Flutter imports).
library;

/// Resolves an enum by its [Enum.name], falling back when data is unknown.
T enumFromName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is T) return raw;
  final name = raw?.toString();
  if (name != null && name.isNotEmpty) {
    for (final value in values) {
      if (value.name == name) return value;
    }
  }
  return fallback;
}

enum PropertyStatus {
  VACANT,
  OCCUPIED,
  UNDER_MAINTENANCE;

  String get label => switch (this) {
        PropertyStatus.VACANT => 'Vacant',
        PropertyStatus.OCCUPIED => 'Occupied',
        PropertyStatus.UNDER_MAINTENANCE => 'Maintenance',
      };
}

enum PropertyType {
  APARTMENT,
  INDEPENDENT_HOUSE,
  VILLA,
  SHOP,
  OFFICE,
  PG_HOSTEL,
  WAREHOUSE,
  OTHER;

  String get label => switch (this) {
        PropertyType.APARTMENT => 'Apartment',
        PropertyType.INDEPENDENT_HOUSE => 'Independent House',
        PropertyType.VILLA => 'Villa',
        PropertyType.SHOP => 'Shop',
        PropertyType.OFFICE => 'Office',
        PropertyType.PG_HOSTEL => 'PG / Hostel',
        PropertyType.WAREHOUSE => 'Warehouse',
        PropertyType.OTHER => 'Other',
      };
}

enum ElectricityBillingType {
  /// Landlord reads a sub-meter and bills tenant at [Property.ratePerUnit].
  SUB_METER,

  /// Tenant pays the electricity board directly — nothing to bill.
  DIRECT_EB,

  /// A flat monthly amount is charged with the rent.
  FIXED;

  String get label => switch (this) {
        ElectricityBillingType.SUB_METER => 'Sub-meter (per unit)',
        ElectricityBillingType.DIRECT_EB => 'Tenant pays EB directly',
        ElectricityBillingType.FIXED => 'Fixed monthly amount',
      };
}

enum TenantStatus {
  ACTIVE,
  EXITED;

  String get label => switch (this) {
        TenantStatus.ACTIVE => 'Active',
        TenantStatus.EXITED => 'Exited',
      };
}

enum TransactionType {
  RENT_PAYMENT,
  MAINTENANCE_FEE,
  EB_BILL,
  WATER_BILL,
  ADVANCE_RECEIVED,
  ADVANCE_REFUND,
  PROPERTY_EXPENSE,
  OTHER;

  String get label => switch (this) {
        TransactionType.RENT_PAYMENT => 'Rent',
        TransactionType.MAINTENANCE_FEE => 'Maintenance',
        TransactionType.EB_BILL => 'Electricity',
        TransactionType.WATER_BILL => 'Water',
        TransactionType.ADVANCE_RECEIVED => 'Advance received',
        TransactionType.ADVANCE_REFUND => 'Advance refund',
        TransactionType.PROPERTY_EXPENSE => 'Property expense',
        TransactionType.OTHER => 'Other',
      };

  TransactionCategory get defaultCategory => switch (this) {
        TransactionType.ADVANCE_REFUND => TransactionCategory.EXPENSE,
        TransactionType.PROPERTY_EXPENSE => TransactionCategory.EXPENSE,
        _ => TransactionCategory.INCOME,
      };

  /// Types that must be attributed to a tenant (or 'Owner' for expenses).
  bool get requiresTenant => switch (this) {
        TransactionType.PROPERTY_EXPENSE => false,
        _ => true,
      };

  /// Electricity bills capture meter readings.
  bool get usesMeterReading => this == TransactionType.EB_BILL;

  /// Counts towards "rent collected" style metrics for a period.
  bool get isRecurringIncome => switch (this) {
        TransactionType.RENT_PAYMENT ||
        TransactionType.MAINTENANCE_FEE ||
        TransactionType.EB_BILL ||
        TransactionType.WATER_BILL =>
          true,
        _ => false,
      };
}

enum TransactionCategory {
  INCOME,
  EXPENSE;

  String get label => switch (this) {
        TransactionCategory.INCOME => 'Income',
        TransactionCategory.EXPENSE => 'Expense',
      };
}

enum ExpenseCategory {
  MAINTENANCE,
  PLUMBING,
  ELECTRICAL,
  PAINTING,
  PROPERTY_TAX,
  APPLIANCE_REPAIR,
  CLEANING,
  LEGAL_FEES,
  OTHER;

  String get label => switch (this) {
        ExpenseCategory.MAINTENANCE => 'Maintenance',
        ExpenseCategory.PLUMBING => 'Plumbing',
        ExpenseCategory.ELECTRICAL => 'Electrical',
        ExpenseCategory.PAINTING => 'Painting',
        ExpenseCategory.PROPERTY_TAX => 'Property Tax',
        ExpenseCategory.APPLIANCE_REPAIR => 'Appliance Repair',
        ExpenseCategory.CLEANING => 'Cleaning',
        ExpenseCategory.LEGAL_FEES => 'Legal / Documentation',
        ExpenseCategory.OTHER => 'Other',
      };
}

enum PaymentMethod {
  CASH,
  UPI,
  BANK_TRANSFER,
  CHEQUE,
  OTHER;

  String get label => switch (this) {
        PaymentMethod.CASH => 'Cash',
        PaymentMethod.UPI => 'UPI',
        PaymentMethod.BANK_TRANSFER => 'Bank transfer',
        PaymentMethod.CHEQUE => 'Cheque',
        PaymentMethod.OTHER => 'Other',
      };
}

enum ExportFormat {
  PDF,
  EXCEL,
  CSV;

  String get label => switch (this) {
        ExportFormat.PDF => 'PDF',
        ExportFormat.EXCEL => 'Excel',
        ExportFormat.CSV => 'CSV',
      };

  String get extension => switch (this) {
        ExportFormat.PDF => 'pdf',
        ExportFormat.EXCEL => 'xlsx',
        ExportFormat.CSV => 'csv',
      };
}
