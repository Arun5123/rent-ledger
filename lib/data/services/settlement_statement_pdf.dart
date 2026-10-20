import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/formatters.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/property.dart';
import '../../domain/models/tenant.dart';
import '../../domain/repositories/repositories.dart';
import 'pdf_document_theme.dart';

/// Renders the "Tenant Exit & Deposit Settlement" statement handed to the
/// tenant (and kept on file for the landlord's records).
class SettlementStatementPdfBuilder implements SettlementStatementBuilder {
  const SettlementStatementPdfBuilder();

  @override
  Future<Uint8List> buildStatement({
    required Property property,
    required Tenant tenant,
    required TenantExitDetails details,
    required String currency,
  }) async {
    final fonts = await PdfFontSet.resolve();
    final document = pw.Document(
      title: 'Exit Settlement — ${tenant.name}',
      author: 'RentLedger',
    );

    final pendingItems = <(String, String)>[
      (
        'Pending rent (${details.pendingRent > 0 ? 'due' : 'settled'})',
        fonts.moneyShort(details.pendingRent),
      ),
      ('Pending maintenance', fonts.moneyShort(details.pendingMaintenance)),
      ('Pending electricity', fonts.moneyShort(details.pendingEb)),
      if (details.pendingOther > 0)
        ('Other dues', fonts.moneyShort(details.pendingOther)),
    ];

    final deductionItems = <(String, String)>[
      ...details.deductions.map(
        (d) => (d.label.isEmpty ? 'Deduction' : d.label, fonts.moneyShort(d.amount)),
      ),
    ];

    final isRefund = details.depositRefunded > 0;

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 22),
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        footer: (context) => PdfBlocks.footer(
          fonts: fonts,
          note: 'Computer generated statement • RentLedger',
          context: context,
        ),
        build: (context) => <pw.Widget>[
          PdfBlocks.header(
            fonts: fonts,
            title: 'Tenant Exit & Deposit Settlement',
            subtitle: '${property.propertyName} • '
                '${property.address.isEmpty ? property.city : property.address}',
            trailing: 'Dated ${Formatters.date(details.exitedAt)}',
          ),
          PdfBlocks.detailPanel(
            fonts: fonts,
            title: 'Parties & tenancy',
            rows: <(String, String)>[
              ('Tenant', tenant.name),
              if (tenant.phone.isNotEmpty) ('Phone', tenant.phone),
              if (tenant.email != null) ('Email', tenant.email!),
              ('Property', property.propertyName),
              ('Lease start', Formatters.date(tenant.leaseStartDate)),
              if (tenant.leaseEndDate != null)
                ('Lease end', Formatters.date(tenant.leaseEndDate!)),
              ('Exit date', Formatters.date(details.exitedAt)),
              ('Rent at exit', fonts.money(tenant.rentFor(property.baseRent))),
              if (property.electricityBillingType ==
                  ElectricityBillingType.SUB_METER)
                (
                  'Final meter reading',
                  '${Formatters.units(details.finalMeterReading)} units '
                      '(prev. ${Formatters.units(property.currentEbMeterReading)})',
                ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text('1. Dues outstanding at exit', style: fonts.heading),
          pw.SizedBox(height: 6),
          PdfBlocks.lineItemTable(
            fonts: fonts,
            items: pendingItems,
            totalLabel: 'Total pending',
            totalValue: fonts.money(details.totalPending),
          ),
          pw.SizedBox(height: 16),
          pw.Text('2. Deductions from deposit', style: fonts.heading),
          pw.SizedBox(height: 6),
          if (deductionItems.isEmpty)
            pw.Text('No deductions applied.', style: fonts.bodyMuted)
          else
            PdfBlocks.lineItemTable(
              fonts: fonts,
              items: deductionItems,
              totalLabel: 'Total deductions',
              totalValue: fonts.money(details.totalDeductions),
            ),
          pw.SizedBox(height: 16),
          pw.Text('3. Settlement', style: fonts.heading),
          pw.SizedBox(height: 6),
          PdfBlocks.detailPanel(
            fonts: fonts,
            rows: <(String, String)>[
              ('Security deposit held', fonts.money(details.advanceDeposit)),
              ('Less: total pending dues', '- ${fonts.money(details.totalPending)}'),
              (
                'Less: total deductions',
                '- ${fonts.money(details.totalDeductions)}'
              ),
              (
                isRefund ? 'Refund payable to tenant' : 'Gross balance due from tenant',
                fonts.money(
                  isRefund
                      ? details.depositRefunded
                      : (details.amountDueFromTenant + details.amountPaidByTenant),
                ),
              ),
              if (details.amountPaidByTenant > 0) ...[
                (
                  'Payment received at exit (${details.paymentMethod?.label ?? 'Received'})',
                  '- ${fonts.money(details.amountPaidByTenant)}',
                ),
                (
                  'Remaining balance due from tenant',
                  fonts.money(details.amountDueFromTenant),
                ),
              ],
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: (isRefund || details.amountDueFromTenant == 0)
                  ? const PdfColor.fromInt(0xFFE7F5EC)
                  : const PdfColor.fromInt(0xFFFDECEA),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    isRefund
                        ? 'Net refund of ${fonts.money(details.depositRefunded)} '
                            'was released to the tenant.'
                        : (details.amountDueFromTenant == 0
                            ? (details.amountPaidByTenant > 0
                                ? 'Fully settled: ${fonts.money(details.amountPaidByTenant)} '
                                    'was received from tenant at exit.'
                                : 'Fully settled: No dues remaining.')
                            : (details.amountPaidByTenant > 0
                                ? '${fonts.money(details.amountPaidByTenant)} paid at exit; '
                                    'Net ${fonts.money(details.amountDueFromTenant)} remains payable by the tenant.'
                                : 'Net ${fonts.money(details.amountDueFromTenant)} '
                                    'remains payable by the tenant.')),
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 10,
                      color: (isRefund || details.amountDueFromTenant == 0)
                          ? PdfFontSet.positive
                          : PdfFontSet.negative,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (details.deductionReason != null &&
              details.deductionReason!.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Reason for deductions', style: fonts.label),
            pw.SizedBox(height: 3),
            pw.Text(details.deductionReason!, style: fonts.body),
          ],
          if (details.notes != null && details.notes!.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Notes', style: fonts.label),
            pw.SizedBox(height: 3),
            pw.Text(details.notes!, style: fonts.body),
          ],
          pw.SizedBox(height: 30),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _signature(fonts, 'Tenant signature'),
              _signature(fonts, 'Landlord signature'),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            'Both parties confirm the meter reading, dues and deductions '
            'recorded above. Settlement is final once signed.',
            style: fonts.bodyMuted,
          ),
        ],
      ),
    );

    return document.save();
  }

  pw.Widget _signature(PdfFontSet fonts, String label) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(width: 180, height: 0.8, color: PdfFontSet.ink),
          pw.SizedBox(height: 4),
          pw.Text(label, style: fonts.bodyMuted),
        ],
      );
}
