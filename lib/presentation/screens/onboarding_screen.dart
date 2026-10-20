import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';

/// First-run wizard collecting the three settings that make the ledger usable:
/// the landlord's name, electricity defaults and reminder preferences.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const int _stepCount = 3;

  final _nameFormKey = GlobalKey<FormState>();
  final _rateFormKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _rateController;

  int _currentStep = 0;
  bool _nameSeeded = false;
  bool _saving = false;
  bool _notificationsEnabled = true;
  int _reminderDay = 1;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _rateController = TextEditingController(
      text: Formatters.units(AppConstants.defaultRatePerUnit),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onContinue() async {
    if (_currentStep == 0) {
      if (!(_nameFormKey.currentState?.validate() ?? false)) return;
      setState(() => _currentStep = 1);
      return;
    }
    if (_currentStep == 1) {
      if (!(_rateFormKey.currentState?.validate() ?? false)) return;
      setState(() => _currentStep = 2);
      return;
    }
    await _finish();
  }

  void _onBack() {
    if (_currentStep == 0) return;
    setState(() => _currentStep -= 1);
  }

  Future<void> _finish() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      _showSnack('You are not signed in. Please sign in again.');
      return;
    }

    setState(() => _saving = true);
    try {
      final repository = ref.read(userRepositoryProvider);
      final base = await repository.ensureProfile(user);
      final rate = double.tryParse(_rateController.text.trim()) ??
          AppConstants.defaultRatePerUnit;

      await repository.saveProfile(
        base.copyWith(
          name: _nameController.text.trim(),
          defaultRatePerUnit: rate,
          notificationsEnabled: _notificationsEnabled,
          rentReminderDay: _reminderDay,
          onboardingComplete: true,
        ),
      );

      final preferences = ref.read(localPreferencesProvider);
      await preferences.setDefaultRatePerUnit(rate);
      await preferences.setNotificationsEnabled(_notificationsEnabled);
      await preferences.setRentReminderDay(_reminderDay);

      await ref.read(onboardingCompleteProvider.notifier).complete();
      // The router's redirect now takes over; this screen is disposed.
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showSnack(
        error is AppException
            ? error.message
            : 'Could not save your setup. Please try again.',
      );
    }
  }

  Widget _controlsBuilder(BuildContext context, ControlsDetails details) {
    final theme = Theme.of(context);
    final isLast = _currentStep == _stepCount - 1;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: _saving ? null : _onContinue,
              child: _saving && isLast
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : Text(isLast ? 'Finish' : 'Continue'),
            ),
          ),
          if (_currentStep > 0) ...[
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : _onBack,
                child: const Text('Back'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Step _nameStep() {
    return Step(
      title: const Text('Your name'),
      subtitle: const Text('Used on reports and settlement statements'),
      isActive: _currentStep == 0,
      state: _currentStep > 0 ? StepState.complete : StepState.indexed,
      content: Form(
        key: _nameFormKey,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Full name',
              hintText: 'e.g. Ramesh Kumar',
            ),
            validator: Validators.name,
          ),
        ),
      ),
    );
  }

  Step _electricityStep(ThemeData theme) {
    return Step(
      title: const Text('Electricity defaults'),
      subtitle: const Text('Applied to new sub-meter properties'),
      isActive: _currentStep == 1,
      state: _currentStep > 1 ? StepState.complete : StepState.indexed,
      content: Form(
        key: _rateFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            TextFormField(
              controller: _rateController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Default rate per unit',
                prefixText: '${AppConstants.currencySymbol} ',
                suffixText: '/ unit',
              ),
              validator: (value) =>
                  Validators.positiveAmount(value, field: 'Rate per unit'),
            ),
            const SizedBox(height: 12),
            Text(
              'For sub-meter properties, RentLedger multiplies this rate by the '
              'units consumed between meter readings to work out the electricity '
              'bill. You can override it for any property later.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.currency_rupee, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Currency', style: theme.textTheme.bodyLarge),
                    ),
                    Text(
                      '${AppConstants.defaultCurrency} '
                      '(${AppConstants.currencySymbol})',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Step _notificationStep(ThemeData theme) {
    return Step(
      title: const Text('Notifications'),
      subtitle: const Text('Rent reminders and due-date nudges'),
      isActive: _currentStep == 2,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Rent reminders'),
            subtitle: const Text('Notify me when rent is due each month'),
            value: _notificationsEnabled,
            onChanged: (value) =>
                setState(() => _notificationsEnabled = value),
          ),
          const SizedBox(height: 8),
          Text('Reminder day of month', style: theme.textTheme.bodyMedium),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _reminderDay.toDouble(),
                  min: 1,
                  max: 28,
                  divisions: 27,
                  label: '$_reminderDay',
                  onChanged: _notificationsEnabled
                      ? (value) =>
                          setState(() => _reminderDay = value.round())
                      : null,
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '$_reminderDay',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Text(
            'Reminders go out on day $_reminderDay of every month (capped at 28 '
            'so the date always exists).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);

    if (!_nameSeeded) {
      _nameController.text = user?.displayName?.trim() ?? '';
      _nameSeeded = true;
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Welcome to ${AppConstants.appName}'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Stepper(
            type: StepperType.vertical,
            currentStep: _currentStep,
            onStepContinue: _onContinue,
            onStepCancel: _currentStep == 0 ? null : _onBack,
            onStepTapped: _saving
                ? null
                : (step) {
                    if (step <= _currentStep) {
                      setState(() => _currentStep = step);
                    }
                  },
            controlsBuilder: _controlsBuilder,
            steps: [
              _nameStep(),
              _electricityStep(theme),
              _notificationStep(theme),
            ],
          ),
        ),
      ),
    );
  }
}
