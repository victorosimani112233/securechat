import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/auth_api.dart';
import '../../auth/auth_error_policy.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../theme/secure_chat_theme.dart';
import '../../widgets/azure_backdrop.dart';

enum _AuthStep { details, email, otp }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _countryCode = TextEditingController(text: '+90');
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _otp = TextEditingController();
  _AuthStep _step = _AuthStep.details;
  bool _busy = false;
  String? _nameError;
  String? _countryCodeError;
  String? _phoneError;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _countryCode.dispose();
    _phone.dispose();
    _email.dispose();
    _otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AzureBackdrop(
    child: Scaffold(
      appBar: _step == _AuthStep.details
          ? null
          : AppBar(
              title: Text(context.l10n.email_otp_title),
              leading: BackButton(onPressed: _goBack),
            ),
      body: SafeArea(
        top: _step == _AuthStep.details,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) {
            final reverse = child.key == const ValueKey('auth-details');
            return SlideTransition(
              position: Tween<Offset>(
                begin: Offset(reverse ? -0.18 : 0.18, 0),
                end: Offset.zero,
              ).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: _step == _AuthStep.details
              ? _DetailsStep(
                  key: const ValueKey('auth-details'),
                  name: _name,
                  countryCode: _countryCode,
                  phone: _phone,
                  nameError: _nameError,
                  countryCodeError: _countryCodeError,
                  phoneError: _phoneError,
                  onNameChanged: (_) => setState(() => _nameError = null),
                  onCountryChanged: (_) =>
                      setState(() => _countryCodeError = null),
                  onPhoneChanged: (_) => setState(() => _phoneError = null),
                  onContinue: _continueToEmail,
                )
              : _EmailStep(
                  key: ValueKey('auth-${_step.name}'),
                  step: _step,
                  email: _email,
                  otp: _otp,
                  busy: _busy,
                  error: _error,
                  onChanged: () => setState(() => _error = null),
                  onSubmit: _step == _AuthStep.email
                      ? _requestOtp
                      : _verifyAndRegister,
                  onChangeEmail: _busy
                      ? null
                      : () => setState(() {
                          _step = _AuthStep.email;
                          _otp.clear();
                          _error = null;
                        }),
                ),
        ),
      ),
    ),
  );

  void _goBack() {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _step = _step == _AuthStep.otp ? _AuthStep.email : _AuthStep.details;
      _error = null;
    });
  }

  void _continueToEmail() {
    final name = _name.text.trim();
    final country = _countryCode.text.trim();
    final phone = _phone.text.replaceAll(RegExp(r'\D'), '');
    setState(() {
      _nameError = name.isEmpty
          ? context.l10n.validation_name_empty
          : name.length < 2
          ? context.l10n.validation_name_too_short(2)
          : name.length > 50
          ? context.l10n.validation_name_too_long(50)
          : null;
      _countryCodeError = !RegExp(r'^\+[0-9]{1,4}$').hasMatch(country)
          ? context.l10n.validation_country_code_non_digit
          : null;
      _phoneError = phone.length < 10
          ? context.l10n.validation_phone_too_short
          : phone.length > 10
          ? context.l10n.validation_phone_too_long
          : null;
    });
    if (_nameError != null ||
        _countryCodeError != null ||
        _phoneError != null) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _step = _AuthStep.email);
  }

  Future<void> _requestOtp() async {
    final email = _email.text.trim();
    if (!RegExp(
      r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
    ).hasMatch(email)) {
      setState(() => _error = context.l10n.email_otp_invalid_email);
      return;
    }
    final auth = AppContainerScope.of(context).auth;
    if (auth == null) {
      setState(() => _error = context.l10n.auth_unavailable);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await auth.requestOtp(email);
      if (!mounted) return;
      switch (result.status) {
        case OtpRequestStatus.sent:
          setState(() => _step = _AuthStep.otp);
        case OtpRequestStatus.smtpDisabled:
          setState(() => _error = context.l10n.email_otp_smtp_disabled);
        case OtpRequestStatus.rateLimited:
          setState(() {
            _error = context.l10n.rate_limit_seconds(
              result.retryAfter?.inSeconds ?? 60,
            );
          });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _presentAuthError(error, verifying: false));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyAndRegister() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_otp.text.trim())) {
      setState(() => _error = context.l10n.email_otp_incomplete);
      return;
    }
    final auth = AppContainerScope.of(context).auth;
    if (auth == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await auth.verifyOtp(_email.text, _otp.text);
      await auth.registerAndLogin(
        displayName: _name.text,
        phoneNumber: '${_countryCode.text}${_phone.text}',
        registrationToken: token,
      );
      if (mounted) Navigator.of(context).pushReplacementNamed('/');
    } catch (error) {
      if (mounted) {
        setState(() => _error = _presentAuthError(error, verifying: true));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _presentAuthError(Object error, {required bool verifying}) {
    return switch (classifyAuthError(error, duringVerification: verifying)) {
      AuthErrorPresentation.connection => context.l10n.connection_failed,
      AuthErrorPresentation.verificationRejected =>
        context.l10n.email_otp_verify_failed,
      AuthErrorPresentation.requestRejected =>
        context.l10n.email_otp_send_error(
          error is AuthApiException ? error.message : context.l10n.failed,
        ),
    };
  }
}

class _DetailsStep extends StatelessWidget {
  const _DetailsStep({
    super.key,
    required this.name,
    required this.countryCode,
    required this.phone,
    required this.nameError,
    required this.countryCodeError,
    required this.phoneError,
    required this.onNameChanged,
    required this.onCountryChanged,
    required this.onPhoneChanged,
    required this.onContinue,
  });

  final TextEditingController name;
  final TextEditingController countryCode;
  final TextEditingController phone;
  final String? nameError;
  final String? countryCodeError;
  final String? phoneError;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onCountryChanged;
  final ValueChanged<String> onPhoneChanged;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 48),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/images/new_logo.png',
                width: 96,
                height: 96,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              context.l10n.app_name,
              style: const TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: AzureTokens.azure,
                letterSpacing: -.7,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.onboarding_subtitle,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock,
                  size: 14,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    context.l10n.onboarding_e2ee_notice,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 48),
            AzureGlassPanel(
              key: const ValueKey('auth-details-panel'),
              strong: true,
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    context.l10n.register_title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.register_subtitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: name,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    onChanged: onNameChanged,
                    decoration: InputDecoration(
                      labelText: context.l10n.register_name_label,
                      hintText: context.l10n.register_name_placeholder,
                      errorText: nameError,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: countryCode,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          onChanged: onCountryChanged,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(5),
                          ],
                          decoration: InputDecoration(
                            labelText: context.l10n.register_country_code_label,
                            errorText: countryCodeError,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: phone,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [
                            AutofillHints.telephoneNumberNational,
                          ],
                          onChanged: onPhoneChanged,
                          onSubmitted: (_) => onContinue(),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: InputDecoration(
                            labelText: context.l10n.register_phone_label,
                            hintText: context.l10n.register_phone_placeholder,
                            errorText: phoneError,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),
            FilledButton(
              key: const ValueKey('auth-details-continue'),
              onPressed: onContinue,
              style: FilledButton.styleFrom(
                backgroundColor: AzureTokens.azure,
                foregroundColor: Colors.white,
              ),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  context.l10n.register_start,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    ),
  );
}

