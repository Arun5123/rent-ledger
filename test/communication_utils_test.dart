import 'package:flutter_test/flutter_test.dart';
import 'package:rentledger/core/utils/communication_utils.dart';

void main() {
  group('CommunicationUtils', () {
    test('cleanPhoneNumber formats 10-digit Indian numbers with country code 91', () {
      expect(CommunicationUtils.cleanPhoneNumber('9876543210'), '919876543210');
      expect(CommunicationUtils.cleanPhoneNumber('+91 98765 43210'), '919876543210');
      expect(CommunicationUtils.cleanPhoneNumber('919876543210'), '919876543210');
    });

    test('buildRentReminder generates proper reminder text', () {
      final msg = CommunicationUtils.buildRentReminder(
        tenantName: 'Suresh',
        propertyName: 'Flat 201',
        amountDue: 15000,
        billingPeriod: 'Oct 2026',
      );

      expect(msg, contains('Hi Suresh'));
      expect(msg, contains('Flat 201'));
      expect(msg, contains('15,000'));
      expect(msg, contains('Oct 2026'));
    });

    test('buildReceiptMessage formats professional receipt', () {
      final msg = CommunicationUtils.buildReceiptMessage(
        tenantName: 'Suresh',
        propertyName: 'Flat 201',
        amount: 15000,
        typeLabel: 'Rent Payment',
        date: DateTime(2026, 10, 5),
        paymentMethodLabel: 'UPI',
      );

      expect(msg, contains('Payment Receipt'));
      expect(msg, contains('Suresh'));
      expect(msg, contains('Flat 201'));
      expect(msg, contains('15,000'));
      expect(msg, contains('UPI'));
      expect(msg, contains('Rent Payment'));
    });
  });
}

