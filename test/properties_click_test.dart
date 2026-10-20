import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentledger/core/router/app_router.dart';
import 'package:rentledger/domain/models/auth_user.dart';
import 'package:rentledger/domain/models/enums.dart';
import 'package:rentledger/domain/models/property.dart';
import 'package:rentledger/domain/models/tenant.dart';
import 'package:rentledger/providers/app_providers.dart';
import 'package:rentledger/providers/auth_providers.dart';
import 'package:rentledger/providers/property_providers.dart';
import 'package:rentledger/providers/tenant_providers.dart';
import 'package:rentledger/providers/transaction_providers.dart';

void main() {
  testWidgets('Clicking property from PropertiesScreen navigates to PropertyDetailScreen', (tester) async {
    final now = DateTime.now();
    final property = Property(
      propertyId: 'p1',
      propertyName: 'Flat 101',
      address: '123 Main St',
      city: 'Chennai',
      currentStatus: PropertyStatus.OCCUPIED,
      baseRent: 15000,
      baseMaintenance: 1000,
      createdAt: now,
      updatedAt: now,
    );
    final tenant = Tenant(
      tenantId: 't1',
      propertyId: 'p1',
      ownerId: 'u1',
      name: 'John Doe',
      phone: '9876543210',
      leaseStartDate: DateTime(now.year, now.month, 1),
      status: TenantStatus.ACTIVE,
      createdAt: now,
      updatedAt: now,
    );

    final container = ProviderContainer(
      overrides: [
        currentUidProvider.overrideWithValue('u1'),
        authStateProvider.overrideWith(() => _MockAuthNotifier(
              const AuthState(
                status: AuthStatus.signedIn,
                user: AuthUser(uid: 'u1', email: 'test@example.com'),
              ),
            )),
        onboardingCompleteProvider.overrideWith(() => _MockOnboardingNotifier(true)),
        propertiesProvider.overrideWith((ref) => Stream.value([property])),
        allTenantsProvider.overrideWith((ref) => Stream.value([tenant])),
        propertyTenantsProvider('p1').overrideWith((ref) => Stream.value([tenant])),
        propertyTransactionsProvider('p1').overrideWith((ref) => Stream.value([])),
        allTransactionsProvider.overrideWith((ref) => Stream.value([])),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        recentLedgersProvider.overrideWith((ref) => Stream.value([])),
      ],
    );

    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // Tap on Properties tab in bottom navigation bar
    await tester.tap(find.text('Properties'));
    await tester.pumpAndSettle();

    expect(find.text('Properties'), findsWidgets);
    expect(find.text('Flat 101'), findsOneWidget);

    // Tap on Flat 101
    await tester.tap(find.text('Flat 101'));
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/properties/p1');
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);
  });
}

class _MockAuthNotifier extends AuthStateNotifier {
  _MockAuthNotifier(this._state);
  final AuthState _state;
  @override
  AuthState build() => _state;
}

class _MockOnboardingNotifier extends OnboardingStatusNotifier {
  _MockOnboardingNotifier(this._val);
  final bool _val;
  @override
  bool build() => _val;
}
