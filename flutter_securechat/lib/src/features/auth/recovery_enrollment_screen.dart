import 'package:flutter/material.dart';

import '../../auth/account_recovery_coordinator.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import 'recovery_form_screen.dart';

enum _EnrollmentStep { checking, email, code, bound }

class RecoveryEnrollmentScreen extends StatefulWidget {
  const RecoveryEnrollmentScreen({super.key, this.coordinator});

  final AccountRecoveryCoordinator? coordinator;

  @override
  State<RecoveryEnrollmentScreen> createState() =>
      _RecoveryEnrollmentScreenState();
}

class _RecoveryEnrollmentScreenState extends State<RecoveryEnrollmentScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  AccountRecoveryCoordinator? _recovery;
  RecoveryChallenge? _challenge;
  _EnrollmentStep _step = _EnrollmentStep.checking;
  bool _initialized = false;
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _recovery =
        widget.coordinator ?? AppContainerScope.of(context).auth?.recovery;
    _checkStatus();
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function(AccountRecoveryCoordinator) task,
  ) async {
    if (_busy) return;
    final recovery = _recovery;
    if (recovery == null) {
      setState(() => _error = context.l10n.auth_unavailable);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await task(recovery);
    } catch (error) {
      if (mounted) setState(() => _error = recoveryError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkStatus() => _run((recovery) async {
    final bound = await recovery.getEnrollmentStatus();
    if (!mounted) return;
    setState(() {
      _step = bound ? _EnrollmentStep.bound : _EnrollmentStep.email;
      _challenge = null;
      _code.clear();
      if (bound) _email.clear();
    });
  });

  Future<void> _submit() async {
    if (_busy) return;
    if (_step == _EnrollmentStep.email) {
      if (!validRecoveryEmail(_email.text.trim())) {
        setState(() => _error = context.l10n.email_otp_invalid_email);
        return;
      }
      await _run((recovery) async {
        final challenge = await recovery.requestEnrollment(_email.text.trim());
        if (!mounted) return;
        setState(() {
          _challenge = challenge;
          _code.clear();
          _step = _EnrollmentStep.code;
        });
      });
    } else if (_step == _EnrollmentStep.code) {
      if (!RegExp(r'^[0-9]{6}$').hasMatch(_code.text)) {
        setState(() => _error = context.l10n.email_otp_incomplete);
        return;
      }
      await _run((recovery) async {
        try {
          await recovery.verifyEnrollment(_challenge!, _code.text);
        } catch (_) {
          // The server may have committed before a response was lost.
          // Require a fresh status check before offering enrollment again.
          if (mounted) setState(() => _step = _EnrollmentStep.checking);
          rethrow;
        }
        if (!mounted) return;
        setState(() {
          _step = _EnrollmentStep.bound;
          _challenge = null;
          _code.clear();
          _email.clear();
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return RecoveryPage(
      title: l10n.recovery_email_title,
      busy: _busy,
      error: _error,
      children: switch (_step) {
        _EnrollmentStep.checking => [
          Text(l10n.recovery_checking),
          if (!_busy)
            FilledButton(
              key: const ValueKey('recovery-status-retry'),
              onPressed: _checkStatus,
              child: Text(l10n.recovery_retry),
            ),
        ],
        _EnrollmentStep.bound => [
          const Icon(Icons.verified_user_outlined, size: 48),
          const SizedBox(height: 24),
          Text(l10n.recovery_email_bound),
          const SizedBox(height: 16),
          Text(l10n.recovery_history_warning),
        ],
        _EnrollmentStep.email || _EnrollmentStep.code => [
          Text(
            _step == _EnrollmentStep.email
                ? l10n.recovery_enrollment_description
                : l10n.recovery_request_sent,
          ),
          RecoveryCodeForm(
            controller: _step == _EnrollmentStep.email ? _email : _code,
            busy: _busy,
            isCode: _step == _EnrollmentStep.code,
            onSubmit: _submit,
            onChangeEmail: _checkStatus,
          ),
        ],
      },
    );
  }
}
