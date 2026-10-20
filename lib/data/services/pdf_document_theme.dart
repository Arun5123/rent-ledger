import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/formatters.dart';
import '../../domain/models/ledger_transaction.dart';
import '../../domain/models/report.dart';

/// Fonts + shared layout blocks for every generated PDF.
///
/// The rupee glyph (U+20B9) is missing from the PDF built-in Helvetica, so we
/// try to load Noto Sans first and gracefully degrade to `Rs.` when the font
/// cannot be fetched (e.g. first export while fully offline).
class PdfFontSet {
  const PdfFontSet({
    required this.regular,
    required this.bold,
    required this.currencySymbol,
  });

  final pw.Font regular;
  final pw.Font bold;

  /// Either `₹` or the ASCII fallback `Rs.`.
  final String currencySymbol;

  static const PdfColor _ink = PdfColor.fromInt(0xFF1F2933);
  static const PdfColor _muted = PdfColor.fromInt(0xFF6B7280);
  static const PdfColor _line = PdfColor.fromInt(0xFFE5E7EB);
  static const PdfColor _band = PdfColor.fromInt(0xFFF3F4F6);
  static const PdfColor _primary = PdfColor.fromInt(0xFF1B4D3E);
  static const PdfColor _positive = PdfColor.fromInt(0xFF1B7F4B);
  static const PdfColor _negative = PdfColor.fromInt(0xFFB3261E);

  static PdfColor get ink => _ink;
  static PdfColor get muted => _muted;
  static PdfColor get line => _line;
  static PdfColor get band => _band;
  static PdfColor get primary => _primary;
  static PdfColor get positive => _positive;
  static PdfColor get negative => _negative;

  static Future<PdfFontSet> resolve() async {
    try {
      final regular = await PdfGoogleFonts.notoSansRegular();
      final bold = await PdfGoogleFonts.notoSansBold();
      return PdfFontSet(
        regular: regular,
        bold: bold,
        currencySymbol: AppConstants.currencySymbol,
      );
    } catch (_) {
      return PdfFontSet(
        regular: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        currencySymbol: 'Rs. ',
      );
    }
  }

  pw.TextStyle get body => pw.TextStyle(font: regular, fontSize: 9, color: ink);
  pw.TextStyle get bodyMuted =>
      pw.TextStyle(font: regular, fontSize: 8.5, color: muted);
  pw.TextStyle get bodyBold =>
      pw.TextStyle(font: bold, fontSize: 9, color: ink);
  pw.TextStyle get label => pw.TextStyle(font: bold, fontSize: 7.5, color: muted);
  pw.TextStyle get heading =>
      pw.TextStyle(font: bold, fontSize: 13, color: ink);
  pw.TextStyle get title => pw.TextStyle(font: bold, fontSize: 17, color: primary);

  String money(num amount) {
    final formatted = Formatters.currency(amount).replaceFirst(
      AppConstants.currencySymbol,
      currencySymbol,
    );
    return formatted;
  }

  String moneyShort(num amount) => Formatters.currencyShort(amount).replaceFirst(
        AppConstants.currencySymbol,
        currencySymbol,
      );
}

