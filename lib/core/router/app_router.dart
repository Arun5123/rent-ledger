import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/app_shell.dart';
import '../../presentation/screens/auth/auth_screen.dart';
import '../../presentation/screens/dashboard/dashboard_screen.dart';
import '../../presentation/screens/onboarding_screen.dart';
import '../../presentation/screens/properties/properties_screen.dart';
import '../../presentation/screens/properties/property_detail_screen.dart';
import '../../presentation/screens/properties/property_form_screen.dart';
import '../../presentation/screens/properties/tenant_onboarding_screen.dart';
import '../../presentation/screens/reports/reports_screen.dart';
import '../../presentation/screens/settings/settings_screen.dart';
import '../../presentation/screens/splash_screen.dart';
import '../../presentation/screens/tenants/tenant_edit_screen.dart';
import '../../presentation/screens/tenants/tenant_exit_wizard_screen.dart';
import '../../presentation/screens/tenants/tenant_history_screen.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';

/// Canonical route table — screens navigate with these helpers so no path
/// string is ever duplicated.
abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String auth = '/auth';
  static const String onboarding = '/onboarding';

  static const String dashboard = '/dashboard';
  static const String properties = '/properties';
  static const String reports = '/reports';
  static const String settings = '/settings';
  static const String history = '/tenants/history';

  static const String newProperty = '/properties/new';

  static String property(String propertyId) => '/properties/$propertyId';
  static String editProperty(String propertyId) => '/properties/$propertyId/edit';

  static String newTenant(String propertyId) =>
      '/properties/$propertyId/tenants/new';

  static String editTenant(String propertyId, String tenantId) =>
      '/properties/$propertyId/tenants/$tenantId/edit';

  static String exitTenant(String propertyId, String tenantId) =>
      '/properties/$propertyId/tenants/$tenantId/exit';
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// The app router. Re-evaluates redirects whenever the session or the
/// first-run flag changes.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen(authStateProvider, (_, _) => refresh.value++)
    ..listen(onboardingCompleteProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final location = state.matchedLocation;
      final onboardingDone = ref.read(onboardingCompleteProvider);

      if (!auth.isResolved) {
        return location == AppRoutes.splash ? null : AppRoutes.splash;
      }

      final signedIn = auth.isSignedIn;

      if (!signedIn) {
        return location == AppRoutes.auth ? null : AppRoutes.auth;
      }

      // Signed in but first-run setup has not been finished yet.
      if (!onboardingDone) {
        return location == AppRoutes.onboarding ? null : AppRoutes.onboarding;
      }

      final onEntryPoint = location == AppRoutes.splash ||
          location == AppRoutes.auth ||
          location == AppRoutes.onboarding;
      return onEntryPoint ? AppRoutes.dashboard : null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.auth,
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.dashboard,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.properties,
                builder: (context, state) => const PropertiesScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const PropertyFormScreen(),
                  ),
                  GoRoute(
                    path: ':propertyId',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => PropertyDetailScreen(
                      propertyId: state.pathParameters['propertyId']!,
                    ),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'edit',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (context, state) => PropertyFormScreen(
                          propertyId: state.pathParameters['propertyId'],
                        ),
                      ),
                      GoRoute(
                        path: 'tenants/new',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (context, state) => TenantOnboardingScreen(
                          propertyId: state.pathParameters['propertyId']!,
                        ),
                      ),
                      GoRoute(
                        path: 'tenants/:tenantId/edit',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (context, state) => TenantEditScreen(
                          propertyId: state.pathParameters['propertyId']!,
                          tenantId: state.pathParameters['tenantId']!,
                        ),
                      ),
                      GoRoute(
                        path: 'tenants/:tenantId/exit',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (context, state) => TenantExitWizardScreen(
                          propertyId: state.pathParameters['propertyId']!,
                          tenantId: state.pathParameters['tenantId']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.reports,
                builder: (context, state) => const ReportsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.history,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const TenantHistoryScreen(),
      ),
    ],
  );
});
