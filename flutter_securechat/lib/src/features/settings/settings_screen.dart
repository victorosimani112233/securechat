import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/app_container.dart';
import '../../l10n/l10n.dart';
import '../../widgets/text_controller_scope.dart';
import '../../settings/account_data_service.dart';
import '../../settings/settings_service.dart';
import '../../widgets/avatar.dart';
import '../../widgets/azure_backdrop.dart';
import '../../widgets/azure_options.dart';
import '../../widgets/notification_sound_picker.dart';
import '../../widgets/azure_surface.dart';
import '../auth/recovery_enrollment_screen.dart';

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
          // Satirlar kayan desenin uzerinde ciplak duruyordu. `Divider`
          // sinirlari artik opak bolumlere donusuyor: hem okunabilir hem
          // hangi ayarin nereye ait oldugu belli.
          children: azureSections(<Widget>[
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
              _soundLabel(context, settings?.notificationSound),
              onTap: service == null
                  ? null
                  : () => _showNotificationSheet(context, service, settings!),
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
            ],
            const Divider(),
            _tile(
              Icons.lock_outline,
              l10n.settings_privacy,
              _privacySummary(context, settings),
              onTap: service == null
                  ? null
                  : () => _showPrivacySheet(context, service, settings!),
            ),
            _tile(
              Icons.alternate_email,
              l10n.recovery_email_title,
              l10n.recovery_email_settings,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RecoveryEnrollmentScreen(),
                ),
              ),
            ),
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
            const Divider(),
            _tile(
              Icons.schedule_send_outlined,
              l10n.settings_manage_scheduled,
              l10n.settings_manage_scheduled_desc,
              onTap: () => Navigator.pushNamed(context, '/scheduled-messages'),
            ),
            const Divider(),
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
              Icons.info_outline,
              l10n.settings_about,
              l10n.settings_about_desc,
              onTap: () => Navigator.pushNamed(context, '/about'),
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
          ]),
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
        contentPadding: const EdgeInsets.only(bottom: 12),
        children: [
          for (final option in AppThemePreference.values)
            AzureOptionTile(
              selected: option == selected,
              icon: switch (option) {
                AppThemePreference.system => Icons.brightness_auto_outlined,
                AppThemePreference.light => Icons.light_mode_outlined,
                AppThemePreference.dark => Icons.dark_mode_outlined,
              },
              title: _themeLabel(context, option),
              onTap: () => Navigator.pop(context, option),
            ),
        ],
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
        contentPadding: const EdgeInsets.only(bottom: 12),
        children: [
          for (final option in AppLanguagePreference.values)
            AzureOptionTile(
              selected: option == selected,
              icon: Icons.translate_outlined,
              title: _languageLabel(option),
              onTap: () => Navigator.pop(context, option),
            ),
        ],
      ),
    );
    if (value != null && context.mounted) {
      await _run(context, () => service.setLanguage(value));
    }
  }

  /// Bildirim SESI — yalniz ses secimi, her secenek dinlenebilir.
  ///
  /// "Mesaj icerigini goster" buradaydi; oraya ait degil. O ayar kilit
  /// ekraninda ne gorunecegini belirliyor, yani bir GIZLILIK karari.
  /// Gizlilik sayfasina tasindi.
  ///
  /// Sayfa kendi kopyasini tutmuyor, `service.states` akisini dinliyor.
  /// Yerel kopya iki soruna yol aciyordu: deger ancak kaydetme bittikten
  /// sonra degisiyordu (dokunusa tepkisiz goruntu), ve kaydetme BASARISIZ
  /// olsa bile ekran yeni degeri gosteriyordu — yani yalan soyluyordu.
  static Future<void> _showNotificationSheet(
    BuildContext context,
    SettingsService service,
    AppSettingsState initial,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StreamBuilder<AppSettingsState>(
      stream: service.states,
      initialData: initial,
      builder: (context, snapshot) => NotificationSoundPicker(
        selected: (snapshot.data ?? initial).notificationSound,
        onSelected: (value) {
          if (value == null) return;
          _run(context, () => service.setNotificationSound(value));
        },
        onSystemSettings: service.openSystemSoundSettings,
      ),
    ),
  );

  /// Gizlilik — karsi tarafin ve kilit ekraninin ne gorecegi.
  ///
  /// Bildirim onizlemesi de burada: kilit ekraninda mesaj icerigi gorunup
  /// gorunmeyecegi bir gizlilik karari, ses tercihiyle ilgisi yok.
  static Future<void> _showPrivacySheet(
    BuildContext context,
    SettingsService service,
    AppSettingsState initial,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    builder: (sheetContext) => SafeArea(
      child: StreamBuilder<AppSettingsState>(
        stream: service.states,
        initialData: initial,
        builder: (context, snapshot) {
          final settings = snapshot.data ?? initial;
          return ListView(
            shrinkWrap: true,
            children: [
              _SheetHeading(context.l10n.settings_privacy),
              SwitchListTile(
                key: const ValueKey('settings-share-phone-number'),
                secondary: const Icon(Icons.phone_outlined),
                title: Text(context.l10n.settings_share_phone_number),
                value: settings.sharePhoneNumber,
                onChanged: (value) =>
                    _run(context, () => service.setSharePhoneNumber(value)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  context.l10n.settings_share_phone_number_desc,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.visibility_outlined),
                title: Text(context.l10n.settings_show_message_preview),
                subtitle: Text(context.l10n.settings_notification_preview_desc),
                value: settings.showNotificationContent,
                onChanged: (value) => _run(
                  context,
                  () => service.setShowNotificationContent(value),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.schedule_outlined),
                title: Text(context.l10n.settings_share_last_seen),
                subtitle: Text(context.l10n.settings_presence_immediate_desc),
                value: settings.shareLastSeen,
                onChanged: (value) =>
                    _run(context, () => service.setShareLastSeen(value)),
              ),
              ListTile(
                leading: const Icon(Icons.screenshot_monitor_outlined),
                title: Text(context.l10n.settings_screen_protection),
                subtitle: Text(context.l10n.settings_screen_protection_desc),
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    ),
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
    final confirmationToken = context.l10n.settings_nuke_type_placeholder;
    var deleting = false;
    // Controller dialog'un yasam dongusune ait (bkz TextControllerScope).
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => TextControllerScope(
        builder: (dialogContext, controller) => StatefulBuilder(
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
      ),
    );
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

  /// Gizlilik satirinin ozeti: iki ayarin da durumu tek satirda.
  ///
  /// Onceden yalniz son gorulme yaziyordu; bildirim onizlemesi bu sayfaya
  /// tasindigi icin o da ozete girdi.
  static String _privacySummary(
    BuildContext context,
    AppSettingsState? settings,
  ) {
    final l10n = context.l10n;
    final lastSeen = settings?.shareLastSeen == false
        ? l10n.settings_last_seen_hidden
        : l10n.settings_last_seen_shared;
    final preview = settings?.showNotificationContent == false
        ? l10n.settings_content_hidden
        : l10n.settings_content_visible;
    return '$lastSeen · $preview';
  }

  static String _soundLabel(
    BuildContext context,
    NotificationSoundPreference? value,
  ) => soundName(context, value ?? NotificationSoundPreference.system);
}

/// Alt sayfalarin basligi.
///
/// Sayfalarin hicbirinde baslik yoktu; acilan panelin neyi degistirdigi
/// yalniz satirlardan anlasiliyordu.
class _SheetHeading extends StatelessWidget {
  const _SheetHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 12),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}
