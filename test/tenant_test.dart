import 'package:flutter_test/flutter_test.dart';
import 'package:rentledger/domain/models/enums.dart';
import 'package:rentledger/domain/models/tenant.dart';

void main() {
  group('Tenant model', () {
    final tenant = Tenant(
      tenantId: 't1',
      propertyId: 'p1',
      ownerId: 'u1',
      name: 'Ravi Kumar',
      phone: '9876543210',
      email: 'ravi@example.com',
      advanceDepositAmount: 50000,
      leaseStartDate: DateTime(2026, 1, 1),
      status: TenantStatus.ACTIVE,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    test('updates name, phone and email via copyWith', () {
      final updated = tenant.copyWith(
        name: 'Ravi K.',
        phone: '9123456789',
        email: 'ravi.k@example.com',
      );

      expect(updated.name, 'Ravi K.');
      expect(updated.phone, '9123456789');
      expect(updated.email, 'ravi.k@example.com');
      expect(updated.tenantId, 't1');
      expect(updated.propertyId, 'p1');
    });

    test('can clear email with clearEmail flag', () {
      final updated = tenant.copyWith(
        clearEmail: true,
      );

      expect(updated.email, isNull);
      expect(updated.name, 'Ravi Kumar');
      expect(updated.phone, '9876543210');
    });

    test('can clear leaseEndDate and overrides with clear flags', () {
      final withEndDate = tenant.copyWith(
        leaseEndDate: DateTime(2026, 12, 31),
        rentOverride: 12000,
        maintenanceOverride: 600,
      );

      expect(withEndDate.leaseEndDate, isNotNull);
      expect(withEndDate.rentOverride, 12000);
      expect(withEndDate.maintenanceOverride, 600);

      final cleared = withEndDate.copyWith(
        clearLeaseEndDate: true,
        clearRentOverride: true,
        clearMaintenanceOverride: true,
      );

      expect(cleared.leaseEndDate, isNull);
      expect(cleared.rentOverride, isNull);
      expect(cleared.maintenanceOverride, isNull);
    });

    test('supports tenant documents and backward compatibility with idProofUrl', () {
      final jsonLegacy = {
        'tenantId': 't1',
        'propertyId': 'p1',
        'ownerId': 'u1',
        'name': 'Ravi Kumar',
        'phone': '9876543210',
        'idProofUrl': 'https://res.cloudinary.com/demo/image/upload/id.jpg',
        'advanceDepositAmount': 50000,
        'leaseStartDate': '2026-01-01T00:00:00.000',
        'status': 'ACTIVE',
        'createdAt': '2026-01-01T00:00:00.000',
      };

      final parsed = Tenant.fromJson('t1', jsonLegacy);
      expect(parsed.documents.length, 1);
      expect(parsed.documents.first.url, 'https://res.cloudinary.com/demo/image/upload/id.jpg');
      expect(parsed.documents.first.name, 'ID Proof');

      final withNewDoc = parsed.copyWith(
        documents: [
          ...parsed.documents,
          TenantDocument(
            id: 'doc2',
            name: 'Rental Agreement',
            url: 'https://res.cloudinary.com/demo/image/upload/agreement.jpg',
            uploadedAt: DateTime(2026, 1, 2),
          ),
        ],
      );

      expect(withNewDoc.documents.length, 2);
      expect(withNewDoc.documents.last.name, 'Rental Agreement');

      final exportedJson = withNewDoc.toJson();
      expect(exportedJson['documents'], isA<List>());
      expect((exportedJson['documents'] as List).length, 2);
    });
  });
}

