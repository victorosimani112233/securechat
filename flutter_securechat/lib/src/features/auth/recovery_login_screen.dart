import 'package:flutter/material.dart';

import '../../auth/account_recovery_coordinator.dart';
import '../../auth/auth_api.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import 'recovery_form_screen.dart';

enum _LoginStep { checking, email, code, approval, pending }

class RecoveryLoginScreen extends StatefulWidget {
  const RecoveryLoginScreen({super.key, this.coordinator});

  final AccountRecoveryCoordinator? coordinator;

  @override
  State<RecoveryLoginScreen> createState() => _RecoveryLoginScreenState();
}

class _RecoveryLoginScreenState extends State<RecoveryLoginScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  AccountRecoveryCoordinator? _recovery;
  RecoveryChallenge? _challenge;
  RecoveryLoginApproval? _approval;
  _LoginStep _step = _LoginStep.checking;
  bool _initialized = false;
  bool _busy = false;
  bool _accepted = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _recovery =
        widget.coordinator ?? AppContainerScope.of(context).auth?.recovery;
    _checkPending();
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
      if (mounted) {
        setState(() {
          if (error is AuthApiException &&
              error.message == 'recovery_pending') {
            _step = _LoginStep.pending;
            _challenge = null;
            _approval = null;
            _accepted = false;
            _code.clear();
            _email.clear();
            _error = null;
          } else {
            _error = recoveryError(context, error);
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkPending() => _run((recovery) async {
    final pending = await recovery.hasPendingLogin();
    if (!mounted) return;
    setState(() => _step = pending ? _LoginStep.pending : _LoginStep.email);
    if (pending) await _resume(recovery);
  });

  Future<void> _resume(AccountRecoveryCoordinator recovery) async {
    final resumed = await recovery.resumePendingLogin();
    if (!mounted) return;
    if (resumed) {
      _finish();
    } else {
      // A failed completion must not fall back to generating another identity.
      setState(() => _error = context.l10n.recovery_resume_unavailable);
    }
  }

  void _finish() {
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_step == _LoginStep.email) {
      if (!validRecoveryEmail(_email.text.trim())) {
        setState(() => _error = context.l10n.email_otp_invalid_email);
        return;
      }
      await _run((recovery) async {
        final challenge = await recovery.requestLogin(_email.text.trim());
        if (!mounted) return;
        setState(() {
          _challenge = challenge;
          _code.clear();
          _step = _LoginStep.code;
        });
      });
    } else if (_step == _LoginStep.code) {
      if (!RegExp(r'^[0-9]{6}$').hasMatch(_code.text)) {
        setState(() => _error = context.l10n.email_otp_incomplete);
        return;
      }
      await _run((recovery) async {
        final approval = await recovery.verifyLogin(_challenge!, _code.text);
        if (!mounted) return;
        setState(() {
          _approval = approval;
          _accepted = false;
          _challenge = null;
          _code.clear();
          _email.clear();
          _step = _LoginStep.approval;
        });
      });
    }
  }

  Future<void> _complete() async {
    if (_busy || _step != _LoginStep.approval || !_accepted) return;
    final approval = _approval!;
    await _run((recovery) async {
      // Once dispatched, every retry goes through persisted pending state.
      setState(() => _step = _LoginStep.pending);
      await recovery.completeLogin(
        approval,
        acceptIdentityReplacement: approval.requiresIdentityReplacement,
      );
      if (mounted) _finish();
    });
  }

  Future<void> _restart() async {
    if (_busy || _step != _LoginStep.pending) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                namesRoute: true,
                header: true,
                child: Text(
                  dialogContext.l10n.recovery_restart,
                  style: Theme.of(dialogContext).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 16),
              Text(dialogContext.l10n.recovery_restart_warning),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(dialogContext.l10n.cancel),
              ),
              FilledButton(
                key: const ValueKey('recovery-restart-confirm'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(
                  dialogContext.l10n.recovery_restart,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || confirmed != true) return;
    await _run((recovery) async {
      await recovery.restartPendingLogin();
      if (!mounted) return;
      setState(() {
        _approval = null;
        _challenge = null;
        _accepted = false;
        _email.clear();
        _code.clear();
        _step = _LoginStep.email;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return RecoveryPage(
      title: _step == _LoginStep.approval
          ? l10n.recovery_approval_title
          : l10n.recovery_login_title,
      busy: _busy,
      error: _error,
      children: switch (_step) {
        _LoginStep.checking => [
          Text(l10n.recovery_checking),
          if (!_busy)
            FilledButton(
              onPressed: _checkPending,
              child: Text(l10n.recovery_retry),
            ),
        ],
        _LoginStep.email || _LoginStep.code => [
          Text(
            _step == _LoginStep.email
                ? l10n.recovery_login_description
                : l10n.recovery_request_sent,
          ),
          RecoveryCodeForm(
            controller: _step == _LoginStep.email ? _email : _code,
            busy: _busy,
            isCode: _step == _LoginStep.code,
            onSubmit: _submit,
            onChangeEmail: () => setState(() {
              _challenge = null;
              _code.clear();
              _error = null;
              _step = _LoginStep.email;
            }),
          ),
        ],
        _LoginStep.approval => [
          const Icon(Icons.security, size: 48),
          const SizedBox(height: 24),
          if (_approval!.requiresIdentityReplacement) ...[
            Text(l10n.recovery_identity_warning),
            const SizedBox(height: 16),
          ],
          Text(l10n.recovery_sessions_warning),
          const SizedBox(height: 16),
          Text(l10n.recovery_history_warning),
          const SizedBox(height: 24),
          CheckboxListTile(
            key: const ValueKey('recovery-accept'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _accepted,
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _accepted = value ?? false;
                  }),
            title: Text(
              _approval!.requiresIdentityReplacement
                  ? l10n.recovery_identity_accept
                  : l10n.recovery_login_accept,
            ),
          ),
          FilledButton.icon(
            key: const ValueKey('recovery-complete'),
            onPressed: _busy || !_accepted ? null : _complete,
            icon: const Icon(Icons.login),
            label: Text(l10n.recovery_complete, textAlign: TextAlign.center),
          ),
        ],
        _LoginStep.pending => [
          Text(l10n.recovery_pending_description),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const ValueKey('recovery-resume'),
            onPressed: _busy ? null : () => _run(_resume),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.recovery_retry),
          ),
          TextButton(
            key: const ValueKey('recovery-restart'),
            onPressed: _busy ? null : _restart,
            child: Text(l10n.recovery_restart, textAlign: TextAlign.center),
          ),
        ],
      },
    );
  }
}