class _EmailStep extends StatelessWidget {
  const _EmailStep({
    super.key,
    required this.step,
    required this.email,
    required this.otp,
    required this.busy,
    required this.error,
    required this.onChanged,
    required this.onSubmit,
    required this.onChangeEmail,
  });

  final _AuthStep step;
  final TextEditingController email;
  final TextEditingController otp;
  final bool busy;
  final String? error;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;
  final VoidCallback? onChangeEmail;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Column(
      children: [
        const SizedBox(height: 48),
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .14),
          ),
          child: Icon(
            step == _AuthStep.email
                ? Icons.email_outlined
                : Icons.verified_user,
            key: const ValueKey('auth-email-step-icon'),
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          step == _AuthStep.email
              ? context.l10n.email_otp_step_email
              : context.l10n.email_otp_step_code,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          step == _AuthStep.email
              ? context.l10n.email_otp_description_email
              : context.l10n.email_otp_description_code(email.text),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),
        AzureGlassPanel(
          strong: true,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              if (step == _AuthStep.email)
                TextField(
                  controller: email,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.send,
                  autofillHints: const [AutofillHints.email],
                  onChanged: (_) => onChanged(),
                  onSubmitted: (_) => onSubmit(),
                  decoration: InputDecoration(
                    labelText: context.l10n.email_otp_email_label,
                    errorText: error,
                  ),
                )
              else
                TextField(
                  controller: otp,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => onChanged(),
                  onSubmitted: (_) => onSubmit(),
                  decoration: InputDecoration(
                    labelText: context.l10n.email_otp_code_label,
                    counterText: '',
                    errorText: error,
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy ? null : onSubmit,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: busy
                      ? const Center(
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Text(
                          step == _AuthStep.email
                              ? context.l10n.email_otp_send
                              : context.l10n.otp_verify,
                          textAlign: TextAlign.center,
                        ),
                ),
              ),
              if (step == _AuthStep.otp) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onChangeEmail,
                  child: Text(context.l10n.email_otp_change_email),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    ),
  );
}
