import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/account_recovery_coordinator.dart';
import '../../auth/registration_lock.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../widgets/azure_backdrop.dart';
import '../../widgets/azure_surface.dart';

/// Kayit kilidi PIN'ini acip kapatir.
class RegistrationLockScreen extends StatefulWidget {
  const RegistrationLockScreen({super.key, this.settings});

  /// Testler icin; verilmezse oturumdaki kurtarma koordinatoru kullanilir.
  final RegistrationLockSettings? settings;

  @override
  State<RegistrationLockScreen> createState() => _RegistrationLockScreenState();
}

class _RegistrationLockScreenState extends State<RegistrationLockScreen> {
  final _pin = TextEditingController();
  final _repeat = TextEditingController();
  bool? _enabled;
  bool _busy = false;
  bool _loadFailed = false;
  String? _error;
  bool _started = false;

  RegistrationLockSettings? get _settings {
    final explicit = widget.settings;
    if (explicit != null) return explicit;
    final recovery = AppContainerScope.of(context).auth?.recovery;
    return recovery is RegistrationLockSettings
        ? recovery as RegistrationLockSettings
        : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _pin.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = _settings;
    if (settings == null) {
      setState(() => _loadFailed = true);
      return;
    }
    try {
      final enabled = await settings.registrationLockEnabled();
      if (mounted) setState(() => _enabled = enabled);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _enable() async {
    final l10n = context.l10n;
    final pin = _pin.text;
    if (!validRegistrationLockPin(pin)) {
      setState(() => _error = l10n.registration_lock_pin_invalid);
      return;
    }
    if (pin != _repeat.text) {
      setState(() => _error = l10n.registration_lock_pin_mismatch);
      return;
    }
    await _change(
      () => _settings!.enableRegistrationLock(pin),
      enabled: true,
      done: l10n.registration_lock_enabled_done,
    );
  }

  Future<void> _disable() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.registration_lock_title),
        content: Text(l10n.registration_lock_disable_confirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('registration-lock-disable-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.registration_lock_disable),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _change(
      () => _settings!.disableRegistrationLock(),
      enabled: false,
      done: l10n.registration_lock_disabled_done,
    );
  }

  Future<void> _change(
    Future<void> Function() action, {
    required bool enabled,
    required String done,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.l10n.registration_lock_failed;
    try {
      await action();
      if (!mounted) return;
      _pin.clear();
      _repeat.clear();
      setState(() => _enabled = enabled);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (_) {
      if (mounted) setState(() => _error = failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final enabled = _enabled;
    final theme = Theme.of(context);
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.registration_lock_title)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AzureSurface(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            enabled == true
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              enabled == null
                                  ? l10n.registration_lock_title
                                  : enabled
                                  ? l10n.registration_lock_on
                                  : l10n.registration_lock_off,
                              key: const ValueKey('registration-lock-state'),
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(l10n.registration_lock_explain),
                      const SizedBox(height: 8),
                      Text(
                        l10n.registration_lock_forget_warning,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_loadFailed)
                Text(l10n.registration_lock_status_failed)
              else if (enabled == null)
                const Center(child: CircularProgressIndicator())
              else if (enabled)
                OutlinedButton.icon(
                  key: const ValueKey('registration-lock-disable'),
                  onPressed: _busy ? null : _disable,
                  icon: const Icon(Icons.lock_open_rounded),
                  label: Text(l10n.registration_lock_disable),
                )
              else ...[
                _pinField(
                  _pin,
                  l10n.registration_lock_pin_label,
                  const ValueKey('registration-lock-pin'),
                ),
                const SizedBox(height: 12),
                _pinField(
                  _repeat,
                  l10n.registration_lock_pin_repeat,
                  const ValueKey('registration-lock-pin-repeat'),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey('registration-lock-enable'),
                  onPressed: _busy ? null : _enable,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_rounded),
                  label: Text(l10n.registration_lock_enable),
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  key: const ValueKey('registration-lock-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _pinField(TextEditingController controller, String label, Key key) =>
      TextField(
        key: key,
        controller: controller,
        enabled: !_busy,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 12,
        autocorrect: false,
        enableSuggestions: false,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, counterText: ''),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      );
}
