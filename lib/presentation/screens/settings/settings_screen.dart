import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/auth_providers.dart';

/// Account, preference and data-management hub for the landlord.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final preferences = ref.watch(localPreferencesProvider);
    final themeMode = ref.watch(themeModeProvider);
    final busy = ref.watch(authActionControllerProvider).isLoading;

    ref.listen<String?>(authErrorProvider, (previous, next) {
      if (next == null || next.isEmpty || next == previous) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(next)));
    });

    final name = profile?.name ?? user?.displayName ?? 'Landlord';
    final contact = (user?.phone?.isNotEmpty ?? false)
        ? user!.phone!
        : (user?.email ?? profile?.email ?? '');
    final ratePerUnit =
        profile?.defaultRatePerUnit ?? preferences.defaultRatePerUnit;
    final notificationsEnabled =
        profile?.notificationsEnabled ?? preferences.notificationsEnabled;
    final reminderDay = profile?.rentReminderDay ?? preferences.rentReminderDay;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _profileCard(context, ref, name, contact),
                const SizedBox(height: 24),
                const SectionHeader(title: 'Preferences'),
                const SizedBox(height: 12),
                _preferencesCard(
                  context,
                  ref,
                  darkMode: themeMode == ThemeMode.dark,
                  notifications: notificationsEnabled,
                  rate: ratePerUnit,
                  reminderDay: reminderDay,
                ),
                const SizedBox(height: 24),
                const SectionHeader(title: 'Records'),
                const SizedBox(height: 12),
                _recordsCard(context),
                const SizedBox(height: 24),
                const SectionHeader(title: 'Data'),
                const SizedBox(height: 12),
                _dataCard(context, ref),
                const SizedBox(height: 24),
                const SectionHeader(title: 'About'),
                const SizedBox(height: 12),
                _aboutCard(context),
                const SizedBox(height: 24),
              ],
            ),
            if (busy) _busyOverlay(context),
          ],
        ),
      ),
    );
  }

  Widget _profileCard(
    BuildContext context,
    WidgetRef ref,
    String name,
    String contact,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: Text(
                    _initials(name),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        contact.isEmpty ? 'No contact on file' : contact,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit name'),
              subtitle: const Text('Shown on reports and statements'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editName(context, ref, name),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preferencesCard(
    BuildContext context,
    WidgetRef ref, {
    required bool darkMode,
    required bool notifications,
    required double rate,
    required int reminderDay,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Dark mode'),
            value: darkMode,
            onChanged: (value) => ref
                .read(themeModeProvider.notifier)
                .setMode(value ? ThemeMode.dark : ThemeMode.light),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Rent reminders'),
            subtitle: const Text('Nudge me when rent is due'),
            value: notifications,
            onChanged: (value) => _setNotifications(ref, value),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.bolt_outlined),
            title: const Text('Default rate per unit'),
            subtitle: const Text('Used for sub-meter electricity billing'),
            trailing: Text(
              '${Formatters.currency(rate)} / unit',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () => _editRate(context, ref, rate),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: const Text('Rent reminder day'),
            subtitle: const Text('Day of the month reminders are sent'),
            trailing: Text(
              'Day $reminderDay',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () => _editReminderDay(context, ref, reminderDay),
          ),
        ],
      ),
    );
  }

  Widget _recordsCard(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.history_outlined),
            title: const Text('Past tenants & history'),
            subtitle: const Text('Review exited tenants and settlements'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.history),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.assessment_outlined),
            title: const Text('Reports & exports'),
            subtitle: const Text('Generate PDF, Excel and CSV statements'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(AppRoutes.reports),
          ),
        ],
      ),
    );
  }

  Widget _dataCard(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: theme.colorScheme.error,
            ),
            title: Text(
              'Delete account',
              style: TextStyle(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: const Text('Permanently remove your account and data'),
            onTap: () => _confirmDeleteAccount(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            subtitle: const Text('You can sign back in any time'),
            onTap: () => _confirmSignOut(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _aboutCard(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Text(
            AppConstants.appName,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppConstants.appTagline,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _busyOverlay(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: theme.colorScheme.scrim.withValues(alpha: 0.32),
          child: const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  Future<void> _setNotifications(WidgetRef ref, bool value) async {
    await ref.read(localPreferencesProvider).setNotificationsEnabled(value);
    final profile = ref.read(userProfileProvider).valueOrNull;
    if (profile != null) {
      await ref
          .read(userRepositoryProvider)
          .saveProfile(profile.copyWith(notificationsEnabled: value));
    }
  }

  Future<void> _editName(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _InputDialog(
        title: 'Edit name',
        label: 'Full name',
        initialValue: current,
        confirmLabel: 'Save',
        validator: Validators.name,
      ),
    );
    if (value == null) return;
    await ref.read(authActionControllerProvider.notifier).updateName(value);
  }

  Future<void> _editRate(
    BuildContext context,
    WidgetRef ref,
    double current,
  ) async {
    final raw = await showDialog<String>(
      context: context,
      builder: (_) => _InputDialog(
        title: 'Default rate per unit',
        label: 'Rate per unit',
        initialValue: Formatters.units(current),
        confirmLabel: 'Save',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        helperText: 'Charged per unit on sub-meter electricity bills.',
        validator: (value) =>
            Validators.positiveAmount(value, field: 'Rate per unit'),
      ),
    );
    if (raw == null) return;
    final rate = double.tryParse(raw);
    if (rate == null) return;

    await ref.read(localPreferencesProvider).setDefaultRatePerUnit(rate);
    final profile = ref.read(userProfileProvider).valueOrNull;
    if (profile != null) {
      await ref
          .read(userRepositoryProvider)
          .saveProfile(profile.copyWith(defaultRatePerUnit: rate));
    }
  }

  Future<void> _editReminderDay(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) async {
    final raw = await showDialog<String>(
      context: context,
      builder: (_) => _InputDialog(
        title: 'Rent reminder day',
        label: 'Day of month (1-28)',
        initialValue: '$current',
        confirmLabel: 'Save',
        keyboardType: TextInputType.number,
        validator: (value) {
          final day = int.tryParse(value ?? '');
          if (day == null || day < 1 || day > 28) {
            return 'Enter a day between 1 and 28';
          }
          return null;
        },
      ),
    );
    if (raw == null) return;
    final day = int.tryParse(raw);
    if (day == null) return;

    await ref.read(localPreferencesProvider).setRentReminderDay(day);
    final profile = ref.read(userProfileProvider).valueOrNull;
    if (profile != null) {
      await ref
          .read(userRepositoryProvider)
          .saveProfile(profile.copyWith(rentReminderDay: day));
    }
  }

  Future<void> _confirmDeleteAccount(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<String>(
      context: context,
      builder: (_) => const _InputDialog(
        title: 'Delete account',
        label: 'Type DELETE to confirm',
        confirmLabel: 'Delete forever',
        exactMatch: 'DELETE',
        destructive: true,
        helperText:
            'This permanently removes your properties, tenants and ledger. '
            'It cannot be undone.',
      ),
    );
    if (confirmed == null) return;
    await ref.read(authActionControllerProvider.notifier).deleteAccount();
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirmDialog(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in again to access your ledger.',
      confirmLabel: 'Sign out',
    );
    if (!confirmed) return;
    await ref.read(authActionControllerProvider.notifier).signOut();
  }
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  final first = parts.first.substring(0, 1);
  final last = parts.length > 1 ? parts.last.substring(0, 1) : '';
  return '$first$last'.toUpperCase();
}

Future<bool> _confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Single-field modal that validates input before popping the trimmed value.
class _InputDialog extends StatefulWidget {
  const _InputDialog({
    required this.title,
    required this.label,
    this.initialValue = '',
    this.confirmLabel = 'Save',
    this.helperText,
    this.keyboardType,
    this.validator,
    this.exactMatch,
    this.destructive = false,
  });

  final String title;
  final String label;
  final String initialValue;
  final String confirmLabel;
  final String? helperText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final String? exactMatch;
  final bool destructive;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (widget.exactMatch != null && value != widget.exactMatch) {
      setState(() => _error = 'Type ${widget.exactMatch} exactly to confirm');
      return;
    }
    final error = widget.validator?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canSubmit =
        widget.exactMatch == null || _controller.text.trim() == widget.exactMatch;
    final capitalise = widget.keyboardType == null && widget.exactMatch == null;

    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: widget.keyboardType,
        textCapitalization: capitalise
            ? TextCapitalization.words
            : TextCapitalization.none,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: _error,
          helperText: widget.helperText,
          helperMaxLines: 3,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: canSubmit ? _submit : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
