import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/auth_api.dart';
import '../../l10n/l10n.dart';

// Only allowlisted presentations reach the UI; server text can contain PII.
String recoveryError(BuildContext context, Object error) {
  final l10n = context.l10n;
  if (error is AuthApiException) {
    switch (error.message) {
      case 'recovery_pending':
        return l10n.recovery_pending_description;
      case 'recovery_expired':
        return l10n.recovery_error_expired;
      case 'recovery_trusted_device_required':
      case 'recovery_session_changed':
        return l10n.recovery_error_trusted_device;
      case 'recovery_already_logged_in':
        return l10n.recovery_error_signed_in;
      case 'recovery_invalid_email':
        return l10n.email_otp_invalid_email;
      case 'recovery_invalid_code':
        return l10n.email_otp_incomplete;
    }
    if (error.kind == AuthApiFailureKind.network) {
      return l10n.connection_failed;
    }
    if (error.statusCode == 429) return l10n.recovery_error_rate_limit;
    if (error.statusCode == 503) return l10n.auth_unavailable;
    if (error.statusCode == 400 ||
        error.statusCode == 401 ||
        error.statusCode == 403 ||
        error.statusCode == 404 ||
        error.statusCode == 410) {
      return l10n.recovery_error_rejected;
    }
  }
  return l10n.recovery_error_generic;
}

bool validRecoveryEmail(String value) =>
    value.length <= 254 &&
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

class RecoveryPage extends StatelessWidget {
  const RecoveryPage({
    super.key,
    required this.title,
    required this.busy,
    required this.children,
    this.error,
  });

  final String title;
  final bool busy;
  final String? error;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        toolbarHeight: MediaQuery.textScalerOf(context).scale(64),
        title: Text(
          title,
          maxLines: 3,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        leading: BackButton(
          onPressed: busy ? null : () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (busy) ...[
                    LinearProgressIndicator(
                      semanticsLabel: context.l10n.loading,
                    ),
                    const SizedBox(height: 16),
                  ],
                  ...children,
                  if (error != null) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        error!,
                        key: const ValueKey('recovery-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class RecoveryCodeForm extends StatelessWidget {
  const RecoveryCodeForm({
    super.key,
    required this.controller,
    required this.busy,
    required this.isCode,
    required this.onSubmit,
    this.onChangeEmail,
  });

  final TextEditingController controller;
  final bool busy;
  final bool isCode;
  final VoidCallback onSubmit;
  final VoidCallback? onChangeEmail;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 24),
      TextField(
        key: ValueKey(isCode ? 'recovery-code' : 'recovery-email'),
        controller: controller,
        enabled: !busy,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: isCode
            ? TextInputType.number
            : TextInputType.emailAddress,
        textInputAction: TextInputAction.done,
        autofillHints: [
          isCode ? AutofillHints.oneTimeCode : AutofillHints.email,
        ],
        inputFormatters: isCode
            ? [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ]
            : [LengthLimitingTextInputFormatter(254)],
        onSubmitted: busy ? null : (_) => onSubmit(),
        decoration: InputDecoration(
          labelText: isCode
              ? context.l10n.email_otp_code_label
              : context.l10n.email_otp_email_label,
        ),
      ),
      const SizedBox(height: 24),
      FilledButton(
        key: const ValueKey('recovery-submit'),
        onPressed: busy ? null : onSubmit,
        child: Text(
          isCode
              ? context.l10n.recovery_verify
              : context.l10n.recovery_send_code,
          textAlign: TextAlign.center,
        ),
      ),
      if (isCode)
        TextButton(
          key: const ValueKey('recovery-change-email'),
          onPressed: busy ? null : onChangeEmail,
          child: Text(context.l10n.recovery_change_email),
        ),
    ],
  );
}
