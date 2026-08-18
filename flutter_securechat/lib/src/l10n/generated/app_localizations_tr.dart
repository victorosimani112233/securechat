// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get app_name => 'ELÇİM';

  @override
  String get group_info => 'Grup Bilgileri';

  @override
  String get group_settings => 'Grup Ayarları';

  @override
  String get add_member => 'Üye Ekle';

  @override
  String members_count(num arg1) {
    return 'Üyeler ($arg1)';
  }

  @override
  String get loading => 'Yükleniyor…';

  @override
  String get admin => 'Admin';

  @override
  String get you => 'Sen';

  @override
  String get remove_member => 'Üyeyi Çıkar';

  @override
  String get remove_from_group => 'Gruptan Çıkar';

  @override
  String get edit_group_name => 'Grup Adını Düzenle';

  @override
  String get group_name => 'Grup Adı';

  @override
  String get save => 'Kaydet';

  @override
  String get cancel => 'İptal';

  @override
  String get add_new_member => 'Yeni Üye Ekle';

  @override
  String get user_id => 'Kullanıcı ID';

  @override
  String get add => 'Ekle';

  @override
  String get remove_member_confirm => 'Üyeyi Çıkar';

  @override
  String remove_member_message(String arg1) {
    return '$arg1 kullanıcısını gruptan çıkarmak istediğinizden emin misiniz?';
  }

  @override
  String get remove => 'Çıkar';

  @override
  String get view_info => 'Bilgileri Gör';

  @override
  String get onboarding_subtitle => 'Güvenli mesajlaşma';

  @override
  String get onboarding_e2ee_notice =>
      'Mesajlarınız uçtan uca şifrelenir. Kimse okuyamaz.';

  @override
  String get register_title => 'Kayıt Ol';

  @override
  String get register_subtitle => 'Bilgilerinizi girerek başlayabilirsiniz.';

  @override
  String get register_name_label => 'Adınız';

  @override
  String get register_name_placeholder => 'Örneğin: Ahmet Yılmaz';

  @override
  String get register_country_code_label => 'Kod';

  @override
  String get register_phone_label => 'Telefon Numarası';

  @override
  String get register_phone_placeholder => '5XX XXX XX XX';

  @override
  String get register_start => 'Başla';

  @override
  String get contacts_permission_title => 'Rehber Erişimi Gerekli';

  @override
  String get contacts_permission_body =>
      'Rehber erişimi uygulamanın temel işlevleri için gereklidir. Kişilerinizi bulabilmek ve güvenli mesajlaşma başlatabilmek için lütfen rehber erişim iznini verin.';

  @override
  String get action_retry => 'Tekrar Dene';

  @override
  String get validation_name_empty => 'Adınızı giriniz';

  @override
  String validation_name_too_short(num arg1) {
    return 'En az $arg1 karakter';
  }

  @override
  String validation_name_too_long(num arg1) {
    return 'En fazla $arg1 karakter';
  }

  @override
  String get validation_name_invalid_chars =>
      'Yalnızca harf, boşluk, tire ve kesme işareti';

  @override
  String get validation_country_code_empty => 'Ülke kodu boş';

  @override
  String get validation_country_code_missing_plus => '+ ile başlamalı';

  @override
  String get validation_country_code_non_digit => 'Yalnızca rakam';

  @override
  String get validation_country_code_too_short => 'En az 1 hane';

  @override
  String get validation_country_code_too_long => 'En fazla 4 hane';

  @override
  String get validation_phone_empty => 'Telefon numaranızı giriniz';

  @override
  String get validation_phone_too_short => '10 hane gerekli';

  @override
  String get validation_phone_too_long => 'Sadece 10 hane';

  @override
  String get validation_phone_non_digit => 'Yalnızca rakam';

  @override
  String get otp_title => 'Doğrulama';

  @override
  String get otp_section_title => 'Doğrulama Kodu';

  @override
  String otp_description(String arg1) {
    return '$arg1 numarasına gönderilen\\n6 haneli doğrulama kodunu girin';
  }

  @override
  String get otp_incomplete_error => 'Lütfen 6 haneli kodu tamamen girin';

  @override
  String get otp_resend => 'Kodu Tekrar Gönder';

  @override
  String otp_resend_countdown(num arg1) {
    return 'Kodu tekrar gönder: ${arg1}s';
  }

  @override
  String get otp_verify => 'Doğrula';

  @override
  String get backup_prompt_title => 'Mevcut bir yedeğiniz var mı?';

  @override
  String get backup_prompt_body =>
      'Daha önce şifreli bir yedek oluşturduysanız, sohbetlerinizi geri yükleyebilirsiniz.';

  @override
  String get backup_prompt_yes => 'Evet, yedeği geri yükle';

  @override
  String get backup_prompt_no => 'Hayır, yeni başla';

  @override
  String get nav_back => 'Geri';

  @override
  String get email_otp_title => 'E-posta Doğrulama';

  @override
  String get email_otp_step_email => 'E-posta Adresiniz';

  @override
  String get email_otp_step_code => 'Doğrulama Kodu';

  @override
  String get email_otp_description_email =>
      'Hesabınızı doğrulamak için e-posta adresinizi girin. Kodu e-postanıza göndereceğiz.';

  @override
  String email_otp_description_code(String arg1) {
    return '$arg1 adresine gönderilen 6 haneli kodu girin.';
  }

  @override
  String get email_otp_email_label => 'E-posta';

  @override
  String get email_otp_code_label => '6 Haneli Kod';

  @override
  String get email_otp_send => 'Kod Gönder';

  @override
  String get email_otp_change_email => 'Farklı e-posta kullan';

  @override
  String get email_otp_dev_skip => 'Geliştirme Modu — Atla';

  @override
  String get email_otp_invalid_email => 'Geçerli bir e-posta girin';

  @override
  String get email_otp_sent => 'Kod e-postanıza gönderildi';

  @override
  String get email_otp_smtp_disabled =>
      'Sunucuda e-posta servisi yapılandırılmamış. Lütfen yöneticiyle iletişime geçin veya geliştirme modunda Atla butonunu kullanın.';

  @override
  String get email_otp_rate_limited =>
      'Çok fazla deneme. Lütfen birkaç dakika bekleyin.';

  @override
  String email_otp_send_error(String arg1) {
    return 'Kod gönderilemedi: $arg1';
  }

  @override
  String get email_otp_verify_failed => 'Kod hatalı veya süresi dolmuş';

  @override
  String get email_otp_incomplete => '6 haneli kodu eksiksiz girin';

  @override
  String get create_group_title => 'Yeni Grup';

  @override
  String get create_group_action => 'Oluştur';

  @override
  String create_group_selected_members(num arg1) {
    return 'Seçili Üyeler ($arg1)';
  }

  @override
  String get create_group_add_by_phone => 'Numara ile Ekle';

  @override
  String get create_group_user_not_found => 'Kullanıcı Bulunamadı';

  @override
  String get create_group_send_invite => 'Davet Gönder';

  @override
  String get create_group_close => 'Kapat';

  @override
  String get create_group_registered_contacts => 'Kayıtlı Kişiler';

  @override
  String get create_group_search_placeholder => 'Kişi ara…';

  @override
  String get invite_chooser_title => 'Davet gönder';

  @override
  String get cd_remove => 'Çıkar';

  @override
  String get cd_search => 'Ara';

  @override
  String get cd_clear => 'Temizle';

  @override
  String get cd_add => 'Ekle';

  @override
  String get cd_more => 'Daha Fazla';

  @override
  String get cd_connection_status => 'Bağlantı durumu';

  @override
  String get cd_new_chat_action => 'Sohbet başlat';

  @override
  String get cd_member_actions => 'Üye İşlemleri';

  @override
  String get network_error_title => 'Bağlantı Hatası';

  @override
  String get contacts_grant_permission => 'Rehber Erişimi Ver';

  @override
  String get contacts_invite_short => 'Davet Et';

  @override
  String get settings_title => 'Ayarlar';

  @override
  String get settings_nuke_dialog_title => 'Tüm Sohbetleri Sil';

  @override
  String get settings_nuke_dialog_body =>
      'Tüm sohbetler ve mesajlar kalıcı olarak silinecektir. Bu işlem geri alınamaz.';

  @override
  String get settings_nuke_confirm => 'Sil';

  @override
  String get settings_nuke_backup_first => 'Önce Yedekleme Yap';

  @override
  String get settings_nuke_all_data_warning =>
      'Tüm mesajlarınız, kişileriniz ve ayarlarınız silinecek.';

  @override
  String get settings_nuke_type_to_confirm =>
      'Onaylamak için \\\"SİL\\\" yazın:';

  @override
  String get settings_nuke_type_placeholder => 'SİL';

  @override
  String get settings_chat_theme => 'Sohbet Teması';

  @override
  String get settings_language => 'Dil';

  @override
  String get settings_backdrop => 'Arka Plan Deseni';

  @override
  String get settings_fullscreen => 'Tam Ekran Modu';

  @override
  String get settings_show_message_preview => 'Mesaj içeriğini göster';

  @override
  String get settings_notification_sound => 'Bildirim Sesi';

  @override
  String get settings_incoming_call_screen => 'Gelen arama ekranı';

  @override
  String get settings_missed_call => 'Aramaları kaçırma';

  @override
  String get settings_battery_optimization => 'Pil optimizasyonu';

  @override
  String get settings_scheduled_messages => 'Planlı Mesajlar';

  @override
  String get settings_manage_scheduled => 'Planlı Mesajları Yönet';

  @override
  String get settings_manage_scheduled_desc =>
      'Mevcut planlı mesajları görüntüle ve düzenle';

  @override
  String get settings_e2ee => 'Uçtan uca şifreleme';

  @override
  String get settings_e2ee_desc =>
      'Mesajlarınız Signal Protocol ile şifrelenir';

  @override
  String get settings_last_seen => 'Son görülme zamanı';

  @override
  String get settings_message_storage => 'Mesaj Depolama Politikası';

  @override
  String get settings_message_storage_desc =>
      'Mesajlar yalnızca bu cihazda saklanır';

  @override
  String get settings_backup => 'Yedekleme';

  @override
  String get settings_backup_desc =>
      'Sohbetleri şifreli olarak yedekle veya geri yükle';

  @override
  String get settings_storage_usage => 'Depolama Kullanımı';

  @override
  String get chat_info_note_label => 'Not';

  @override
  String get chat_info_search_placeholder => 'Mesajlarda ara…';

  @override
  String get conv_new_chat => 'Yeni Sohbet';

  @override
  String get conv_new_group => 'Yeni Grup';

  @override
  String get conv_bulk_message => 'Toplu Mesaj';

  @override
  String get conv_scheduled_messages => 'Planlı Mesajlar';

  @override
  String get conv_filter_all => 'Tümü';

  @override
  String get conv_filter_unread => 'Okunmamış';

  @override
  String get conv_filter_groups => 'Gruplar';

  @override
  String get conv_filter_favorites => 'Favoriler';

  @override
  String get conv_archive => 'Arşivle';

  @override
  String get conv_delete => 'Sil';

  @override
  String get conv_info => 'Bilgi';

  @override
  String get conv_delete_chat => 'Sohbeti Sil';

  @override
  String get group_view_profile => 'Profili Görüntüle';

  @override
  String get group_leave => 'Gruptan Çıkar';

  @override
  String get chat_search_in_chat => 'Sohbette Ara';

  @override
  String get chat_export => 'Sohbeti Dışa Aktar';

  @override
  String get action_close => 'Kapat';

  @override
  String get chat_custom_duration => 'Özel Süre';

  @override
  String get msg_action_reply => 'Yanıtla';

  @override
  String get msg_action_copy => 'Kopyala';

  @override
  String get msg_action_edit => 'Düzenle';

  @override
  String get msg_action_edit_history => 'Düzenleme Geçmişi';

  @override
  String get msg_action_info => 'Bilgi';

  @override
  String get msg_action_forward => 'İlet';

  @override
  String get msg_action_delete_for_me => 'Benden Sil';

  @override
  String get msg_delete_title => 'Mesajı sil';

  @override
  String get msg_delete_cancel => 'Vazgeç';

  @override
  String get msg_edit_title => 'Mesajı Düzenle';

  @override
  String get sched_title => 'Planlı Mesajlar';

  @override
  String get sched_delete_title => 'Planlı Mesajı Sil';

  @override
  String get sched_delete_body => 'Bu planlı mesaj kalıcı olarak silinecektir.';

  @override
  String get sched_tab_create => 'Oluştur';

  @override
  String get sched_tab_existing => 'Mevcut Planlananlar';

  @override
  String get sched_message_placeholder => 'Mesajınızı yazın…';

  @override
  String get sched_action_edit => 'Düzenle';

  @override
  String get sched_action_delete => 'Sil';

  @override
  String get sched_pick_time => 'Saat Seçin';

  @override
  String get sched_pick_day => 'Gün Seçimi';

  @override
  String get sched_pick_recipient => 'Alıcı Seç';

  @override
  String get action_ok => 'Tamam';

  @override
  String get conversations_title => 'Sohbetler';

  @override
  String get conversations_search => 'Sohbetlerde ara';

  @override
  String get nav_chats => 'Sohbet';

  @override
  String get nav_calls => 'Arama';

  @override
  String get nav_contacts => 'Rehber';

  @override
  String get chat_e2ee => 'Uçtan uca şifreli';

  @override
  String get archive_remove => 'Arşivden çıkar';

  @override
  String get profile_photo_change => 'Profil fotoğrafını değiştir';

  @override
  String get settings_watermark_desc => 'Elçim filigranını göster';

  @override
  String get settings_scheduled_enabled_desc =>
      'Arka plan gönderimlerini etkinleştir';

  @override
  String get settings_local_data_desc => 'Mesajlar, kişiler, medya ve ayarlar';

  @override
  String get settings_account_data_desc =>
      'Sunucu hesabı ve bu cihazdaki tüm veriler';

  @override
  String get settings_logout => 'Çıkış yap';

  @override
  String get settings_notification_preview_desc =>
      'Kilit ekranı bildirim önizlemesi';

  @override
  String get settings_default_notification_sound => 'Varsayılan bildirim sesi';

  @override
  String get settings_silent => 'Sessiz';

  @override
  String get settings_share_last_seen => 'Son görülmeyi paylaş';

  @override
  String get settings_screen_protection => 'Ekran koruması etkin';

  @override
  String get camera => 'Kamera';

  @override
  String get gallery => 'Galeri';

  @override
  String get profile_photo_remove => 'Fotoğrafı kaldır';

  @override
  String get settings_delete_local_data => 'Tüm yerel verileri sil';

  @override
  String get settings_delete_account => 'Hesabı kalıcı olarak sil';

  @override
  String get settings_delete_account_body =>
      'Sunucu hesabınız ve bu cihazdaki tüm veriler silinecek. Bu işlem geri alınamaz.';

  @override
  String get theme_system => 'Sistem';

  @override
  String get theme_light => 'Açık';

  @override
  String get theme_dark => 'Koyu';

  @override
  String get settings_content_hidden => 'Mesaj içeriği gizli';

  @override
  String get settings_content_visible => 'İçerik görünür';

  @override
  String get settings_privacy => 'Gizlilik';

  @override
  String get settings_last_seen_hidden => 'Son görülme paylaşılmıyor';

  @override
  String get settings_last_seen_shared => 'Son görülme paylaşılıyor';

  @override
  String get settings_fullscreen_ios_desc =>
      'iOS sistem alanlarını korur; kenardan kenara görünüm uygulanır';

  @override
  String get settings_fullscreen_android_desc =>
      'Android sistem çubuklarını uygulama içinde gizle';

  @override
  String get settings_auto_download => 'Otomatik indirme';

  @override
  String get settings_auto_download_desc => 'Wi-Fi ve mobil veri kuralları';

  @override
  String get settings_call_readiness => 'Arama hazırlığı';

  @override
  String get settings_call_readiness_desc =>
      'Pil, bildirim ve kilit ekranı izinleri';

  @override
  String get settings_bulk_message => 'Toplu mesaj';

  @override
  String get settings_bulk_message_desc =>
      'Birden fazla sohbete güvenli gönderim';

  @override
  String get settings_storage_desc => 'Medya ve sohbet kullanımı';

  @override
  String get settings_presence_immediate_desc =>
      'Değişiklik çevrimiçi durum protokolüne hemen iletilir';

  @override
  String get settings_screen_protection_desc =>
      'Android ekran yakalamayı engeller; iOS uygulama değiştiricide içeriği örter.';

  @override
  String get group_not_found => 'Grup bulunamadı.';

  @override
  String get group_admin_only => 'Sadece yöneticiler yazabilir';

  @override
  String get group_announcement_desc => 'Grubu duyuru kanalı olarak kullan';

  @override
  String get mute => 'Sessize al';

  @override
  String get chat_lock => 'Sohbet kilidi';

  @override
  String get chat_lock_desc => 'Cihaz doğrulamasıyla erişim';

  @override
  String get export_history => 'Dışa aktarma geçmişi';

  @override
  String get make_admin => 'Yönetici yap';

  @override
  String get no_contacts_to_add => 'Eklenebilecek kayıtlı kişi yok.';

  @override
  String get confirmation => 'Onay';

  @override
  String get confirm => 'Onayla';

  @override
  String get background_unavailable => 'Arka plan servisi kullanılamıyor.';

  @override
  String get storage_service_unavailable => 'Depolama hizmeti kullanılamıyor.';

  @override
  String get edit_mode => 'Düzenleme modu';

  @override
  String get repeat_once => 'Tek';

  @override
  String get repeat_daily => 'Her gün';

  @override
  String get repeat_custom => 'Özel';

  @override
  String get weekdays_short => 'Pzt,Sal,Çar,Per,Cum,Cmt,Paz';

  @override
  String get delivery_time => 'Gönderim saati';

  @override
  String get message_content => 'Mesaj içeriği';

  @override
  String get recipients => 'Alıcılar';

  @override
  String get recipient_required => 'En az bir kişi veya grup seçin';

  @override
  String get schedule => 'Planla';

  @override
  String get update => 'Güncelle';

  @override
  String get no_scheduled_messages => 'Henüz planlı mesaj yok.';

  @override
  String get schedule_saved => 'Planlı mesaj kaydedildi.';

  @override
  String get form_incomplete => 'Form eksik.';

  @override
  String get over_wifi => 'Wi-Fi üzerinden';

  @override
  String get over_cellular => 'Hücresel veri üzerinden';

  @override
  String get photos => 'Fotoğraflar';

  @override
  String get videos => 'Videolar';

  @override
  String get documents => 'Belgeler';

  @override
  String cellular_limit(num arg1) {
    return 'Hücresel üst sınırı: $arg1 MB';
  }

  @override
  String get no_chats_yet => 'Henüz sohbet yok';

  @override
  String storage_summary(num arg1, num arg2, String arg3) {
    return '$arg1 mesaj · $arg2 dosya · $arg3';
  }

  @override
  String get clear_media => 'Medyayı temizle';

  @override
  String clear_media_body(String arg1) {
    return '“$arg1” sohbetindeki medya ve dosya mesajları silinecek. Metin mesajları korunur.';
  }

  @override
  String get no_exports_yet => 'Henüz dışa aktarma yapılmadı';

  @override
  String message_count(num arg1) {
    return '$arg1 mesaj';
  }

  @override
  String get entire_chat => 'Tüm sohbet';

  @override
  String get admin_only_screen => 'Bu ekran sadece grup yöneticilerine açıktır';

  @override
  String get bulk_unavailable => 'Toplu gönderim kullanılamıyor.';

  @override
  String get select_all => 'Tümünü seç';

  @override
  String get group => 'Grup';

  @override
  String send_to_recipients(num arg1) {
    return '$arg1 alıcıya gönder';
  }

  @override
  String bulk_result(num arg1, num arg2) {
    return '$arg1 gönderildi, $arg2 başarısız.';
  }

  @override
  String get encrypted_backup => 'Şifreli Yedekleme';

  @override
  String get backup_explanation =>
      'Sohbetler, kişiler, çağrı kayıtları, planlı mesajlar ve uçtan uca şifreleme durumu parola ile korunan .elbk dosyasına kaydedilir. Oturum erişim anahtarları yedeğe eklenmez.';

  @override
  String get create_backup => 'Yeni yedek oluştur';

  @override
  String get restore_backup_file => 'Yedek dosyasını geri yükle';

  @override
  String get backups_on_device => 'Bu cihazdaki yedekler';

  @override
  String get no_local_backups => 'Henüz yerel yedek yok';

  @override
  String get backup_password => 'Yedek parolası';

  @override
  String get backup_unavailable => 'Yedekleme hizmeti kullanılamıyor.';

  @override
  String get save_encrypted_backup => 'Şifreli yedeği kaydet';

  @override
  String get backup_created => 'Yedek şifreli olarak oluşturuldu.';

  @override
  String backup_create_failed(String arg1) {
    return 'Yedek oluşturulamadı: $arg1';
  }

  @override
  String get backup_restored => 'Yedek geri yüklendi.';

  @override
  String wrong_password_attempts(num arg1) {
    return 'Parola yanlış. $arg1 deneme kaldı.';
  }

  @override
  String get backup_deleted_after_attempts =>
      'Beş yanlış deneme sonrası yedek dosyası silindi.';

  @override
  String get backup_delete_failed_after_attempts =>
      'Deneme sınırı doldu; dosya platform tarafından silinemedi.';

  @override
  String get password => 'Parola';

  @override
  String get password_min_length => 'En az 8 karakter';

  @override
  String get password_repeat => 'Parola tekrar';

  @override
  String get password_too_short => 'Parola en az 8 karakter olmalı.';

  @override
  String get password_mismatch => 'Parolalar eşleşmiyor.';

  @override
  String get restore => 'Geri yükle';

  @override
  String get no_call_history => 'Henüz arama kaydı yok.';

  @override
  String get video_call => 'Görüntülü ara';

  @override
  String get voice_call => 'Sesli ara';

  @override
  String get outgoing => 'Giden';

  @override
  String get incoming => 'Gelen';

  @override
  String get video => 'görüntülü';

  @override
  String get voice => 'sesli';

  @override
  String get missed => 'Cevapsız';

  @override
  String get rejected => 'Reddedildi';

  @override
  String get busy => 'Meşgul';

  @override
  String get failed => 'Başarısız';

  @override
  String call_description(String arg1, String arg2, String arg3) {
    return '$arg1 $arg2 arama$arg3';
  }

  @override
  String get recheck_status => 'Durumu yeniden denetle';

  @override
  String get calls_ready => 'Aramalar için hazırsınız';

  @override
  String get calls_readiness_missing =>
      'Aramaların gecikmemesi için eksikleri tamamlayın';

  @override
  String get battery_optimization_desc =>
      'Data-only push ve arka plan işlerinin Doze gecikmesini azaltır';

  @override
  String get fullscreen_call_notification => 'Tam ekran arama bildirimi';

  @override
  String get fullscreen_call_notification_desc =>
      'Android 14+ kilit ekranı arama görünümü';

  @override
  String get notification_permission => 'Bildirim izni';

  @override
  String get notification_permission_desc =>
      'Mesaj ve gelen arama bildirimleri';

  @override
  String get overlay_permission => 'Diğer uygulamaların üstünde göster';

  @override
  String get overlay_permission_desc => 'Android arka plan arama ekranı';

  @override
  String get ios_call_readiness_note =>
      'iOS’ta pil optimizasyonu, tam ekran intent ve overlay uygulama tarafından değiştirilemez. Gelen çağrı uyandırması APNs/CallKit ve sistem politikalarına bağlıdır.';

  @override
  String get secure_communication => 'Güvenli Haberleşme';

  @override
  String get onboarding_private_subtitle =>
      'Mesajlarınız yalnızca sizin aranızda';

  @override
  String get onboarding_private_body =>
      'Her mesaj cihazınızda şifrelenir; sunucu içeriği göremez.';

  @override
  String get onboarding_direct_call => 'Doğrudan arama';

  @override
  String get onboarding_webrtc_subtitle => 'Sesli ve görüntülü WebRTC';

  @override
  String get onboarding_webrtc_body =>
      'Bire bir aramalar doğrudan, büyük grup aramaları Janus SFU üzerinden çalışır.';

  @override
  String get onboarding_privacy_control => 'Tam gizlilik kontrolü';

  @override
  String get onboarding_you_decide => 'Siz karar verirsiniz';

  @override
  String get onboarding_privacy_body =>
      'Tek gösterim, süreli mesaj, ekran koruması ve grup export politikası.';

  @override
  String get skip => 'Atla';

  @override
  String get lets_start => 'Başlayalım';

  @override
  String get continue_action => 'Devam et';

  @override
  String get notifications => 'Bildirimler';

  @override
  String get notifications_permission_reason => 'Yeni mesaj ve aramalar için.';

  @override
  String get contacts_permission_reason =>
      'Kişileri yalnızca hash ile keşfetmek için.';

  @override
  String get microphone => 'Mikrofon';

  @override
  String get microphone_permission_reason =>
      'Sesli ve görüntülü aramalar için.';

  @override
  String get camera_permission_reason => 'Görüntülü aramalar için.';

  @override
  String get permissions_required => 'Birkaç izin gerekiyor';

  @override
  String get permissions_intro =>
      'İstediklerinizi şimdi verebilir, kalanlarını daha sonra ayarlardan açabilirsiniz.';

  @override
  String get grant_permission => 'İzin ver';

  @override
  String get chat_not_found => 'Sohbet bulunamadı.';

  @override
  String get contact_info => 'Kişi Bilgileri';

  @override
  String get starred_messages => 'Yıldızlı Mesajlar';

  @override
  String get media => 'Medya';

  @override
  String get disappearing_messages => 'Süreli mesajlar';

  @override
  String get contact_note => 'Kişiye not';

  @override
  String get tap_to_add_note => 'Not eklemek için dokun';

  @override
  String get no_records => 'Kayıt bulunamadı';

  @override
  String get add_contact_note => 'Kişiye not ekle';

  @override
  String get off => 'Kapalı';

  @override
  String hours(num arg1) {
    return '$arg1 saat';
  }

  @override
  String days(num arg1) {
    return '$arg1 gün';
  }

  @override
  String files_selected(num arg1) {
    return '$arg1 dosya seçildi';
  }

  @override
  String get add_caption => 'Açıklama ekle...';

  @override
  String get view_once => 'Tek gösterim';

  @override
  String get view_once_protected => 'Tek gösterimlik · ekran korumalı';

  @override
  String get share => 'Paylaş';

  @override
  String get tap_to_close_view_once =>
      'Kapatmak için dokunun · bir daha açılamaz';

  @override
  String file_open_failed(String arg1) {
    return 'Dosya açılamadı: $arg1';
  }

  @override
  String file_share_failed(String arg1) {
    return 'Dosya paylaşılamadı: $arg1';
  }

  @override
  String get file => 'Dosya';

  @override
  String get open_with_app => 'Uygulamayla aç';

  @override
  String get media_not_found => 'Medya dosyası bulunamadı';

  @override
  String get call_service_unavailable => 'Çağrı hizmeti başlatılamadı.';

  @override
  String get locked_chat => 'Kilitli Sohbet';

  @override
  String get disable_export => 'Dışa aktarmayı kapat';

  @override
  String get enable_export => 'Dışa aktarmayı aç';

  @override
  String get clear_chat => 'Sohbeti temizle';

  @override
  String get read_only_announcement =>
      'Bu grup sadece yöneticilerin yazabildiği bir duyuru kanalıdır.';

  @override
  String get no_matching_messages => 'Eşleşen mesaj bulunamadı';

  @override
  String get cancel_selection => 'Seçimi iptal et';

  @override
  String messages_selected(num arg1) {
    return '$arg1 mesaj seçildi';
  }

  @override
  String get forward_selected => 'Seçilenleri ilet';

  @override
  String get record_voice_message => 'Sesli mesaj kaydet';

  @override
  String get poll => 'Anket';

  @override
  String get add_reaction => 'Tepki ver';

  @override
  String get remove_star => 'Yıldızı kaldır';

  @override
  String get add_star => 'Yıldızla';

  @override
  String get unpin => 'Sabitlemeyi kaldır';

  @override
  String get pin => 'Sabitle';

  @override
  String get choose_reaction => 'Tepki seç';

  @override
  String get delete_for_everyone => 'Herkesten sil';

  @override
  String get clear_chat_confirm => 'Sohbet temizlensin mi?';

  @override
  String get clear_chat_body =>
      'Bu cihazdaki tüm mesajlar kalıcı olarak silinir.';

  @override
  String get voice_message => 'Sesli mesaj';

  @override
  String get recording_start_failed => 'Kayıt başlatılamadı';

  @override
  String get recording_paused => 'Kayıt duraklatıldı';

  @override
  String get recording_active => 'Kayıt sürüyor';

  @override
  String get send => 'Gönder';

  @override
  String get poll_load_failed => 'Anket yüklenemedi';

  @override
  String get single_choice => 'Tekli seçim';

  @override
  String get multiple_choice => 'Çoklu seçim';

  @override
  String total_votes(num arg1) {
    return 'Toplam $arg1 oy';
  }

  @override
  String get message_info => 'Mesaj Bilgisi';

  @override
  String get sent => 'Gönderildi';

  @override
  String get read => 'Okundu';

  @override
  String get delivered => 'İletildi';

  @override
  String get send_failed_no_plaintext =>
      'Gönderim başarısız. Plaintext fallback uygulanmadı.';

  @override
  String get forward_to_chat => 'Sohbete ilet';

  @override
  String get read_only_chat => 'Salt okunur sohbet';

  @override
  String participant_count(num arg1) {
    return '$arg1 katılımcı';
  }

  @override
  String get create_poll => 'Anket Oluştur';

  @override
  String get question => 'Soru';

  @override
  String option_number(num arg1) {
    return 'Seçenek $arg1';
  }

  @override
  String get add_option => 'Seçenek ekle';

  @override
  String get member_export_permission =>
      'Üyelerin kopyalama ve dışa aktarma yetkisi';

  @override
  String get admin_change_only => 'Yalnızca yönetici değiştirebilir';

  @override
  String remove_member_named(String arg1) {
    return '$arg1 gruptan çıkarılsın mı?';
  }

  @override
  String get leave_group_confirm => 'Bu gruptan ayrılmak istiyor musunuz?';

  @override
  String get archive => 'Arşiv';

  @override
  String get remove_favorite => 'Favorilerden çıkar';

  @override
  String get add_favorite => 'Favoriye ekle';

  @override
  String get mark_read => 'Okundu işaretle';

  @override
  String get mark_unread => 'Okunmadı işaretle';

  @override
  String delete_chat_body(String arg1) {
    return '$arg1 sohbeti ve bu cihazdaki mesajları kalıcı olarak silinsin mi?';
  }

  @override
  String get reject => 'Reddet';

  @override
  String get answer => 'Cevapla';

  @override
  String get unmute => 'Sesi aç';

  @override
  String get speaker => 'Hoparlör';

  @override
  String get flip_camera => 'Çevir';

  @override
  String get end_call => 'Bitir';

  @override
  String get call_preparing => 'Arama hazırlanıyor…';

  @override
  String get incoming_call => 'Gelen arama';

  @override
  String get ringing => 'Çalıyor…';

  @override
  String get connecting => 'Bağlanıyor…';

  @override
  String get reconnecting => 'Yeniden bağlanıyor…';

  @override
  String get weak_connection_disable_video =>
      'Bağlantı zayıf — videoyu kapatıp sesli devam et';

  @override
  String get call_ended => 'Arama sona erdi';

  @override
  String get call_rejected => 'Arama reddedildi';

  @override
  String get connection_failed => 'Bağlantı kurulamadı';

  @override
  String get voice_service_unavailable => 'Sesli mesaj hizmeti başlatılamadı.';

  @override
  String get voice_encrypting => 'Sesli mesaj şifrelenip gönderiliyor…';

  @override
  String get voice_sent => 'Sesli mesaj gönderildi.';

  @override
  String voice_send_failed(String arg1) {
    return 'Sesli mesaj gönderilemedi: $arg1';
  }

  @override
  String get file_transfer_unavailable =>
      'Dosya aktarım hizmeti başlatılamadı.';

  @override
  String media_pick_failed(String arg1) {
    return 'Medya seçilemedi: $arg1';
  }

  @override
  String get media_encrypting => 'Medya şifrelenip gönderiliyor…';

  @override
  String media_send_failed(String arg1) {
    return 'Medya gönderilemedi: $arg1';
  }

  @override
  String media_sent(num arg1) {
    return '$arg1 medya şifreli olarak gönderildi.';
  }

  @override
  String media_failed(num arg1, String arg2) {
    return '$arg1 medya gönderilemedi: $arg2';
  }

  @override
  String get poll_unavailable => 'Anket hizmeti kullanılamıyor.';

  @override
  String get poll_sent => 'Anket gönderildi.';

  @override
  String get poll_send_failed => 'Anket gönderilemedi.';

  @override
  String get vote_send_failed => 'Oy güvenli olarak gönderilemedi.';

  @override
  String get pin_failed => 'Sabitleme yetkisi yok veya sinyal gönderilemedi.';

  @override
  String get forward_service_unavailable =>
      'Mesaj iletme hizmeti başlatılamadı.';

  @override
  String forward_encrypting(num arg1, String arg2) {
    return '$arg1 mesaj $arg2 için yeniden şifreleniyor…';
  }

  @override
  String forward_encryption_result(num arg1, num arg2) {
    return '$arg1 mesaj iletildi; $arg2 mesaj şifrelenemedi ve gönderilmedi.';
  }

  @override
  String forward_sent(num arg1) {
    return '$arg1 mesaj iletildi.';
  }

  @override
  String forward_partial(num arg1, num arg2) {
    return '$arg1 mesaj iletildi; $arg2 mesaj gönderilemedi.';
  }

  @override
  String get reaction_failed => 'Tepki gönderilemedi.';

  @override
  String get edit_failed => 'Mesaj düzenlenemedi.';

  @override
  String get delete_signal_failed => 'Silme bildirimi gönderilemedi.';

  @override
  String get export_unavailable => 'Dışa aktarma kullanılamıyor.';

  @override
  String get chat_exported => 'Sohbet dışa aktarıldı.';

  @override
  String get group_policy_unavailable => 'Grup ilkesi kullanılamıyor.';

  @override
  String get export_disabled => 'Dışa aktarma kapatıldı.';

  @override
  String get export_enabled => 'Dışa aktarma açıldı.';

  @override
  String get chat_unmuted => 'Sohbet sesi açıldı.';

  @override
  String get chat_muted => 'Sohbet sessize alındı.';

  @override
  String get invalid_voice_recording => 'Geçerli bir ses kaydı oluşturulamadı.';

  @override
  String get audio_not_found => 'Ses dosyası bulunamadı';

  @override
  String get audio_play_failed => 'Ses kaydı oynatılamadı';

  @override
  String get opened => 'Açıldı';

  @override
  String get view_once_photo => 'Tek gösterimlik fotoğraf';

  @override
  String get media_no_longer_available => 'Bu medya artık açılamaz';

  @override
  String get tap_to_open => 'Açmak için dokunun';

  @override
  String get attachment => 'Ek ekle';

  @override
  String get dialpad => 'Tuş takımını aç';

  @override
  String get remove_option => 'Seçeneği kaldır';

  @override
  String get auth_unavailable => 'Kimlik doğrulama hizmeti yapılandırılmamış.';

  @override
  String rate_limit_seconds(num arg1) {
    return 'Çok fazla istek. $arg1 saniye bekleyin.';
  }

  @override
  String get chat_cleared => 'Sohbet temizlendi.';

  @override
  String get no_registered_contacts =>
      'Kayıtlı kişi bulunamadı. Rehber izni verip yenilemeyi deneyin.';

  @override
  String get contacts_secure_directory_unavailable_title =>
      'Güvenli rehber hizmeti kullanılamıyor';

  @override
  String get contacts_secure_directory_unavailable_body =>
      'Sunucu özel rehber protokolünü henüz sunmuyor. Daha az güvenli bir yönteme geçilmedi; önceden doğrulanan kişiler yalnızca cihazında korunuyor.';

  @override
  String get contacts_secure_directory_server_upgrade_title =>
      'Sunucu güncellemesi gerekiyor';

  @override
  String get contacts_secure_directory_server_upgrade_body =>
      'Bağlantı kuruldu ancak sunucuda güvenli rehber modülü etkin değil. Rehber verilerin gönderilmedi; sunucu güncellendikten sonra yeniden deneyebilirsin.';

  @override
  String get contacts_secure_directory_verification_failed_body =>
      'Güvenli rehber doğrulaması tamamlanamadı. Gizliliğini korumak için eski keşif yöntemine geçilmedi.';

  @override
  String get contacts_sync_failed_body =>
      'Rehber eşitlemesi tamamlanamadı. Cihazındaki mevcut güvenli eşleşmeler değiştirilmedi; tekrar deneyebilirsin.';

  @override
  String get clear_search => 'Aramayı temizle';

  @override
  String get conversations_archived_title => 'Arşivlenmiş Sohbetler';

  @override
  String get conversations_no_results => 'Sonuç bulunamadı';

  @override
  String get conversations_no_results_body =>
      'Farklı bir arama terimi veya filtre deneyin.';

  @override
  String get conversations_empty_body =>
      'Yeni bir güvenli sohbet başlatmak için sağ üstteki menüyü kullanın.';

  @override
  String get conversation_typing => 'yazıyor…';

  @override
  String get conversation_locked_preview => 'Bu sohbet gizlendi';

  @override
  String get conversations_messages_section => 'Mesajlarda';

  @override
  String get signaling_disconnected => 'Sunucu bağlantısı kesildi';

  @override
  String get connected => 'Bağlandı';

  @override
  String get chat_online => 'çevrimiçi';

  @override
  String chat_last_seen(String time) {
    return 'son görülme $time';
  }

  @override
  String get chat_encryption_notice => 'Mesajlar uçtan uca şifrelenmiştir.';

  @override
  String get chat_today => 'Bugün';

  @override
  String get chat_yesterday => 'Dün';

  @override
  String get chat_pinned_message => 'Sabitlenmiş Mesaj';

  @override
  String get chat_admins_only => 'Sadece yöneticiler mesaj gönderebilir';

  @override
  String get chat_message_hint => 'Mesaj yazın…';

  @override
  String get chat_scroll_bottom => 'En yeni mesaja git';

  @override
  String get chat_you => 'Sen';

  @override
  String get chat_edited => 'düzenlendi';

  @override
  String get chat_attachment_options => 'Ek seçenekleri';

  @override
  String get chat_empty_secure => 'Bu güvenli sohbette henüz mesaj yok.';

  @override
  String get chat_previous_result => 'Önceki sonuç';

  @override
  String get chat_next_result => 'Sonraki sonuç';

  @override
  String get sending => 'Gönderiliyor';

  @override
  String get return_to_call => 'Aramaya dön';

  @override
  String get settings_open_source_licenses => 'Açık kaynak lisansları';

  @override
  String get settings_open_source_licenses_desc =>
      'Bu derlemeye dahil edilen yazılım lisanslarını inceleyin.';
}