abstract final class PdfBlocks {
  /// Document header: brand line, title and an optional subtitle.
  static pw.Widget header({
    required PdfFontSet fonts,
    required String title,
    String? subtitle,
    String? trailing,
  }) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(AppConstants.appName.toUpperCase(),
                      style: fonts.label),
                  pw.SizedBox(height: 2),
                  pw.Text(title, style: fonts.title),
                ],
              ),
              if (trailing != null)
                pw.Text(trailing, style: fonts.bodyMuted),
            ],
          ),
          if (subtitle != null) ...[
            pw.SizedBox(height: 4),
            pw.Text(subtitle, style: fonts.bodyMuted),
          ],
          pw.SizedBox(height: 8),
          pw.Container(height: 1.2, color: PdfFontSet.primary),
          pw.SizedBox(height: 12),
        ],
      );

  /// Two-column label/value panel.
  static pw.Widget detailPanel({
    required PdfFontSet fonts,
    required List<(String, String)> rows,
    String? title,
  }) =>
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfFontSet.band,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              pw.Text(title.toUpperCase(), style: fonts.label),
              pw.SizedBox(height: 6),
            ],
            ...rows.map(
              (row) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      flex: 4,
                      child: pw.Text(row.$1, style: fonts.bodyMuted),
                    ),
                    pw.Expanded(
                      flex: 6,
                      child: pw.Text(
                        row.$2,
                        style: fonts.bodyBold,
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  /// Transactions table used by the report exports.
  static pw.Widget transactionTable({
    required PdfFontSet fonts,
    required ReportBundle bundle,
  }) {
    final headers = <String>[
      'Date',
      'Type',
      'Tenant',
      'Period',
      'Method',
      'Amount',
    ];

    final rows = bundle.transactions.map((txn) {
      return <String>[
        Formatters.date(txn.recordedAt),
        txn.type.label,
        txn.tenantName ?? (txn.isExpense ? '—' : 'Owner'),
        Formatters.monthLabel(txn.billingPeriod),
        txn.paymentMethod.label,
        '${txn.isExpense ? '-' : ''}${fonts.moneyShort(txn.amount)}',
      ];
    }).toList(growable: false);

    if (rows.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 24),
        alignment: pw.Alignment.center,
        child: pw.Text('No transactions in this period.', style: fonts.bodyMuted),
      );
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: fonts.label,
      headerDecoration: const pw.BoxDecoration(color: PdfFontSet._band),
      cellStyle: fonts.body,
      cellAlignments: const <int, pw.Alignment>{
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerLeft,
        4: pw.Alignment.centerLeft,
        5: pw.Alignment.centerRight,
      },
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfFontSet.line, width: 0.5),
        bottom: pw.BorderSide(color: PdfFontSet.line, width: 0.5),
      ),
      headerPadding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(1.5),
        1: pw.FlexColumnWidth(1.5),
        2: pw.FlexColumnWidth(2.2),
        3: pw.FlexColumnWidth(1.3),
        4: pw.FlexColumnWidth(1.3),
        5: pw.FlexColumnWidth(1.5),
      },
    );
  }

  /// Line-item table (deductions, ledger breakdowns, ...).
  static pw.Widget lineItemTable({
    required PdfFontSet fonts,
    required List<(String, String)> items,
    String? totalLabel,
    String? totalValue,
    PdfColor? totalColor,
  }) {
    if (items.isEmpty) return pw.SizedBox.shrink();
    return pw.Column(
      children: [
        ...items.map(
          (item) => pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfFontSet._line, width: 0.5),
              ),
            ),
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Row(
              children: [
                pw.Expanded(child: pw.Text(item.$1, style: fonts.body)),
                pw.Text(item.$2,
                    style: fonts.bodyBold, textAlign: pw.TextAlign.right),
              ],
            ),
          ),
        ),
        if (totalLabel != null && totalValue != null) ...[
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(totalLabel,
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 10,
                      color: PdfFontSet.ink,
                    )),
              ),
              pw.Text(
                totalValue,
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 12,
                  color: totalColor ?? PdfFontSet.ink,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Repeated on every page.
  static pw.Widget footer({
    required PdfFontSet fonts,
    required String note,
    required pw.Context context,
  }) =>
      pw.Column(
        children: [
          pw.Container(height: 0.6, color: PdfFontSet.line),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(child: pw.Text(note, style: fonts.bodyMuted)),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: fonts.bodyMuted,
              ),
            ],
          ),
        ],
      );

  static String describeFilter(ReportBundle bundle, String allLabel) {
    final filter = bundle.filter;
    final range =
        '${Formatters.date(filter.from)} – ${Formatters.date(filter.to)}';
    final scope = filter.propertyId == null
        ? allLabel
        : bundle.propertyNameFor(filter.propertyId!);
    return '$range  •  $scope';
  }

  /// Human readable file name, e.g. `RentLedger_Report_2026-04-01_2026-04-30.pdf`.
  static String fileNameFor(ReportBundle bundle, String extension) {
    final filter = bundle.filter;
    final from = DateFormat('yyyy-MM-dd').format(filter.from);
    final to = DateFormat('yyyy-MM-dd').format(filter.to);
    final scope = filter.propertyId == null
        ? 'All'
        : bundle.propertyNameFor(filter.propertyId!).replaceAll(
              RegExp(r'[^A-Za-z0-9]+'),
              '',
            );
    return 'RentLedger_Report_${scope}_${from}_$to.$extension';
  }

  static String describeTransactionScope(LedgerTransaction txn) =>
      txn.isExpense ? 'Owner expense' : (txn.tenantName ?? 'Tenant');
}
