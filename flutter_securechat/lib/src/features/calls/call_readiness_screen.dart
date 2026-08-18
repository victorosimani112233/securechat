import 'package:flutter/material.dart';

import '../../calls/call_readiness_service.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../widgets/azure_backdrop.dart';

class CallReadinessScreen extends StatefulWidget {
  const CallReadinessScreen({super.key});

  @override
  State<CallReadinessScreen> createState() => _CallReadinessScreenState();
}

class _CallReadinessScreenState extends State<CallReadinessScreen>
    with WidgetsBindingObserver {
  CallReadinessState? _state;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(title: Text(context.l10n.settings_missed_call)),
        body: state == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : FilledButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: Text(context.l10n.recheck_status),
                      ),
              )
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Icon(
                      state.allGranted
                          ? Icons.phone_in_talk
                          : Icons.phone_android,
                      size: 64,
                      color: state.allGranted
                          ? Colors.green
                          : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      state.allGranted
                          ? context.l10n.calls_ready
                          : context.l10n.calls_readiness_missing,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 24),
                    _row(
                      'battery',
                      Icons.battery_full,
                      context.l10n.settings_battery_optimization,
                      context.l10n.battery_optimization_desc,
                      state.battery,
                    ),
                    _row(
                      'fullScreenIntent',
                      Icons.fullscreen,
                      context.l10n.fullscreen_call_notification,
                      context.l10n.fullscreen_call_notification_desc,
                      state.fullScreenIntent,
                    ),
                    _row(
                      'notification',
                      Icons.notifications_outlined,
                      context.l10n.notification_permission,
                      context.l10n.notification_permission_desc,
                      state.notification,
                    ),
                    _row(
                      'overlay',
                      Icons.picture_in_picture_alt_outlined,
                      context.l10n.overlay_permission,
                      context.l10n.overlay_permission_desc,
                      state.overlay,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.l10n.ios_call_readiness_note,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _row(
    String kind,
    IconData icon,
    String title,
    String description,
    ReadinessStatus status,
  ) {
    if (status == ReadinessStatus.notApplicable) return const SizedBox.shrink();
    final granted = status == ReadinessStatus.granted;
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(description),
        trailing: Icon(
          granted ? Icons.check_circle : Icons.arrow_forward,
          color: granted ? Colors.green : Theme.of(context).colorScheme.error,
        ),
        onTap: granted ? null : () => _open(kind),
      ),
    );
  }

  Future<void> _refresh() async {
    try {
      final state = await AppContainerScope.of(
        context,
      ).callReadinessRuntime.service.refresh();
      if (!mounted) return;
      setState(() {
        _state = state;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _open(String kind) async {
    await AppContainerScope.of(
      context,
    ).callReadinessRuntime.service.openSetting(kind);
  }
}
