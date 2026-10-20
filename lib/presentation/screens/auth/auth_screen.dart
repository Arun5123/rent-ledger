import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/validators.dart';
import '../../../providers/auth_providers.dart';

/// Which credential the landlord is using on the shared sign-in screen.
enum _AuthMode { phone, email }

/// Single entry point for authentication: phone (OTP) or email/password,
/// plus Google. Successful sign-in needs no navigation here — the router
/// redirect reacts to the auth session automatically.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();

  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  _AuthMode _mode =
      AppConstants.phoneAuthEnabled ? _AuthMode.phone : _AuthMode.email;
  bool _creatingAccount = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String _fullPhoneNumber() {
    final digits = _phoneController.text.trim().replaceAll(RegExp(r'\s+'), '');
    return '${AppConstants.defaultCountryCode}$digits';
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendCode() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref
        .read(phoneAuthControllerProvider.notifier)
        .sendCode(_fullPhoneNumber());
  }

  Future<void> _verifyCode() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref
        .read(phoneAuthControllerProvider.notifier)
        .verify(_otpController.text.trim());
  }

  Future<void> _resendCode() async {
    await ref
        .read(phoneAuthControllerProvider.notifier)
        .sendCode(_fullPhoneNumber());
  }

  Future<void> _submitEmail() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final controller = ref.read(authActionControllerProvider.notifier);
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (_creatingAccount) {
      await controller.signUpWithEmail(
        email,
        password,
        name: _nameController.text.trim(),
      );
    } else {
      await controller.signInWithEmail(email, password);
    }
  }

  Future<void> _continueWithGoogle() async {
    FocusScope.of(context).unfocus();
    await ref.read(authActionControllerProvider.notifier).signInWithGoogle();
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (Validators.requiredEmail(email) != null) {
      _showSnack('Enter your email above, then tap "Forgot password?" again.');
      return;
    }
    final confirmed = await _confirm(
      title: 'Reset password',
      message: 'Send a password reset link to $email?',
      confirmLabel: 'Send link',
    );
    if (!confirmed) return;
    final sent = await ref
        .read(authActionControllerProvider.notifier)
        .sendPasswordReset(email);
    if (sent) _showSnack('Password reset link sent to $email.');
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _progress(Color color) => SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: color),
      );

  Widget _branding(ThemeData theme) {
    return Column(
      children: [
        Container(
          height: 72,
          width: 72,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            Icons.apartment_rounded,
            size: 38,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppConstants.appName,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Sign in to manage your rentals',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _errorText(ThemeData theme, String message) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _phoneFields(ThemeData theme, PhoneAuthState phoneState) {
    if (!phoneState.codeSent) {
      return [
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Phone number',
            prefixText: '${AppConstants.defaultCountryCode} ',
            hintText: '9876543210',
          ),
          validator: (_) => Validators.phone(_fullPhoneNumber()),
          onFieldSubmitted: (_) => _sendCode(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: phoneState.sendingCode ? null : _sendCode,
          child: phoneState.sendingCode
              ? _progress(theme.colorScheme.onPrimary)
              : const Text('Send OTP'),
        ),
      ];
    }
    return [
      TextFormField(
        controller: _otpController,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        maxLength: 6,
        decoration: const InputDecoration(
          labelText: 'Enter 6-digit OTP',
          counterText: '',
          hintText: '------',
        ),
        validator: Validators.otp,
        onFieldSubmitted: (_) => _verifyCode(),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: phoneState.sendingCode ? null : _resendCode,
          child: const Text('Resend OTP'),
        ),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: phoneState.verifying ? null : _verifyCode,
        child: phoneState.verifying
            ? _progress(theme.colorScheme.onPrimary)
            : const Text('Verify & continue'),
      ),
    ];
  }

  List<Widget> _emailFields(ThemeData theme, bool actionLoading) {
    return [
      if (_creatingAccount) ...[
        TextFormField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Full name',
            hintText: 'e.g. Ramesh Kumar',
          ),
          validator: Validators.name,
        ),
        const SizedBox(height: 16),
      ],
      TextFormField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Email',
          hintText: 'you@example.com',
        ),
        validator: Validators.email,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _passwordController,
        obscureText: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'Password'),
        validator: Validators.password,
        onFieldSubmitted: (_) => _submitEmail(),
      ),
      if (!_creatingAccount)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: actionLoading ? null : _forgotPassword,
            child: const Text('Forgot password?'),
          ),
        ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: actionLoading ? null : _submitEmail,
        child: actionLoading
            ? _progress(theme.colorScheme.onPrimary)
            : Text(_creatingAccount ? 'Create account' : 'Sign in'),
      ),
      const SizedBox(height: 4),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_creatingAccount ? 'Already have an account?' : 'New here?'),
          TextButton(
            onPressed: actionLoading
                ? null
                : () => setState(() => _creatingAccount = !_creatingAccount),
            child: Text(_creatingAccount ? 'Sign in instead' : 'Create account'),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phoneState = ref.watch(phoneAuthControllerProvider);
    final actionLoading = ref.watch(authActionControllerProvider).isLoading;
    final authError = ref.watch(authErrorProvider);

    ref.listen<String?>(authErrorProvider, (previous, next) {
      if (next != null && next.isNotEmpty && next != previous) {
        _showSnack(next);
      }
    });
    ref.listen<PhoneAuthState>(phoneAuthControllerProvider, (previous, next) {
      final error = next.error;
      if (error != null && error != previous?.error) {
        _showSnack(error);
      }
    });

    final inlineError = phoneState.error ?? authError;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    _branding(theme),
                    const SizedBox(height: 28),
                    if (AppConstants.phoneAuthEnabled) ...[
                      SegmentedButton<_AuthMode>(
                        segments: const [
                          ButtonSegment<_AuthMode>(
                            value: _AuthMode.phone,
                            label: Text('Phone'),
                            icon: Icon(Icons.smartphone_outlined),
                          ),
                          ButtonSegment<_AuthMode>(
                            value: _AuthMode.email,
                            label: Text('Email'),
                            icon: Icon(Icons.mail_outline),
                          ),
                        ],
                        selected: <_AuthMode>{_mode},
                        showSelectedIcon: false,
                        onSelectionChanged: (selection) {
                          setState(() => _mode = selection.first);
                          ref
                              .read(phoneAuthControllerProvider.notifier)
                              .resetError();
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                    if (_mode == _AuthMode.phone)
                      ..._phoneFields(theme, phoneState)
                    else
                      ..._emailFields(theme, actionLoading),
                    if (inlineError != null) ...[
                      const SizedBox(height: 16),
                      _errorText(theme, inlineError),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: actionLoading ? null : _continueWithGoogle,
                      icon: actionLoading
                          ? _progress(theme.colorScheme.primary)
                          : const Icon(Icons.g_mobiledata_rounded, size: 28),
                      label: const Text('Continue with Google'),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
