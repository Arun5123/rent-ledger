import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'formatters.dart';

/// Utilities for contacting tenants via WhatsApp, phone call, SMS,
/// and sharing transaction receipts.
abstract final class CommunicationUtils {
  /// Cleans phone number to international E.164-style digits (defaulting to India country code 91).
  static String cleanPhoneNumber(String phone, {String defaultCountryCode = '91'}) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) {
      return '$defaultCountryCode$digits';
    }
    return digits;
  }

  /// Opens WhatsApp with the given [phone] and optional pre-filled [message].
  static Future<bool> openWhatsApp({
    required BuildContext context,
    required String phone,
    String? message,
  }) async {
    final clean = cleanPhoneNumber(phone);
    if (clean.isEmpty) {
      _showSnack(context, 'No phone number available.');
      return false;
    }

    final query = message != null && message.isNotEmpty
        ? '?text=${Uri.encodeComponent(message)}'
        : '';
    final uri = Uri.parse('https://wa.me/$clean$query');

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        _showSnack(context, 'Could not launch WhatsApp.');
      }
      return launched;
    } catch (_) {
      if (context.mounted) {
        _showSnack(context, 'Could not open WhatsApp on this device.');
      }
      return false;
    }
  }

  /// Dials the tenant's phone number.
  static Future<bool> makePhoneCall({
    required BuildContext context,
    required String phone,
  }) async {
    final digits = phone.replaceAll(RegExp(r'\s+'), '');
    if (digits.isEmpty) {
      _showSnack(context, 'No phone number available.');
      return false;
    }

    final uri = Uri.parse('tel:$digits');
    try {
      final launched = await launchUrl(uri);
      if (!launched && context.mounted) {
        _showSnack(context, 'Could not make phone call.');
      }
      return launched;
    } catch (_) {
      if (context.mounted) {
        _showSnack(context, 'Calling is not supported on this device.');
      }
      return false;
    }
  }

  /// Sends an SMS with optional pre-filled body.
  static Future<bool> sendSms({
    required BuildContext context,
    required String phone,
    String? body,
  }) async {
    final digits = phone.replaceAll(RegExp(r'\s+'), '');
    if (digits.isEmpty) {
      _showSnack(context, 'No phone number available.');
      return false;
    }

    final query = body != null && body.isNotEmpty
        ? '?body=${Uri.encodeComponent(body)}'
        : '';
    final uri = Uri.parse('sms:$digits$query');

    try {
      final launched = await launchUrl(uri);
      if (!launched && context.mounted) {
        _showSnack(context, 'Could not open SMS.');
      }
      return launched;
    } catch (_) {
      if (context.mounted) {
        _showSnack(context, 'SMS is not supported on this device.');
      }
      return false;
    }
  }

  /// Shares text using the system share sheet (e.g. WhatsApp, Email, Slack, etc.).
  static Future<void> shareText({
    required String text,
    String? subject,
  }) async {
    await Share.share(text, subject: subject);
  }

  /// Builds a polite rent reminder message for WhatsApp or SMS.
  static String buildRentReminder({
    required String tenantName,
    required String propertyName,
    required double amountDue,
    String? billingPeriod,
  }) {
    final periodStr = billingPeriod != null ? ' for $billingPeriod' : '';
    return 'Hi $tenantName,\n\n'
        'This is a friendly reminder that rent of ${Formatters.currency(amountDue)}$periodStr '
        'for $propertyName is due.\n\n'
        'Kindly make the payment at your earliest convenience.\n\n'
        'Thank you!';
  }

  /// Builds a clean payment receipt message for WhatsApp or SMS.
  static String buildReceiptMessage({
    required String tenantName,
    required String propertyName,
    required double amount,
    required String typeLabel,
    required DateTime date,
    String? paymentMethodLabel,
    String? billingPeriod,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('🧾 *Payment Receipt — RentLedger*');
    buffer.writeln('--------------------------------');
    buffer.writeln('Tenant: $tenantName');
    buffer.writeln('Property: $propertyName');
    buffer.writeln('Type: $typeLabel');
    if (billingPeriod != null && billingPeriod.isNotEmpty) {
      buffer.writeln('Period: $billingPeriod');
    }
    buffer.writeln('Amount: ${Formatters.currency(amount)}');
    buffer.writeln('Date: ${Formatters.date(date)}');
    if (paymentMethodLabel != null && paymentMethodLabel.isNotEmpty) {
      buffer.writeln('Method: $paymentMethodLabel');
    }
    buffer.writeln('--------------------------------');
    buffer.writeln('Thank you for your payment!');
    return buffer.toString();
  }

  static void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

