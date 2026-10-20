import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/auth_repository_impl.dart';
import '../data/repositories/cloudinary_storage_repository.dart';
import '../data/repositories/ledger_repository_impl.dart';
import '../data/repositories/property_repository_impl.dart';
import '../data/repositories/tenant_repository_impl.dart';
import '../data/repositories/transaction_repository_impl.dart';
import '../data/repositories/user_repository_impl.dart';
import '../data/services/export_file_saver.dart';
import '../data/services/local_preferences.dart';
import '../data/services/report_exporters.dart';
import '../data/services/settlement_statement_pdf.dart';
import '../domain/models/enums.dart';
import '../domain/repositories/repositories.dart';

/// Injected in `main()` after `SharedPreferences` has been loaded.
final localPreferencesProvider = Provider<LocalPreferences>(
  (ref) => throw UnimplementedError(
    'localPreferencesProvider must be overridden in main()',
  ),
);

/// Emits `true` while the device has any usable network transport.
///
/// Firestore keeps serving from cache when this is `false`, which is what
/// drives the offline banner.
final isOnlineProvider = StreamProvider<bool>((ref) {
  final connectivity = Connectivity();
  return connectivity.onConnectivityChanged.map(
    (results) => results.any((result) => result != ConnectivityResult.none),
  );
});

// ------------------------------------------------------- device preferences

/// Mirrors the device-local onboarding flag so GoRouter can redirect
/// synchronously on first launch.
class OnboardingStatusNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(localPreferencesProvider).onboardingComplete;

  Future<void> complete() async {
    await ref.read(localPreferencesProvider).setOnboardingComplete(true);
    state = true;
  }
}

final onboardingCompleteProvider =
    NotifierProvider<OnboardingStatusNotifier, bool>(
  OnboardingStatusNotifier.new,
);

/// Light/dark preference, seeded from the device and persisted locally.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() =>
      ref.watch(localPreferencesProvider).darkMode ? ThemeMode.dark : ThemeMode.light;

  Future<void> setMode(ThemeMode mode) async {
    await ref.read(localPreferencesProvider).setDarkMode(mode == ThemeMode.dark);
    state = mode;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

// ------------------------------------------------------------- repositories

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => FirebaseAuthRepository(firestore: ref.watch(firestoreProvider)),
);

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => FirestoreUserRepository(firestore: ref.watch(firestoreProvider)),
);

final propertyRepositoryProvider = Provider<PropertyRepository>(
  (ref) => FirestorePropertyRepository(firestore: ref.watch(firestoreProvider)),
);

final tenantRepositoryProvider = Provider<TenantRepository>(
  (ref) => FirestoreTenantRepository(firestore: ref.watch(firestoreProvider)),
);

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => FirestoreTransactionRepository(
    firestore: ref.watch(firestoreProvider),
  ),
);

final ledgerRepositoryProvider = Provider<LedgerRepository>(
  (ref) => FirestoreLedgerRepository(firestore: ref.watch(firestoreProvider)),
);

/// Receipts and photos go to Cloudinary, since Cloud Storage needs Blaze.
final storageRepositoryProvider = Provider<StorageRepository>(
  (ref) => CloudinaryStorageRepository(),
);

// ---------------------------------------------------------------- utilities

final exportFileSaverProvider = Provider<ExportFileSaver>(
  (ref) => const ExportFileSaver(),
);

/// Resolves the right exporter for a requested [ExportFormat].
final reportExporterProvider = Provider.family<ReportExporter, ExportFormat>(
  (ref, format) => switch (format) {
    ExportFormat.PDF => const PdfReportExporter(),
    ExportFormat.EXCEL => const ExcelReportExporter(),
    ExportFormat.CSV => const CsvReportExporter(),
  },
);

final settlementStatementBuilderProvider =
    Provider<SettlementStatementBuilder>(
  (ref) => const SettlementStatementPdfBuilder(),
);
