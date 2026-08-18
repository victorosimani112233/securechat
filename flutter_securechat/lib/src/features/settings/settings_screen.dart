import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/app_container.dart';
import '../../l10n/l10n.dart';
import '../../settings/account_data_service.dart';
import '../../settings/settings_service.dart';
import '../../widgets/avatar.dart';
import '../../widgets/azure_backdrop.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final container = AppContainerScope.of(context);
    final service = container.settingsRuntime?.service;
    if (service == null) {
      return _body(context, container, null, null);
    }
    return StreamBuilder<AppSettingsState>(
      stream: service.states,
      initialData: service.current,
      builder: (context, snapshot) =>
          _body(context, container, service, snapshot.data ?? service.current),
    );
  }

  Widget _body(
    BuildContext context,
    AppContainer container,
    SettingsService? service,
    AppSettingsState? settings,
  ) {
    final session = container.session;
    final accountData = container.accountDataRuntime?.service;
    final l10n = context.l10n;
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !embedded,
          title: Text(l10n.settings_title),
        ),
        body: ListView(
          key: const ValueKey('settings-list'),
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              leading: _profileAvatar(
                settings?.profilePhotoPath,
                session.displayName ?? 'Elçim',
              ),
              title: Text(session.displayName ?? 'Elçim'),
              subtitle: Text(session.phoneNumber ?? ''),
              trailing: IconButton(
                tooltip: l10n.profile_photo_change,
                onPressed: service == null
                    ? null
                    : () => _showProfilePhotoSheet(
                        context,
                        container,
                        service,
                        settings?.profilePhotoPath,
                      ),
                icon: const Icon(Icons.camera_alt_outlined),
              ),
            ),
            const Divider(),
            _tile(
              Icons.palette_outlined,
              l10n.settings_chat_theme,
              _themeLabel(context, settings?.theme),
              onTap: service == null
                  ? null
                  : () => _showThemeDialog(context, service, settings!.theme),
            ),
            _tile(
              Icons.language_outlined,
              l10n.settings_language,
              _languageLabel(settings?.language),
              onTap: service == null
                  ? null
                  : () => _showLanguageDialog(
                      context,
                      service,
                      settings!.language,
                    ),
            ),
            _tile(
              Icons.notifications_outlined,
              l10n.settings_notification_sound,
              settings?.showNotificationContent == false
                  ? l10n.settings_content_hidden
                  : '${l10n.settings_content_visible} · '
                        '${_soundLabel(context, settings?.notificationSound)}',
              onTap: service == null
                  ? null
                  : () => _showNotificationSheet(context, service, settings!),
            ),
            _tile(
              Icons.lock_outline,
              l10n.settings_privacy,
              settings?.shareLastSeen == false
                  ? l10n.settings_last_seen_hidden
                  : l10n.settings_last_seen_shared,
              onTap: service == null
                  ? null
                  : () => _showPrivacySheet(context, service, settings!),
            ),
            if (settings != null && service != null) ...[
              SwitchListTile(
                secondary: const Icon(Icons.wallpaper_outlined),
                title: Text(l10n.settings_backdrop),
                subtitle: Text(l10n.settings_watermark_desc),
                value: settings.useDoodleBackground,
                onChanged: (value) =>
                    _run(context, () => service.setUseDoodleBackground(value)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.fullscreen_outlined),
                title: Text(l10n.settings_fullscreen),
                subtitle: Text(
                  Platform.isIOS
                      ? l10n.settings_fullscreen_ios_desc
                      : l10n.settings_fullscreen_android_desc,
                ),
                value: settings.fullscreenMode,
                onChanged: (value) =>
                    _run(context, () => service.setFullscreenMode(value)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.schedule_send_outlined),
                title: Text(l10n.settings_scheduled_messages),
                subtitle: Text(l10n.settings_scheduled_enabled_desc),
                value: settings.scheduledMessagesEnabled,
                onChanged: (value) => _run(
                  context,
                  () => service.setScheduledMessagesEnabled(value),
                ),
              ),
            ],
            _tile(
              Icons.download_outlined,
              l10n.settings_auto_download,
              l10n.settings_auto_download_desc,
              onTap: () => Navigator.pushNamed(context, '/auto-download'),
            ),
            _tile(
              Icons.phone_in_talk_outlined,
              l10n.settings_call_readiness,
              l10n.settings_call_readiness_desc,
              onTap: () => Navigator.pushNamed(context, '/call-readiness'),
            ),
            _tile(
              Icons.schedule_send_outlined,
              l10n.settings_manage_scheduled,
              l10n.settings_manage_scheduled_desc,
              onTap: () => Navigator.pushNamed(context, '/scheduled-messages'),
            ),
            _tile(
              Icons.send_to_mobile_outlined,
              l10n.settings_bulk_message,
              l10n.settings_bulk_message_desc,
              onTap: () => Navigator.pushNamed(context, '/bulk-message'),
            ),
            _tile(
              Icons.sd_storage_outlined,
              l10n.settings_storage_usage,
              l10n.settings_storage_desc,
              onTap: () => Navigator.pushNamed(context, '/storage-usage'),
            ),
            _tile(
              Icons.backup_outlined,
              l10n.settings_backup,
              l10n.settings_backup_desc,
              onTap: () => Navigator.pushNamed(context, '/backup'),
            ),
            _tile(
              Icons.article_outlined,
              l10n.settings_open_source_licenses,
              l10n.settings_open_source_licenses_desc,
              onTap: () =>
                  showLicensePage(context: context, applicationName: 'Elçim'),
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.delete_sweep_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                l10n.settings_delete_local_data,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle: Text(l10n.settings_local_data_desc),
              onTap: accountData == null
                  ? null
                  : () => _confirmLocalDelete(context, accountData),
            ),
            ListTile(
              leading: Icon(
                Icons.person_remove_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                l10n.settings_delete_account,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle: Text(l10n.settings_account_data_desc),
              onTap: accountData == null
                  ? null
                  : () => _confirmAccountDelete(context, accountData),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(l10n.settings_logout),
              onTap: () async {
                await container.pushRuntime?.coordinator.unregister();
                final auth = container.auth;
                if (auth != null) {
                  await auth.logout();
                } else {
                  await container.signaling.disconnect();
                  await session.clearAndPersist();
                }
                if (!context.mounted) return;
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/auth', (_) => false);
              },
            ),
          ],
        ),
      ),
    );
  }

  static Widget _tile(
    IconData icon,
    String title,
    String subtitle, {
    VoidCallback? onTap,
  }) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );

  static Widget _profileAvatar(String? path, String name) {
    if (path != null && File(path).existsSync()) {
      return CircleAvatar(backgroundImage: FileImage(File(path)));
    }
    return GeneratedAvatar(name: name);
  }

  static Future<void> _showThemeDialog(
    BuildContext context,
    SettingsService service,
    AppThemePreference selected,
  ) async {
    final value = await showDialog<AppThemePreference>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.settings_chat_theme),
        children: AppThemePreference.values
            .map(
              (value) => ListTile(
                leading: Icon(
                  value == selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(_themeLabel(context, value)),
                onTap: () => Navigator.pop(context, value),
              ),
            )
            .toList(growable: false),
      ),
    );
    if (value != null && context.mounted) {
      await _run(context, () => service.setTheme(value));
    }
  }

  static Future<void> _showLanguageDialog(
    BuildContext context,
    SettingsService service,
    AppLanguagePreference selected,
  ) async {
    final value = await showDialog<AppLanguagePreference>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.settings_language),
        children: AppLanguagePreference.values
            .map(
              (value) => ListTile(
                leading: Icon(
                  value == selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(_languageLabel(value)),
                onTap: () => Navigator.pop(context, value),
              ),
            )
            .toList(growable: false),
      ),
    );
    if (value != null && context.mounted) {
      await _run(context, () => service.setLanguage(value));
    }
  }

  static Future<void> _showNotificationSheet(
    BuildContext context,
    SettingsService service,
    AppSettingsState initial,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      var content = initial.showNotificationContent;
      var sound = initial.notificationSound;
      return StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: Text(context.l10n.settings_show_message_preview),
                subtitle: Text(context.l10n.settings_notification_preview_desc),
                value: content,
                onChanged: (value) async {
                  await _run(
                    context,
                    () => service.setShowNotificationContent(value),
                  );
                  setSheetState(() => content = value);
                },
              ),
              ListTile(
                leading: Icon(
                  sound == NotificationSoundPreference.defaultSound
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(context.l10n.settings_default_notification_sound),
                onTap: () async {
                  await _run(
                    context,
                    () => service.setNotificationSound(
                      NotificationSoundPreference.defaultSound,
                    ),
                  );
                  setSheetState(
                    () => sound = NotificationSoundPreference.defaultSound,
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  sound == NotificationSoundPreference.silent
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(context.l10n.settings_silent),
                onTap: () async {
                  await _run(
                    context,
                    () => service.setNotificationSound(
                      NotificationSoundPreference.silent,
                    ),
                  );
                  setSheetState(
                    () => sound = NotificationSoundPreference.silent,
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );

  static Future<void> _showPrivacySheet(
    BuildContext context,
    SettingsService service,
    AppSettingsState initial,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      var shareLastSeen = initial.shareLastSeen;
      return StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: Text(context.l10n.settings_share_last_seen),
                subtitle: Text(context.l10n.settings_presence_immediate_desc),
                value: shareLastSeen,
                onChanged: (value) async {
                  await _run(context, () => service.setShareLastSeen(value));
                  setSheetState(() => shareLastSeen = value);
                },
              ),
              ListTile(
                leading: const Icon(Icons.screenshot_monitor_outlined),
                title: Text(context.l10n.settings_screen_protection),
                subtitle: Text(context.l10n.settings_screen_protection_desc),
              ),
            ],
          ),
        ),
      );
    },
  );

  static Future<void> _showProfilePhotoSheet(
    BuildContext context,
    AppContainer container,
    SettingsService service,
    String? currentPath,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(context.l10n.camera),
            onTap: () async {
              Navigator.pop(sheetContext);
              final selected = await container.mediaRuntime?.mediaSelection
                  .takePhoto();
              if (selected != null && selected.isNotEmpty && context.mounted) {
                await _run(
                  context,
                  () => service.updateProfilePhoto(selected.first),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(context.l10n.gallery),
            onTap: () async {
              Navigator.pop(sheetContext);
              final selected = await container.mediaRuntime?.mediaSelection
                  .pickGallery();
              if (selected != null && selected.isNotEmpty && context.mounted) {
                await _run(
                  context,
                  () => service.updateProfilePhoto(selected.first),
                );
              }
            },
          ),
          if (currentPath != null)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(context.l10n.profile_photo_remove),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _run(context, service.removeProfilePhoto);
              },
            ),
        ],
      ),
    ),
  );

  static Future<void> _confirmLocalDelete(
    BuildContext context,
    AccountDataService accountData,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.delete_forever,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: Text(dialogContext.l10n.settings_delete_local_data),
        content: Text(
          '${dialogContext.l10n.settings_nuke_dialog_body}\n'
          '${dialogContext.l10n.settings_nuke_all_data_warning}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.settings_nuke_confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _runAndLeave(context, accountData.deleteLocalData);
  }

  static Future<void> _confirmAccountDelete(
    BuildContext context,
    AccountDataService accountData,
  ) async {
    final controller = TextEditingController();
    final confirmationToken = context.l10n.settings_nuke_type_placeholder;
    var deleting = false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (contentContext, setDialogState) => AlertDialog(
          icon: Icon(
            Icons.person_remove,
            color: Theme.of(contentContext).colorScheme.error,
          ),
          title: Text(contentContext.l10n.settings_delete_account),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: deleting
                    ? null
                    : () {
                        Navigator.pop(dialogContext, false);
                        Navigator.pushNamed(context, '/backup');
                      },
                icon: const Icon(Icons.backup_outlined),
                label: Text(contentContext.l10n.settings_nuke_backup_first),
              ),
              const SizedBox(height: 12),
              Text(
                '${contentContext.l10n.settings_delete_account_body}\n\n'
                '${contentContext.l10n.settings_nuke_type_to_confirm}',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                enabled: !deleting,
                autofocus: true,
                decoration: InputDecoration(hintText: confirmationToken),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: deleting
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: Text(contentContext.l10n.cancel),
            ),
            FilledButton(
              onPressed:
                  controller.text.trim().toUpperCase() ==
                          confirmationToken.toUpperCase() &&
                      !deleting
                  ? () {
                      setDialogState(() => deleting = true);
                      Navigator.pop(dialogContext, true);
                    }
                  : null,
              child: Text(contentContext.l10n.settings_delete_account),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (confirmed != true || !context.mounted) return;
    await _runAndLeave(context, accountData.deleteAccount);
  }

  static Future<void> _runAndLeave(
    BuildContext context,
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
      if (!context.mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (_) => false);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  static Future<void> _run(
    BuildContext context,
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  static String _themeLabel(BuildContext context, AppThemePreference? value) =>
      switch (value) {
        AppThemePreference.light => context.l10n.theme_light,
        AppThemePreference.dark => context.l10n.theme_dark,
        _ => context.l10n.theme_system,
      };

  static String _languageLabel(AppLanguagePreference? value) => switch (value) {
    AppLanguagePreference.tr => 'Türkçe',
    AppLanguagePreference.en => 'English',
    AppLanguagePreference.de => 'Deutsch',
    AppLanguagePreference.ar => 'العربية',
    _ => 'Sistem / System',
  };

  static String _soundLabel(
    BuildContext context,
    NotificationSoundPreference? value,
  ) => value == NotificationSoundPreference.silent
      ? context.l10n.settings_silent
      : context.l10n.settings_default_notification_sound;
}
