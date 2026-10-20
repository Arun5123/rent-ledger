import 'package:flutter/material.dart';

/// Material 3 theme tuned for an Indian landlord audience: high contrast,
/// large touch targets, calm indigo primary with a warm accent for money.
abstract final class AppTheme {
  static const Color _seed = Color(0xFF1B4D3E);
  static const Color _accent = Color(0xFFF4A300);

  static const Color incomeColor = Color(0xFF1B7F4B);
  static const Color expenseColor = Color(0xFFB3261E);
  static const Color pendingColor = Color(0xFFB26A00);

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final isLight = brightness == Brightness.light;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isLight ? const Color(0xFFF7F8F7) : scheme.surface,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: isLight ? const Color(0xFFF7F8F7) : scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isLight ? Colors.white : scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? Colors.white : scheme.surfaceContainerHigh,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error),
        ),
        labelStyle: const TextStyle(fontWeight: FontWeight.w500),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      // `RawChip` wraps its label in a `DefaultTextStyle` built from
      // `chipTheme.labelStyle`, so this style *replaces* the framework default
      // instead of merging with it. Leaving the colour out therefore drops the
      // `onSurfaceVariant` colour the framework would have applied, and the
      // label falls back to the engine's fixed default colour — invisible on
      // light backgrounds while still looking correct on dark ones.
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: scheme.onSurface,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: scheme.outlineVariant,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 2,
        backgroundColor: isLight ? Colors.white : scheme.surfaceContainerHigh,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.7),
        thickness: 1,
        space: 1,
      ),
      extensions: const <ThemeExtension<dynamic>>[
        RentLedgerColors(),
      ],
    );
  }
}

/// Semantic colours that Material's [ColorScheme] does not express.
@immutable
class RentLedgerColors extends ThemeExtension<RentLedgerColors> {
  const RentLedgerColors({
    this.income = AppTheme.incomeColor,
    this.expense = AppTheme.expenseColor,
    this.pending = AppTheme.pendingColor,
    this.accent = AppTheme._accent,
  });

  final Color income;
  final Color expense;
  final Color pending;
  final Color accent;

  @override
  RentLedgerColors copyWith({
    Color? income,
    Color? expense,
    Color? pending,
    Color? accent,
  }) =>
      RentLedgerColors(
        income: income ?? this.income,
        expense: expense ?? this.expense,
        pending: pending ?? this.pending,
        accent: accent ?? this.accent,
      );

  @override
  RentLedgerColors lerp(RentLedgerColors? other, double t) {
    if (other == null) return this;
    return RentLedgerColors(
      income: Color.lerp(income, other.income, t) ?? income,
      expense: Color.lerp(expense, other.expense, t) ?? expense,
      pending: Color.lerp(pending, other.pending, t) ?? pending,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
    );
  }
}

extension RentLedgerThemeX on BuildContext {
  RentLedgerColors get ledgerColors =>
      Theme.of(this).extension<RentLedgerColors>() ?? const RentLedgerColors();
}
