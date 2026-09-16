import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../l10n/l10n.dart';
import '../settings/settings_service.dart';
import 'azure_options.dart';

/// Bildirim sesi secme sayfasi.
///
/// Iki yerden aciliyor: uygulama genelindeki ayar ve sohbete ozel ses.
/// Ikisinde de ayni liste, ayni onizleme ve ayni gorunum olmali; ayri ayri
/// yazilsalardi zamanla ayrisirlardi.
///
/// `allowInherit` sohbete ozel secimde true veriliyor: orada "uygulama
/// ayarini kullan" diye ek bir secenek gerekiyor, uygulama genelinde ise
/// boyle bir sey yok.
class NotificationSoundPicker extends StatefulWidget {
  const NotificationSoundPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    this.allowInherit = false,
    this.onSystemSettings,
  });

  /// Secili ses; `allowInherit` ile birlikte null "uygulama ayarini kullan".
  final NotificationSoundPreference? selected;
  final ValueChanged<NotificationSoundPreference?> onSelected;
  final bool allowInherit;

  /// Sistem ses secicisini acan geri cagri; verilmezse o satir gosterilmez.
  final VoidCallback? onSystemSettings;

  @override
  State<NotificationSoundPicker> createState() =>
      _NotificationSoundPickerState();
}

class _NotificationSoundPickerState extends State<NotificationSoundPicker> {
  final AudioPlayer _player = AudioPlayer();

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  /// Secilen sesi calar. Onceki calma kesilir: art arda secim yapildiginda
  /// sesler ust uste binmemeli.
  Future<void> _preview(NotificationSoundPreference option) async {
    final asset = option.asset;
    if (asset == null) return;
    try {
      await _player.stop();
      await _player.setAsset('assets/sounds/$asset.wav');
      await _player.play();
    } catch (_) {
      // Onizleme calmazsa secim yine de yapilabilmeli; bu bir kolaylik,
      // ayarin kendisi degil.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      // Sayfa ekranin tamamini kaplamasin: ustte kalan bosluga dokunarak
      // kapatmak, kaydirma hareketinin listeye gittigi durumda tek yol.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AzureSheetHeading(
              l10n.settings_notification_sound,
              subtitle: l10n.sound_preview,
              onClose: () => Navigator.maybePop(context),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  if (widget.allowInherit)
                    AzureOptionTile(
                      selected: widget.selected == null,
                      icon: Icons.settings_outlined,
                      title: l10n.sound_inherit,
                      onTap: () => widget.onSelected(null),
                    ),
                  for (final option in NotificationSoundPreference.values)
                    AzureOptionTile(
                      selected: option == widget.selected,
                      icon: soundIcon(option),
                      title: soundName(context, option),
                      trailing: option.asset == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.play_circle_outline),
                              tooltip: l10n.sound_preview,
                              onPressed: () => _preview(option),
                            ),
                      onTap: () {
                        _preview(option);
                        widget.onSelected(option);
                      },
                    ),
                ],
              ),
            ),
            if (widget.onSystemSettings case final VoidCallback open) ...[
              const Divider(height: 24),
              // Paketlenmis sesler sinirli bir liste. Cihazdaki HER sesi
              // secebilmenin tek yolu sistemin kendi secicisi — Android 8'den
              // beri kanalin sesi zaten yalnizca oradan degistirilebiliyor.
              ListTile(
                leading: const Icon(Icons.library_music_outlined),
                title: Text(l10n.sound_system_picker),
                subtitle: Text(l10n.sound_system_picker_desc),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: open,
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Bir ses secenegi icin gorunen ad.
///
/// Ayarlar listesindeki ozet satiri, sohbet bilgisi satiri ve secim sayfasi
/// ayni adi kullanmali; ayri yazilirlarsa zamanla ayrisiyorlar.
String soundName(BuildContext context, NotificationSoundPreference option) {
  final l10n = context.l10n;
  return switch (option) {
    NotificationSoundPreference.silent => l10n.settings_silent,
    NotificationSoundPreference.system => l10n.sound_system,
    NotificationSoundPreference.chime => l10n.sound_chime,
    NotificationSoundPreference.bell => l10n.sound_bell,
    NotificationSoundPreference.tap => l10n.sound_tap,
    NotificationSoundPreference.warm => l10n.sound_warm,
    NotificationSoundPreference.soft => l10n.sound_soft,
    NotificationSoundPreference.melody => l10n.sound_melody,
    NotificationSoundPreference.flow => l10n.sound_flow,
    NotificationSoundPreference.sparkle => l10n.sound_sparkle,
    NotificationSoundPreference.beep => l10n.sound_beep,
    NotificationSoundPreference.ding => l10n.sound_ding,
  };
}

/// Her sesin karakterine yakin bir ikon.
///
/// Uzun bir listede yalniz adlar birbirine benziyor; ikon satirlari
/// birbirinden ayirmanin en ucuz yolu.
IconData soundIcon(NotificationSoundPreference option) => switch (option) {
  NotificationSoundPreference.silent => Icons.notifications_off_outlined,
  NotificationSoundPreference.system => Icons.smartphone_outlined,
  NotificationSoundPreference.chime => Icons.notifications_active_outlined,
  NotificationSoundPreference.bell => Icons.doorbell_outlined,
  NotificationSoundPreference.tap => Icons.touch_app_outlined,
  NotificationSoundPreference.warm => Icons.wb_twilight_outlined,
  NotificationSoundPreference.soft => Icons.cloud_outlined,
  NotificationSoundPreference.melody => Icons.music_note_outlined,
  NotificationSoundPreference.flow => Icons.waves_outlined,
  NotificationSoundPreference.sparkle => Icons.auto_awesome_outlined,
  NotificationSoundPreference.beep => Icons.graphic_eq_outlined,
  NotificationSoundPreference.ding => Icons.notifications_none_outlined,
};
