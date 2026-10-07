// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get hide_keyboard => 'Tastatur ausblenden';

  @override
  String get calls_filter_video => 'Video';

  @override
  String get calls_filter_empty => 'Keine Anrufe für diesen Filter';

  @override
  String get group_added_notification => 'Du wurdest einer Gruppe hinzugefügt.';

  @override
  String get group_create_failed =>
      'Die Gruppe konnte nicht erstellt werden. Prüfe deine Verbindung und versuche es erneut.';

  @override
  String get group_call_active_voice => 'Laufender Sprachanruf';

  @override
  String get group_call_active_video => 'Laufender Videoanruf';

  @override
  String get group_call_join => 'Beitreten';

  @override
  String get group_call_return => 'Zurück zum Anruf';

  @override
  String get group_call_join_failed =>
      'Der Anruf ist beendet oder der Beitritt ist fehlgeschlagen.';

  @override
  String get identity_review_title => 'Identität prüfen';

  @override
  String get identity_review_warning =>
      'Eine geänderte Identität kann auf eine Kontowiederherstellung, ein neues Gerät oder einen Angriff hinweisen. Vergleiche vor der Bestätigung den aktuellen SHA-256-Fingerabdruck persönlich oder über einen vertrauenswürdigen, unabhängigen Kanal mit dieser Person. Verlasse dich nicht auf eine Nachricht in diesem Chat. Die andere Person kann deinen Fingerabdruck ebenfalls auf ihrem Gerät vergleichen.';

  @override
  String get identity_review_previous =>
      'Bisher vertrauenswürdiger Fingerabdruck (SHA-256)';

  @override
  String get identity_review_current =>
      'Aktueller Fingerabdruck des Kontakts (SHA-256)';

  @override
  String get identity_review_local => 'Dein Fingerabdruck (SHA-256)';

  @override
  String get identity_review_no_previous =>
      'Keine bisher vertrauenswürdige Identität';

  @override
  String get identity_review_unchanged =>
      'Die aktuelle Identität stimmt mit der gespeicherten Identität überein.';

  @override
  String get identity_review_confirm =>
      'Ich habe diesen Fingerabdruck über einen vertrauenswürdigen, unabhängigen Kanal verglichen.';

  @override
  String get identity_review_approve => 'Diese Identität bestätigen';

  @override
  String get identity_review_approved =>
      'Identität bestätigt. Du kannst zum Gespräch zurückkehren.';

  @override
  String get identity_review_stale =>
      'Die Identität hat sich während der Prüfung geändert. Lade sie neu und prüfe sie erneut.';

  @override
  String get identity_review_failed =>
      'Die Identität konnte nicht geprüft werden. Es wurde keine neue Identität bestätigt.';

  @override
  String get identity_review_retry => 'Identität neu laden';

  @override
  String get recovery_error_expired =>
      'Diese Verifizierung ist abgelaufen. Fordere einen neuen Code an oder starte eine neue Verifizierung.';

  @override
  String get recovery_error_trusted_device =>
      'Zum Einrichten einer Wiederherstellungs-E-Mail ist dein vertrauenswürdiges, angemeldetes Gerät erforderlich. Prüfe vor einem erneuten Versuch deine Sitzung.';

  @override
  String get recovery_error_signed_in =>
      'Dieses Gerät ist bereits angemeldet. Kehre zu deinem Konto zurück, statt eine weitere Verifizierung zu starten.';

  @override
  String get recovery_restart => 'Neue Verifizierung starten';

  @override
  String get recovery_restart_warning =>
      'Die vorherige Anmeldung hat möglicherweise bereits deine Verschlüsselungsidentität geändert und alte Sitzungen widerrufen. Starte nur neu, wenn ein erneuter Versuch nicht abgeschlossen werden kann. Ein neuer E-Mail-Code und eine ausdrückliche Identitätsbestätigung sind erforderlich. Wenn die vorherige Anmeldung bestätigt wurde, bleibt ihre Identität erhalten.';

  @override
  String get recovery_login_title => 'Bei bestehendem Konto anmelden';

  @override
  String get recovery_email_title => 'Wiederherstellungs-E-Mail';

  @override
  String get recovery_email_settings =>
      'Kontowiederherstellung auf diesem angemeldeten Gerät verwalten.';

  @override
  String get recovery_login_description =>
      'Gib die zuvor auf deinem angemeldeten Gerät bestätigte Wiederherstellungs-E-Mail ein.';

  @override
  String get recovery_enrollment_description =>
      'Bestätige eine Wiederherstellungs-E-Mail auf diesem vertrauenswürdigen, angemeldeten Gerät. Nur die erste Adresse kann verknüpft werden; sie kann hier weder angezeigt noch ersetzt werden.';

  @override
  String get recovery_request_sent =>
      'Wenn diese Anfrage berechtigt ist, wird ein sechsstelliger Code gesendet. Prüfe deine E-Mails.';

  @override
  String get recovery_send_code => 'Code senden';

  @override
  String get recovery_verify => 'Code bestätigen';

  @override
  String get recovery_change_email =>
      'Andere E-Mail verwenden oder neuen Code anfordern';

  @override
  String get recovery_checking => 'Wiederherstellungsstatus wird geprüft…';

  @override
  String get recovery_retry => 'Erneut versuchen';

  @override
  String get recovery_email_bound =>
      'Für dieses Konto ist eine Wiederherstellungs-E-Mail bestätigt. Die Adresse wird nicht angezeigt und kann hier nicht geändert werden.';

  @override
  String get recovery_approval_title => 'Kontoanmeldung bestätigen';

  @override
  String get recovery_identity_warning =>
      'Diese Anmeldung erstellt eine neue Verschlüsselungsidentität für dein Konto. Deine Sicherheitsnummer ändert sich. Kontakte sollten sie erneut prüfen.';

  @override
  String get recovery_sessions_warning =>
      'Bisherige Kontositzungen werden widerrufen.';

  @override
  String get recovery_history_warning =>
      'Die Kontowiederherstellung stellt keine Nachrichten wieder her. Chatverläufe können nur aus einer vorhandenen Sicherung wiederhergestellt werden.';

  @override
  String get recovery_identity_accept =>
      'Ich stimme einer neuen Verschlüsselungsidentität und dem Widerruf bisheriger Sitzungen zu.';

  @override
  String get recovery_login_accept =>
      'Ich stimme dieser Anmeldung und dem Widerruf bisheriger Sitzungen zu.';

  @override
  String get recovery_complete => 'Bestätigen und anmelden';

  @override
  String get recovery_pending_description =>
      'Eine zuvor bestätigte Anmeldung wird abgeschlossen. Ein erneuter Versuch setzt dieselbe Anmeldung fort, ohne eine weitere Identität zu erstellen.';

  @override
  String get recovery_resume_unavailable =>
      'Die ausstehende Anmeldung konnte nicht fortgesetzt werden. Behalte die Daten dieses Geräts und versuche es erneut oder kontaktiere den Support.';

  @override
  String get recovery_error_rate_limit =>
      'Zu viele Versuche. Bitte warte vor einem erneuten Versuch.';

  @override
  String get recovery_error_rejected =>
      'Die Wiederherstellung konnte nicht bestätigt werden. Prüfe deine Angaben oder fordere einen neuen Code an.';

  @override
  String get recovery_error_generic =>
      'Die Wiederherstellung konnte nicht abgeschlossen werden. Bitte versuche es erneut.';

  @override
  String get recovery_registration_existing =>
      'Dieses Konto besteht bereits. Melde dich mit deiner bestätigten Wiederherstellungs-E-Mail beim bestehenden Konto an. Behalte dein angemeldetes Gerät.';

  @override
  String get auth_login_unavailable =>
      'Eine Registrierung ermöglicht keinen Zugriff auf ein bestehendes Konto. Die Anmeldung bei bestehenden Konten ist noch nicht verfügbar. Behalten Sie Ihr angemeldetes Gerät und wenden Sie sich an Ihren Administrator.';

  @override
  String get auth_setup_failed =>
      'Die Kontoeinrichtung wurde nicht abgeschlossen. Wenden Sie sich vor einer erneuten Registrierung an Ihren Administrator. Ein neuer Versuch erfordert einen neuen E-Mail-Code.';

  @override
  String notification_private_summary(int messageCount, int chatCount) {
    String _temp0 = intl.Intl.pluralLogic(
      messageCount,
      locale: localeName,
      other: '$messageCount Nachrichten',
      one: '1 Nachricht',
    );
    String _temp1 = intl.Intl.pluralLogic(
      chatCount,
      locale: localeName,
      other: '$chatCount Chats',
      one: '1 Chat',
    );
    return '$_temp0 aus $_temp1';
  }

  @override
  String get app_name => 'ELÇİM';

  @override
  String get group_info => 'Gruppeninfo';

  @override
  String get group_settings => 'Gruppeneinstellungen';

  @override
  String get add_member => 'Mitglied hinzufügen';

  @override
  String members_count(num arg1) {
    return 'Mitglieder ($arg1)';
  }

  @override
  String get loading => 'Wird geladen…';

  @override
  String get admin => 'Administrator';

  @override
  String get you => 'Du';

  @override
  String get remove_member => 'Mitglied entfernen';

  @override
  String get remove_from_group => 'Aus Gruppe entfernen';

  @override
  String get edit_group_name => 'Gruppennamen bearbeiten';

  @override
  String get group_name => 'Gruppenname';

  @override
  String get save => 'Speichern';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get add_new_member => 'Neues Mitglied hinzufügen';

  @override
  String get user_id => 'Benutzer-ID';

  @override
  String get add => 'Hinzufügen';

  @override
  String get remove_member_confirm => 'Mitglied entfernen';

  @override
  String remove_member_message(String arg1) {
    return 'Möchtest du $arg1 wirklich aus der Gruppe entfernen?';
  }

  @override
  String get remove => 'Entfernen';

  @override
  String get view_info => 'Informationen anzeigen';

  @override
  String get onboarding_subtitle => 'Sichere Kommunikation';

  @override
  String get onboarding_e2ee_notice =>
      'Deine Nachrichten sind Ende-zu-Ende verschlüsselt. Niemand kann sie lesen.';

  @override
  String get register_title => 'Registrieren';

  @override
  String get register_subtitle => 'Gib deine Daten ein, um zu starten.';

  @override
  String get register_name_label => 'Dein Name';

  @override
  String get register_name_placeholder => 'z. B. Max Mustermann';

  @override
  String get register_country_code_label => 'Vorwahl';

  @override
  String get register_phone_label => 'Telefonnummer';

  @override
  String get register_phone_placeholder => '5XX XXX XX XX';

  @override
  String get register_start => 'Starten';

  @override
  String get contacts_permission_title => 'Zugriff auf Kontakte erforderlich';

  @override
  String get contacts_permission_body =>
      'Die App benötigt Zugriff auf deine Kontakte. Erteile die Berechtigung, damit wir deine Kontakte finden und sichere Nachrichten ermöglichen können.';

  @override
  String get action_retry => 'Erneut versuchen';

  @override
  String get validation_name_empty => 'Gib deinen Namen ein';

  @override
  String validation_name_too_short(num arg1) {
    return 'Mindestens $arg1 Zeichen';
  }

  @override
  String validation_name_too_long(num arg1) {
    return 'Höchstens $arg1 Zeichen';
  }

  @override
  String get validation_name_invalid_chars =>
      'Nur Buchstaben, Leerzeichen, Bindestriche und Apostrophe';

  @override
  String get validation_country_code_empty => 'Vorwahl fehlt';

  @override
  String get validation_country_code_missing_plus => 'Muss mit + beginnen';

  @override
  String get validation_country_code_non_digit => 'Nur Ziffern';

  @override
  String get validation_country_code_too_short => 'Mindestens 1 Ziffer';

  @override
  String get validation_country_code_too_long => 'Höchstens 4 Ziffern';

  @override
  String get validation_phone_empty => 'Gib deine Telefonnummer ein';

  @override
  String get validation_phone_too_short => '10 Ziffern erforderlich';

  @override
  String get validation_phone_too_long => 'Nur 10 Ziffern';

  @override
  String get validation_phone_non_digit => 'Nur Ziffern';

  @override
  String get otp_title => 'Verifizierung';

  @override
  String get otp_section_title => 'Verifizierungscode';

  @override
  String otp_description(String arg1) {
    return 'Gib den 6-stelligen Code ein, der\\nan $arg1 gesendet wurde';
  }

  @override
  String get otp_incomplete_error => 'Bitte gib alle 6 Ziffern ein';

  @override
  String get otp_resend => 'Code erneut senden';

  @override
  String otp_resend_countdown(num arg1) {
    return 'Code erneut senden: ${arg1}s';
  }

  @override
  String get otp_verify => 'Verifizieren';

  @override
  String get backup_prompt_title => 'Hast du ein vorhandenes Backup?';

  @override
  String get backup_prompt_body =>
      'Wenn du zuvor ein verschlüsseltes Backup erstellt hast, kannst du deine Chats wiederherstellen.';

  @override
  String get backup_prompt_yes => 'Ja, Backup wiederherstellen';

  @override
  String get backup_prompt_no => 'Nein, neu beginnen';

  @override
  String get nav_back => 'Zurück';

  @override
  String get email_otp_title => 'E-Mail-Verifizierung';

  @override
  String get email_otp_step_email => 'Deine E-Mail-Adresse';

  @override
  String get email_otp_step_code => 'Verifizierungscode';

  @override
  String get email_otp_description_email =>
      'Gib deine E-Mail-Adresse ein, um dein Konto zu verifizieren. Wir senden den Code an deine E-Mail-Adresse.';

  @override
  String email_otp_description_code(String arg1) {
    return 'Gib den 6-stelligen Code ein, der an $arg1 gesendet wurde.';
  }

  @override
  String get email_otp_email_label => 'E-Mail';

  @override
  String get email_otp_code_label => '6-stelliger Code';

  @override
  String get email_otp_send => 'Code senden';

  @override
  String get email_otp_change_email => 'Andere E-Mail-Adresse verwenden';

  @override
  String get email_otp_dev_skip => 'Entwicklungsmodus — Überspringen';

  @override
  String get email_otp_invalid_email => 'Gib eine gültige E-Mail-Adresse ein';

  @override
  String get email_otp_sent => 'Code an deine E-Mail-Adresse gesendet';

  @override
  String get email_otp_smtp_disabled =>
      'Der E-Mail-Dienst ist auf dem Server nicht konfiguriert. Wende dich an deine Administration oder nutze im Entwicklungsmodus „Überspringen“.';

  @override
  String get email_otp_rate_limited =>
      'Zu viele Versuche. Warte einige Minuten.';

  @override
  String email_otp_send_error(String arg1) {
    return 'Code konnte nicht gesendet werden: $arg1';
  }

  @override
  String get email_otp_verify_failed => 'Code ungültig oder abgelaufen';

  @override
  String get email_otp_incomplete => 'Gib alle 6 Ziffern ein';

  @override
  String get create_group_title => 'Neue Gruppe';

  @override
  String get create_group_action => 'Erstellen';

  @override
  String create_group_selected_members(num arg1) {
    return 'Ausgewählte Mitglieder ($arg1)';
  }

  @override
  String get create_group_add_by_phone => 'Über Nummer hinzufügen';

  @override
  String get create_group_user_not_found => 'Benutzer nicht gefunden';

  @override
  String get create_group_send_invite => 'Einladung senden';

  @override
  String get create_group_close => 'Schließen';

  @override
  String get create_group_registered_contacts => 'Registrierte Kontakte';

  @override
  String get create_group_search_placeholder => 'Kontakte suchen…';

  @override
  String get invite_chooser_title => 'Einladung senden';

  @override
  String get cd_remove => 'Entfernen';

  @override
  String get cd_search => 'Suchen';

  @override
  String get cd_clear => 'Löschen';

  @override
  String get cd_add => 'Hinzufügen';

  @override
  String get cd_more => 'Mehr';

  @override
  String get cd_connection_status => 'Verbindungsstatus';

  @override
  String get cd_new_chat_action => 'Chat starten';

  @override
  String get cd_member_actions => 'Mitgliederaktionen';

  @override
  String get network_error_title => 'Verbindungsfehler';

  @override
  String get contacts_grant_permission => 'Zugriff auf Kontakte erteilen';

  @override
  String get contacts_invite_short => 'Einladen';

  @override
  String get settings_title => 'Einstellungen';

  @override
  String get settings_nuke_dialog_title => 'Alle Chats löschen';

  @override
  String get settings_nuke_dialog_body =>
      'Alle Chats und Nachrichten werden endgültig gelöscht. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get settings_nuke_confirm => 'Löschen';

  @override
  String get settings_nuke_backup_first => 'Zuerst sichern';

  @override
  String get settings_nuke_all_data_warning =>
      'Alle deine Nachrichten, Kontakte und Einstellungen werden gelöscht.';

  @override
  String get settings_nuke_type_to_confirm =>
      'Gib zur Bestätigung \\\"DELETE\\\" ein:';

  @override
  String get settings_nuke_type_placeholder => 'DELETE';

  @override
  String get settings_chat_theme => 'Chat-Design';

  @override
  String get settings_language => 'Sprache';

  @override
  String get settings_backdrop => 'Hintergrundmuster';

  @override
  String get settings_fullscreen => 'Vollbildmodus';

  @override
  String get settings_show_message_preview => 'Nachrichteninhalt anzeigen';

  @override
  String get settings_notification_sound => 'Benachrichtigungston';

  @override
  String get settings_incoming_call_screen => 'Anrufbildschirm';

  @override
  String get settings_missed_call => 'Hinweise zu verpassten Anrufen';

  @override
  String get settings_battery_optimization => 'Akkuoptimierung';

  @override
  String get settings_scheduled_messages => 'Geplante Nachrichten';

  @override
  String get settings_manage_scheduled => 'Geplante Nachrichten verwalten';

  @override
  String get settings_manage_scheduled_desc =>
      'Vorhandene geplante Nachrichten ansehen und bearbeiten';

  @override
  String get settings_e2ee => 'Ende-zu-Ende-Verschlüsselung';

  @override
  String get settings_e2ee_desc =>
      'Deine Nachrichten werden Ende-zu-Ende verschlüsselt';

  @override
  String get settings_last_seen => 'Zuletzt online';

  @override
  String get settings_message_storage =>
      'Richtlinie zur Nachrichtenspeicherung';

  @override
  String get settings_message_storage_desc =>
      'Nachrichten werden nur auf diesem Gerät gespeichert';

  @override
  String get settings_backup => 'Backup';

  @override
  String get settings_backup_desc =>
      'Chats verschlüsselt sichern oder wiederherstellen';

  @override
  String get settings_storage_usage => 'Speicher';

  @override
  String get create_group_and_add => 'Gruppe erstellen und Personen hinzufügen';

  @override
  String get recipient_action_failed =>
      'Aktion fehlgeschlagen. Bitte erneut versuchen.';

  @override
  String get settings_share_online => 'Online-Status teilen';

  @override
  String get settings_read_receipts => 'Lesebestätigungen';

  @override
  String get settings_read_receipts_desc =>
      'Wenn deaktiviert, werden keine Lesebestätigungen gesendet oder von anderen angezeigt.';

  @override
  String get message_show_more => 'Mehr anzeigen';

  @override
  String get message_show_less => 'Weniger anzeigen';

  @override
  String get chat_info_note_label => 'Notiz';

  @override
  String get chat_info_search_placeholder => 'Nachrichten suchen…';

  @override
  String get conv_new_chat => 'Neuer Chat';

  @override
  String get conv_new_group => 'Neue Gruppe';

  @override
  String get conv_bulk_message => 'Sammelnachricht';

  @override
  String get conv_scheduled_messages => 'Geplante Nachrichten';

  @override
  String get conv_filter_all => 'Alle';

  @override
  String get conv_filter_unread => 'Ungelesen';

  @override
  String get conv_filter_groups => 'Gruppen';

  @override
  String get conv_filter_favorites => 'Favoriten';

  @override
  String get conv_archive => 'Archivieren';

  @override
  String get conv_delete => 'Löschen';

  @override
  String get conv_info => 'Info';

  @override
  String get conv_delete_chat => 'Chat löschen';

  @override
  String get group_view_profile => 'Profil ansehen';

  @override
  String get group_leave => 'Gruppe verlassen';

  @override
  String get group_not_member => 'Du bist kein Mitglied dieser Gruppe mehr.';

  @override
  String get group_leave_failed =>
      'Die Austrittsnachricht konnte nicht gesendet werden. Prüfe deine Verbindung und versuche es erneut.';

  @override
  String get chat_search_in_chat => 'Im Chat suchen';

  @override
  String get chat_export => 'Chat exportieren';

  @override
  String get action_close => 'Schließen';

  @override
  String get chat_custom_duration => 'Eigene Dauer';

  @override
  String get msg_action_reply => 'Antworten';

  @override
  String get msg_action_copy => 'Kopieren';

  @override
  String get message_copied => 'Nachricht kopiert.';

  @override
  String get msg_action_edit => 'Bearbeiten';

  @override
  String get msg_action_edit_history => 'Bearbeitungsverlauf';

  @override
  String get msg_action_info => 'Info';

  @override
  String get msg_action_forward => 'Weiterleiten';

  @override
  String get msg_action_delete_for_me => 'Für mich löschen';

  @override
  String get msg_delete_title => 'Nachricht löschen';

  @override
  String get msg_delete_cancel => 'Verwerfen';

  @override
  String get msg_edit_title => 'Nachricht bearbeiten';

  @override
  String get sched_title => 'Geplante Nachrichten';

  @override
  String get sched_delete_title => 'Geplante Nachricht löschen';

  @override
  String get sched_delete_body =>
      'Diese geplante Nachricht wird endgültig gelöscht.';

  @override
  String get sched_tab_create => 'Erstellen';

  @override
  String get sched_tab_existing => 'Vorhanden';

  @override
  String get sched_message_placeholder => 'Schreibe deine Nachricht…';

  @override
  String get sched_action_edit => 'Bearbeiten';

  @override
  String get sched_action_delete => 'Löschen';

  @override
  String get sched_pick_time => 'Uhrzeit wählen';

  @override
  String get sched_pick_day => 'Tag wählen';

  @override
  String get sched_pick_recipient => 'Empfänger wählen';

  @override
  String get action_ok => 'OK';

  @override
  String get conversations_title => 'Chats';

  @override
  String get conversations_search => 'Chats durchsuchen';

  @override
  String get nav_chats => 'Chats';

  @override
  String get nav_calls => 'Anrufe';

  @override
  String get nav_contacts => 'Kontakte';

  @override
  String get chat_e2ee => 'Ende-zu-Ende verschlüsselt';

  @override
  String get archive_remove => 'Archivierung aufheben';

  @override
  String get profile_photo_change => 'Profilbild ändern';

  @override
  String get settings_watermark_desc => 'Elçim-Wasserzeichen anzeigen';

  @override
  String get settings_scheduled_enabled_desc => 'Hintergrundversand aktivieren';

  @override
  String get settings_local_data_desc =>
      'Nachrichten, Kontakte, Medien und Einstellungen';

  @override
  String get settings_account_data_desc =>
      'Serverkonto und alle Daten auf diesem Gerät';

  @override
  String get settings_logout => 'Abmelden';

  @override
  String get settings_notification_preview_desc =>
      'Benachrichtigungsvorschau auf dem Sperrbildschirm';

  @override
  String get settings_default_notification_sound =>
      'Standard-Benachrichtigungston';

  @override
  String get settings_silent => 'Lautlos';

  @override
  String get sound_system => 'Gerätestandard';

  @override
  String get sound_chime => 'Glockenspiel';

  @override
  String get sound_bell => 'Glocke';

  @override
  String get sound_tap => 'Tippen';

  @override
  String get sound_warm => 'Warm';

  @override
  String get sound_soft => 'Sanft';

  @override
  String get sound_melody => 'Melodie';

  @override
  String get sound_flow => 'Fluss';

  @override
  String get sound_sparkle => 'Funkeln';

  @override
  String get sound_beep => 'Piep';

  @override
  String get sound_ding => 'Ding';

  @override
  String get sound_preview => 'Ton abspielen';

  @override
  String get sound_inherit => 'App-Einstellung verwenden';

  @override
  String get sound_system_picker => 'Weitere Töne auf diesem Gerät';

  @override
  String get sound_system_picker_desc =>
      'Beliebigen Ton aus den Systemeinstellungen wählen';

  @override
  String get settings_share_last_seen => 'Zuletzt online teilen';

  @override
  String get settings_share_phone_number => 'Meine Telefonnummer teilen';

  @override
  String get settings_share_phone_number_desc =>
      'Nur mit Personen, denen ich direkt schreibe, Ende-zu-Ende verschlüsselt. Bereits geteilte Nummern können nicht zurückgerufen werden.';

  @override
  String get settings_screen_protection => 'Bildschirmschutz aktiviert';

  @override
  String get camera => 'Kamera';

  @override
  String get gallery => 'Galerie';

  @override
  String get profile_photo_remove => 'Foto entfernen';

  @override
  String get settings_delete_local_data => 'Alle lokalen Daten löschen';

  @override
  String get settings_delete_account => 'Konto dauerhaft löschen';

  @override
  String get settings_delete_account_body =>
      'Dein Serverkonto und alle Daten auf diesem Gerät werden gelöscht. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get theme_system => 'System';

  @override
  String get theme_light => 'Hell';

  @override
  String get theme_dark => 'Dunkel';

  @override
  String get settings_content_hidden => 'Nachrichteninhalt ausgeblendet';

  @override
  String get settings_content_visible => 'Inhalt sichtbar';

  @override
  String get settings_privacy => 'Datenschutz';

  @override
  String get settings_last_seen_hidden => 'Zuletzt online wird nicht geteilt';

  @override
  String get settings_last_seen_shared => 'Zuletzt online wird geteilt';

  @override
  String get settings_fullscreen_ios_desc =>
      'iOS behält Systembereiche bei und verwendet ein randloses Layout';

  @override
  String get settings_fullscreen_android_desc =>
      'Android-Systemleisten in der App ausblenden';

  @override
  String get settings_auto_download => 'Automatischer Download';

  @override
  String get settings_auto_download_desc => 'WLAN- und Mobilfunkregeln';

  @override
  String get settings_call_readiness => 'Anrufbereitschaft';

  @override
  String get settings_call_readiness_desc =>
      'Akku-, Benachrichtigungs- und Sperrbildschirmberechtigungen';

  @override
  String get settings_bulk_message => 'Sammelnachricht';

  @override
  String get settings_bulk_message_desc => 'Sicher an mehrere Chats senden';

  @override
  String get settings_storage_desc => 'Medien- und Chatnutzung';

  @override
  String get settings_presence_immediate_desc =>
      'Änderungen werden sofort an das Anwesenheitsprotokoll gesendet';

  @override
  String get settings_screen_protection_desc =>
      'Android blockiert Bildschirmaufnahmen; iOS verdeckt Inhalte im App-Umschalter.';

  @override
  String get group_not_found => 'Gruppe nicht gefunden.';

  @override
  String get group_admin_only => 'Nur Admins können Nachrichten senden';

  @override
  String get group_announcement_desc => 'Gruppe als Ankündigungskanal nutzen';

  @override
  String get mute => 'Stummschalten';

  @override
  String get chat_lock => 'Chat-Sperre';

  @override
  String get chat_lock_desc => 'Zugriff mit einem Chat-Passwort';

  @override
  String get chat_lock_create_title => 'Chat-Passwort festlegen';

  @override
  String get chat_lock_create_body =>
      'Dieses Passwort wird jedes Mal verlangt, wenn dieser Chat auf diesem Gerät geöffnet wird.';

  @override
  String get chat_lock_unlock_title => 'Chat entsperren';

  @override
  String chat_lock_unlock_body(String chatName) {
    return 'Gib das Passwort für $chatName ein.';
  }

  @override
  String get chat_lock_unlock_action => 'Entsperren';

  @override
  String get chat_lock_wrong_password => 'Falsches Passwort.';

  @override
  String get chat_lock_update_failed =>
      'Die Chat-Sperre konnte nicht aktualisiert werden.';

  @override
  String get export_history => 'Exportverlauf';

  @override
  String get make_admin => 'Zum Admin machen';

  @override
  String get no_contacts_to_add =>
      'Es können keine gespeicherten Kontakte hinzugefügt werden.';

  @override
  String get confirmation => 'Bestätigung';

  @override
  String get confirm => 'Bestätigen';

  @override
  String get background_unavailable =>
      'Der Hintergrunddienst ist nicht verfügbar.';

  @override
  String get storage_service_unavailable =>
      'Der Speicherdienst ist nicht verfügbar.';

  @override
  String get edit_mode => 'Bearbeitungsmodus';

  @override
  String get repeat_once => 'Einmal';

  @override
  String get repeat_daily => 'Täglich';

  @override
  String get repeat_custom => 'Eigene';

  @override
  String get weekdays_short => 'Mo,Di,Mi,Do,Fr,Sa,So';

  @override
  String get schedule_days_label => 'Tage';

  @override
  String get schedule_days_empty => 'Tage auswählen';

  @override
  String get delivery_time => 'Zustellzeit';

  @override
  String get message_content => 'Nachrichtentext';

  @override
  String get recipients => 'Empfänger';

  @override
  String get recipient_required => 'Wähle mindestens eine Person oder Gruppe';

  @override
  String get schedule => 'Planen';

  @override
  String get update => 'Aktualisieren';

  @override
  String get no_scheduled_messages => 'Noch keine geplanten Nachrichten.';

  @override
  String get schedule_saved => 'Geplante Nachricht gespeichert.';

  @override
  String get form_incomplete => 'Das Formular ist unvollständig.';

  @override
  String get over_wifi => 'Über WLAN';

  @override
  String get over_cellular => 'Über mobile Daten';

  @override
  String get photos => 'Fotos';

  @override
  String get videos => 'Videos';

  @override
  String get documents => 'Dokumente';

  @override
  String cellular_limit(num arg1) {
    return 'Mobilfunk-Limit: $arg1 MB';
  }

  @override
  String get no_chats_yet => 'Noch keine Chats';

  @override
  String storage_summary(num arg1, num arg2, String arg3) {
    return '$arg1 Nachrichten · $arg2 Dateien · $arg3';
  }

  @override
  String get clear_media => 'Medien löschen';

  @override
  String clear_media_body(String arg1) {
    return 'Medien- und Dateinachrichten in „$arg1“ werden gelöscht. Textnachrichten bleiben erhalten.';
  }

  @override
  String get no_exports_yet => 'Noch keine Exporte';

  @override
  String message_count(num arg1) {
    return '$arg1 Nachrichten';
  }

  @override
  String get entire_chat => 'Gesamter Chat';

  @override
  String get admin_only_screen =>
      'Dieser Bereich ist nur für Gruppenadmins verfügbar';

  @override
  String get bulk_unavailable => 'Sammelversand ist nicht verfügbar.';

  @override
  String get bulk_explainer_title => 'Einzeln an jeden gesendet';

  @override
  String get bulk_explainer_body =>
      'Dieselbe Nachricht wird an jeden ausgewählten Chat als separate Nachricht gesendet. Die Empfänger sehen sich nicht gegenseitig und es wird keine Gruppe erstellt.';

  @override
  String get bulk_search_hint => 'Personen oder Gruppen suchen';

  @override
  String bulk_selected_count(Object arg1, Object arg2) {
    return '$arg1 von $arg2 ausgewählt';
  }

  @override
  String get bulk_no_recipients => 'Keine Chats zum Senden';

  @override
  String get bulk_no_results => 'Keine passenden Chats';

  @override
  String get bulk_message_required => 'Schreibe zuerst deine Nachricht';

  @override
  String get select_all => 'Alle auswählen';

  @override
  String get group => 'Gruppe';

  @override
  String send_to_recipients(num arg1) {
    return 'An $arg1 Empfänger senden';
  }

  @override
  String bulk_result(num arg1, num arg2) {
    return '$arg1 gesendet, $arg2 fehlgeschlagen.';
  }

  @override
  String get encrypted_backup => 'Verschlüsseltes Backup';

  @override
  String get backup_explanation =>
      'Chats, Kontakte, Anrufprotokolle, geplante Nachrichten und der Zustand der Ende-zu-Ende-Verschlüsselung werden in einer passwortgeschützten .elbk-Datei gespeichert. Sitzungszugriffsschlüssel sind ausgeschlossen.';

  @override
  String get create_backup => 'Neues Backup erstellen';

  @override
  String get restore_backup_file => 'Backup-Datei wiederherstellen';

  @override
  String get backups_on_device => 'Backups auf diesem Gerät';

  @override
  String get no_local_backups => 'Noch keine lokalen Backups';

  @override
  String get backup_password => 'Backup-Passwort';

  @override
  String get backup_unavailable => 'Der Backup-Dienst ist nicht verfügbar.';

  @override
  String get save_encrypted_backup => 'Verschlüsseltes Backup speichern';

  @override
  String get backup_created => 'Verschlüsseltes Backup erstellt.';

  @override
  String backup_create_failed(String arg1) {
    return 'Backup konnte nicht erstellt werden: $arg1';
  }

  @override
  String get backup_restored => 'Backup wiederhergestellt.';

  @override
  String wrong_password_attempts(num arg1) {
    return 'Falsches Passwort. $arg1 Versuche übrig.';
  }

  @override
  String get backup_deleted_after_attempts =>
      'Die Backup-Datei wurde nach fünf falschen Versuchen gelöscht.';

  @override
  String get backup_delete_failed_after_attempts =>
      'Versuchsgrenze erreicht; das System konnte die Datei nicht löschen.';

  @override
  String get password => 'Passwort';

  @override
  String get password_min_length => 'Mindestens 8 Zeichen';

  @override
  String get password_repeat => 'Passwort wiederholen';

  @override
  String get password_too_short =>
      'Das Passwort muss mindestens 8 Zeichen lang sein.';

  @override
  String get password_mismatch => 'Die Passwörter stimmen nicht überein.';

  @override
  String get restore => 'Wiederherstellen';

  @override
  String get no_call_history => 'Noch kein Anrufverlauf.';

  @override
  String get video_call => 'Videoanruf';

  @override
  String get voice_call => 'Sprachanruf';

  @override
  String get outgoing => 'Ausgehend';

  @override
  String get incoming => 'Eingehend';

  @override
  String get video => 'Video';

  @override
  String get voice => 'Sprach';

  @override
  String get missed => 'Verpasst';

  @override
  String get rejected => 'Abgelehnt';

  @override
  String get busy => 'Besetzt';

  @override
  String get failed => 'Fehlgeschlagen';

  @override
  String call_description(String arg1, String arg2, String arg3) {
    return '$arg1 ${arg2}anruf$arg3';
  }

  @override
  String get recheck_status => 'Status erneut prüfen';

  @override
  String get calls_ready => 'Du bist für Anrufe bereit';

  @override
  String get calls_readiness_missing =>
      'Vervollständige die fehlenden Punkte, um Anrufverzögerungen zu vermeiden';

  @override
  String get battery_optimization_desc =>
      'Reduziert Doze-Verzögerungen für datenbasierte Push-Nachrichten und Hintergrundarbeit';

  @override
  String get fullscreen_call_notification => 'Vollbild-Anrufbenachrichtigung';

  @override
  String get fullscreen_call_notification_desc =>
      'Anrufansicht auf dem Sperrbildschirm ab Android 14';

  @override
  String get notification_permission => 'Benachrichtigungsberechtigung';

  @override
  String get notification_permission_desc =>
      'Benachrichtigungen für Nachrichten und eingehende Anrufe';

  @override
  String get ios_call_readiness_note =>
      'Unter iOS können Akkuoptimierung und Vollbild-Intent nicht von der App geändert werden. Das Aufwecken bei eingehenden Anrufen hängt von APNs/CallKit und den Systemrichtlinien ab.';

  @override
  String get secure_communication => 'Sichere Kommunikation';

  @override
  String get onboarding_private_subtitle =>
      'Deine Nachrichten bleiben zwischen euch';

  @override
  String get onboarding_private_body =>
      'Jede Nachricht wird auf deinem Gerät verschlüsselt; der Server kann ihren Inhalt nicht lesen.';

  @override
  String get onboarding_direct_call => 'Direkte Anrufe';

  @override
  String get onboarding_webrtc_subtitle => 'Sprache und Video über WebRTC';

  @override
  String get onboarding_webrtc_body =>
      'Einzelanrufe werden direkt verbunden; große Gruppenanrufe nutzen den Janus-SFU.';

  @override
  String get onboarding_privacy_control =>
      'Vollständige Kontrolle über die Privatsphäre';

  @override
  String get onboarding_you_decide => 'Du entscheidest';

  @override
  String get onboarding_privacy_body =>
      'Einmal ansehen, verschwindende Nachrichten, Bildschirmschutz und Export-Richtlinie für Gruppen.';

  @override
  String get skip => 'Überspringen';

  @override
  String get lets_start => 'Los geht’s';

  @override
  String get continue_action => 'Weiter';

  @override
  String get notifications => 'Benachrichtigungen';

  @override
  String get notifications_permission_reason =>
      'Für neue Nachrichten und Anrufe.';

  @override
  String get contacts_permission_reason =>
      'Um Personen ausschließlich über Hashes zu finden.';

  @override
  String get microphone => 'Mikrofon';

  @override
  String get microphone_permission_reason => 'Für Sprach- und Videoanrufe.';

  @override
  String get camera_permission_reason => 'Für Videoanrufe.';

  @override
  String get permissions_required => 'Einige Berechtigungen sind erforderlich';

  @override
  String get permissions_intro =>
      'Erteile jetzt die Berechtigungen, die du möchtest; die übrigen kannst du später in den Einstellungen aktivieren.';

  @override
  String get grant_permission => 'Berechtigung erteilen';

  @override
  String get chat_not_found => 'Chat nicht gefunden.';

  @override
  String get contact_info => 'Kontaktinfo';

  @override
  String get starred_messages => 'Markierte Nachrichten';

  @override
  String get media => 'Medien';

  @override
  String get disappearing_messages => 'Verschwindende Nachrichten';

  @override
  String disappearing_timer_enabled_by_you(String duration) {
    return 'Du hast verschwindende Nachrichten auf $duration gesetzt.';
  }

  @override
  String get disappearing_timer_disabled_by_you =>
      'Du hast verschwindende Nachrichten deaktiviert.';

  @override
  String disappearing_timer_enabled_by_peer(String sender, String duration) {
    return '$sender hat verschwindende Nachrichten auf $duration gesetzt.';
  }

  @override
  String disappearing_timer_disabled_by_peer(String sender) {
    return '$sender hat verschwindende Nachrichten deaktiviert.';
  }

  @override
  String get contact_note => 'Kontaktnotiz';

  @override
  String get tap_to_add_note => 'Tippen, um eine Notiz hinzuzufügen';

  @override
  String get no_records => 'Keine Einträge gefunden';

  @override
  String get add_contact_note => 'Kontaktnotiz hinzufügen';

  @override
  String get off => 'Aus';

  @override
  String hours(num arg1) {
    return '$arg1 Stunden';
  }

  @override
  String days(num arg1) {
    return '$arg1 Tage';
  }

  @override
  String files_selected(num arg1) {
    return '$arg1 Dateien ausgewählt';
  }

  @override
  String get add_caption => 'Beschriftung hinzufügen …';

  @override
  String get view_once => 'Einmal ansehen';

  @override
  String get view_once_protected => 'Einmal ansehen · Bildschirm geschützt';

  @override
  String get share => 'Teilen';

  @override
  String get tap_to_close_view_once =>
      'Tippen zum Schließen · kann nicht erneut geöffnet werden';

  @override
  String file_open_failed(String arg1) {
    return 'Datei konnte nicht geöffnet werden: $arg1';
  }

  @override
  String file_share_failed(String arg1) {
    return 'Datei konnte nicht geteilt werden: $arg1';
  }

  @override
  String get file => 'Datei';

  @override
  String get open_with_app => 'Mit App öffnen';

  @override
  String get media_not_found => 'Mediendatei nicht gefunden';

  @override
  String get call_service_unavailable =>
      'Der Anrufdienst konnte nicht gestartet werden.';

  @override
  String get locked_chat => 'Gesperrter Chat';

  @override
  String get disable_export => 'Export deaktivieren';

  @override
  String get enable_export => 'Export aktivieren';

  @override
  String get clear_chat => 'Chat leeren';

  @override
  String get read_only_announcement =>
      'Diese Gruppe ist ein Ankündigungskanal, in dem nur Admins posten können.';

  @override
  String get no_matching_messages => 'Keine passenden Nachrichten gefunden';

  @override
  String get cancel_selection => 'Auswahl aufheben';

  @override
  String messages_selected(num arg1) {
    return '$arg1 Nachrichten ausgewählt';
  }

  @override
  String get forward_selected => 'Auswahl weiterleiten';

  @override
  String get record_voice_message => 'Sprachnachricht aufnehmen';

  @override
  String get poll => 'Umfrage';

  @override
  String get add_reaction => 'Reaktion hinzufügen';

  @override
  String get remove_star => 'Markierung entfernen';

  @override
  String get add_star => 'Markieren';

  @override
  String get unpin => 'Lösen';

  @override
  String get pin => 'Anpinnen';

  @override
  String get choose_reaction => 'Reaktion wählen';

  @override
  String get delete_for_everyone => 'Für alle löschen';

  @override
  String get clear_chat_confirm => 'Diesen Chat leeren?';

  @override
  String get clear_chat_body =>
      'Alle Nachrichten auf diesem Gerät werden endgültig gelöscht.';

  @override
  String get clear_group_history_body =>
      'Nur die Nachrichten dieser Gruppe auf diesem Gerät werden gelöscht. Die Gruppe und Ihre Mitgliedschaft bleiben erhalten. Nachrichten anderer Mitglieder bleiben unverändert.';

  @override
  String get voice_message => 'Sprachnachricht';

  @override
  String get recording_start_failed => 'Aufnahme konnte nicht gestartet werden';

  @override
  String get recording_paused => 'Aufnahme pausiert';

  @override
  String get recording_active => 'Aufnahme läuft';

  @override
  String get send => 'Senden';

  @override
  String get poll_load_failed => 'Umfrage konnte nicht geladen werden';

  @override
  String get single_choice => 'Einfachauswahl';

  @override
  String get multiple_choice => 'Mehrfachauswahl';

  @override
  String total_votes(num arg1) {
    return '$arg1 Stimmen insgesamt';
  }

  @override
  String get message_info => 'Nachrichteninfo';

  @override
  String get sent => 'Gesendet';

  @override
  String get read => 'Gelesen';

  @override
  String get delivered => 'Zugestellt';

  @override
  String get send_failed_no_plaintext =>
      'Senden fehlgeschlagen. Es wurde kein unverschlüsselter Ersatzweg verwendet.';

  @override
  String get forward_to_chat => 'An Chat weiterleiten';

  @override
  String get read_only_chat => 'Nur-Lese-Chat';

  @override
  String participant_count(num arg1) {
    return '$arg1 Teilnehmende';
  }

  @override
  String get create_poll => 'Umfrage erstellen';

  @override
  String get question => 'Frage';

  @override
  String option_number(num arg1) {
    return 'Option $arg1';
  }

  @override
  String get add_option => 'Option hinzufügen';

  @override
  String get member_export_permission =>
      'Mitglieder dürfen kopieren und exportieren';

  @override
  String get admin_change_only => 'Nur ein Admin kann dies ändern';

  @override
  String remove_member_named(String arg1) {
    return '$arg1 aus der Gruppe entfernen?';
  }

  @override
  String get leave_group_confirm => 'Möchtest du diese Gruppe verlassen?';

  @override
  String get archive => 'Archivieren';

  @override
  String get remove_favorite => 'Aus Favoriten entfernen';

  @override
  String get add_favorite => 'Zu Favoriten hinzufügen';

  @override
  String get mark_read => 'Als gelesen markieren';

  @override
  String get mark_unread => 'Als ungelesen markieren';

  @override
  String delete_chat_body(String arg1) {
    return 'Den Chat mit $arg1 und seine Nachrichten endgültig von diesem Gerät löschen?';
  }

  @override
  String get reject => 'Ablehnen';

  @override
  String get answer => 'Annehmen';

  @override
  String get unmute => 'Stummschaltung aufheben';

  @override
  String get speaker => 'Lautsprecher';

  @override
  String get flip_camera => 'Wechseln';

  @override
  String get end_call => 'Beenden';

  @override
  String get call_preparing => 'Anruf wird vorbereitet …';

  @override
  String get incoming_call => 'Eingehender Anruf';

  @override
  String get ringing => 'Es klingelt …';

  @override
  String get connecting => 'Verbindung wird hergestellt …';

  @override
  String get reconnecting => 'Verbindung wird wiederhergestellt …';

  @override
  String get weak_connection_disable_video =>
      'Schwache Verbindung — Video ausschalten und mit Audio fortfahren';

  @override
  String get call_ended => 'Anruf beendet';

  @override
  String get call_rejected => 'Anruf abgelehnt';

  @override
  String get connection_failed => 'Verbindung fehlgeschlagen';

  @override
  String get voice_service_unavailable =>
      'Der Dienst für Sprachnachrichten konnte nicht gestartet werden.';

  @override
  String get voice_encrypting =>
      'Sprachnachricht wird verschlüsselt und gesendet …';

  @override
  String get voice_sent => 'Sprachnachricht gesendet.';

  @override
  String voice_send_failed(String arg1) {
    return 'Sprachnachricht konnte nicht gesendet werden: $arg1';
  }

  @override
  String get file_transfer_unavailable =>
      'Der Dateiübertragungsdienst konnte nicht gestartet werden.';

  @override
  String media_pick_failed(String arg1) {
    return 'Medien konnten nicht ausgewählt werden: $arg1';
  }

  @override
  String get media_encrypting => 'Medien werden verschlüsselt und gesendet …';

  @override
  String media_send_failed(String arg1) {
    return 'Medien konnten nicht gesendet werden: $arg1';
  }

  @override
  String media_sent(num arg1) {
    return '$arg1 Medienelemente verschlüsselt gesendet.';
  }

  @override
  String media_failed(num arg1, String arg2) {
    return '$arg1 Medienelemente fehlgeschlagen: $arg2';
  }

  @override
  String get poll_unavailable => 'Der Umfragedienst ist nicht verfügbar.';

  @override
  String get poll_sent => 'Umfrage gesendet.';

  @override
  String get poll_send_failed => 'Umfrage konnte nicht gesendet werden.';

  @override
  String get vote_send_failed =>
      'Die Stimme konnte nicht sicher gesendet werden.';

  @override
  String get pin_failed =>
      'Keine Pin-Berechtigung oder Signalisierung fehlgeschlagen.';

  @override
  String get forward_service_unavailable =>
      'Der Weiterleitungsdienst konnte nicht gestartet werden.';

  @override
  String forward_encrypting(num arg1, String arg2) {
    return '$arg1 Nachrichten werden für $arg2 neu verschlüsselt …';
  }

  @override
  String forward_encryption_result(num arg1, num arg2) {
    return '$arg1 Nachrichten weitergeleitet; $arg2 konnten nicht verschlüsselt und nicht gesendet werden.';
  }

  @override
  String forward_sent(num arg1) {
    return '$arg1 Nachrichten weitergeleitet.';
  }

  @override
  String forward_partial(num arg1, num arg2) {
    return '$arg1 Nachrichten weitergeleitet; $arg2 fehlgeschlagen.';
  }

  @override
  String get reaction_failed => 'Reaktion konnte nicht gesendet werden.';

  @override
  String get edit_failed => 'Nachricht konnte nicht bearbeitet werden.';

  @override
  String get delete_signal_failed =>
      'Löschsignal konnte nicht gesendet werden.';

  @override
  String get export_unavailable => 'Export ist nicht verfügbar.';

  @override
  String get chat_exported => 'Chat exportiert.';

  @override
  String get group_policy_unavailable =>
      'Die Gruppenrichtlinie ist nicht verfügbar.';

  @override
  String get export_disabled => 'Export deaktiviert.';

  @override
  String get export_enabled => 'Export aktiviert.';

  @override
  String get chat_unmuted => 'Stummschaltung des Chats aufgehoben.';

  @override
  String get chat_muted => 'Chat stummgeschaltet.';

  @override
  String get invalid_voice_recording =>
      'Es konnte keine gültige Sprachaufnahme erstellt werden.';

  @override
  String get audio_not_found => 'Audiodatei nicht gefunden';

  @override
  String get audio_play_failed =>
      'Sprachaufnahme konnte nicht abgespielt werden';

  @override
  String get opened => 'Geöffnet';

  @override
  String get view_once_photo => 'Einmal-ansehen-Foto';

  @override
  String get media_no_longer_available =>
      'Dieses Medium kann nicht mehr geöffnet werden';

  @override
  String get tap_to_open => 'Tippen zum Öffnen';

  @override
  String get attachment => 'Anhang hinzufügen';

  @override
  String get dialpad => 'Wähltastatur öffnen';

  @override
  String get remove_option => 'Option entfernen';

  @override
  String get auth_unavailable =>
      'Der Authentifizierungsdienst ist nicht konfiguriert.';

  @override
  String rate_limit_seconds(num arg1) {
    return 'Zu viele Anfragen. Warte $arg1 Sekunden.';
  }

  @override
  String get chat_cleared => 'Chat geleert.';

  @override
  String get no_registered_contacts =>
      'Keine registrierten Kontakte gefunden. Erteile die Kontaktberechtigung und aktualisiere.';

  @override
  String get contacts_secure_directory_unavailable_title =>
      'Sicheres Kontaktverzeichnis nicht verfügbar';

  @override
  String get contacts_secure_directory_unavailable_body =>
      'Der Server stellt das private Verzeichnisprotokoll noch nicht bereit. Es wurde kein unsicherer Ersatz verwendet; zuvor bestätigte Kontakte bleiben ausschließlich auf deinem Gerät.';

  @override
  String get contacts_secure_directory_server_upgrade_title =>
      'Server-Update erforderlich';

  @override
  String get contacts_secure_directory_server_upgrade_body =>
      'Die Verbindung wurde hergestellt, aber das sichere Verzeichnismodul ist auf dem Server nicht aktiviert. Deine Adressbuchdaten wurden nicht gesendet; versuche es nach dem Server-Update erneut.';

  @override
  String get contacts_secure_directory_verification_failed_body =>
      'Das sichere Kontaktverzeichnis konnte nicht verifiziert werden. Zum Schutz deiner Privatsphäre wurde keine ältere Suchmethode verwendet.';

  @override
  String get contacts_sync_failed_body =>
      'Die Kontaktsynchronisierung konnte nicht abgeschlossen werden. Bestehende sichere Treffer auf diesem Gerät wurden nicht verändert; versuche es erneut.';

  @override
  String get clear_search => 'Suche löschen';

  @override
  String get conversations_archived_title => 'Archivierte Chats';

  @override
  String get conversations_no_results => 'Keine Ergebnisse gefunden';

  @override
  String get conversations_no_results_body =>
      'Versuche einen anderen Suchbegriff oder Filter.';

  @override
  String get conversations_empty_body =>
      'Verwende das Menü oben rechts, um einen neuen sicheren Chat zu starten.';

  @override
  String get conversation_typing => 'schreibt…';

  @override
  String get conversation_locked_preview => 'Dieser Chat ist ausgeblendet';

  @override
  String get conversations_messages_section => 'In Nachrichten';

  @override
  String get signaling_disconnected => 'Serververbindung getrennt';

  @override
  String get connected => 'Verbunden';

  @override
  String get chat_online => 'online';

  @override
  String chat_last_seen(String time) {
    return 'zuletzt gesehen $time';
  }

  @override
  String get chat_encryption_notice =>
      'Nachrichten sind Ende-zu-Ende verschlüsselt.';

  @override
  String get chat_today => 'Heute';

  @override
  String get chat_yesterday => 'Gestern';

  @override
  String get chat_pinned_message => 'Angeheftete Nachricht';

  @override
  String get chat_admins_only => 'Nur Admins können Nachrichten senden';

  @override
  String get chat_message_hint => 'Nachricht schreiben…';

  @override
  String get chat_scroll_bottom => 'Zur neuesten Nachricht';

  @override
  String get chat_you => 'Du';

  @override
  String get chat_edited => 'bearbeitet';

  @override
  String get chat_attachment_options => 'Anhangsoptionen';

  @override
  String get chat_empty_secure =>
      'In diesem sicheren Chat gibt es noch keine Nachrichten.';

  @override
  String get chat_previous_result => 'Vorheriges Ergebnis';

  @override
  String get chat_next_result => 'Nächstes Ergebnis';

  @override
  String get sending => 'Wird gesendet';

  @override
  String get return_to_call => 'Zum Anruf zurück';

  @override
  String get settings_open_source_licenses => 'Open-Source-Lizenzen';

  @override
  String get settings_open_source_licenses_desc =>
      'Sieh die in diesem Build enthaltenen Softwarelizenzen durch.';

  @override
  String get settings_about => 'Über';

  @override
  String get settings_about_desc => 'Version, Sicherheitshinweise und Lizenzen';

  @override
  String get about_security_title => 'Sicherheit';

  @override
  String get about_security_body =>
      'Nachrichten werden Ende-zu-Ende verschlüsselt, bevor sie das Gerät verlassen, und der Ratchet leitet für jede Nachricht einen neuen Nachrichtenschlüssel ab. Der Server speichert weder Klartext noch Gesprächsverlauf; ein nicht zugestellter verschlüsselter Umschlag kann nur in einer kurzlebigen RAM-Warteschlange verbleiben, bis er bestätigt wird oder abläuft. Die lokale Datenbank ist mit SQLCipher verschlüsselt.';

  @override
  String get about_version => 'Version';

  @override
  String get missed_call => 'Verpasster Anruf';

  @override
  String get missed_video_call => 'Verpasster Videoanruf';

  @override
  String get missed_voice_call => 'Verpasster Sprachanruf';

  @override
  String missed_call_from(Object peer) {
    return 'Von $peer';
  }

  @override
  String get missed_calls_channel => 'Verpasste Anrufe';

  @override
  String get missed_calls_channel_desc =>
      'Benachrichtigungen für unbeantwortete Anrufe';

  @override
  String get messages_channel => 'elçim Nachrichten';

  @override
  String get messages_channel_silent => 'elçim Nachrichten (stumm)';

  @override
  String get messages_channel_desc =>
      'Benachrichtigungen für eingehende sichere Nachrichten';

  @override
  String get messages_channel_silent_desc =>
      'Stummgeschaltete oder In-App-Nachrichten';

  @override
  String get security_number_changed =>
      'Die Sicherheitsnummer hat sich geändert. Diese Person hat die App möglicherweise neu installiert. Überprüfe die Identität im Zweifel über einen anderen Kanal.';

  @override
  String get security_message_unreadable =>
      'Eine Nachricht konnte nicht entschlüsselt werden und wird nicht angezeigt. Bitten Sie den Absender, sie erneut zu senden.';

  @override
  String get chat_jump_to_replied_message =>
      'Zur beantworteten Nachricht springen';

  @override
  String get contacts_empty_body =>
      'Ihre Kontakte werden nur per Hash abgeglichen. Wer elçim nutzt, erscheint hier.';

  @override
  String get calls_empty_body =>
      'Getätigte und empfangene Anrufe werden hier aufgelistet. Gesprächsinhalte werden nie aufgezeichnet.';

  @override
  String get group_unknown_member => 'Unbekanntes Mitglied';

  @override
  String get backup_passwords_match => 'Passwörter müssen übereinstimmen';

  @override
  String get sched_tab_history => 'Verlauf';

  @override
  String get sched_history_note =>
      'Gesendet bedeutet nicht, dass die Nachricht empfangen oder gelesen wurde.';

  @override
  String get sched_history_empty => 'Noch kein Sendeverlauf.';

  @override
  String get sched_history_locked => 'Inhalt eines gesperrten Chats';

  @override
  String get sched_history_sent => 'Gesendet';

  @override
  String get sched_history_partial_failure => 'Teilweise fehlgeschlagen';

  @override
  String get sched_history_failed => 'Senden fehlgeschlagen';

  @override
  String get sched_history_encryption_failed =>
      'Verschlüsselung fehlgeschlagen';

  @override
  String get sched_history_delivery_failed => 'Übertragung fehlgeschlagen';

  @override
  String get sched_history_details => 'Sendedetails';

  @override
  String get sched_history_executed_at => 'Sendezeit';

  @override
  String get sched_history_status => 'Status';

  @override
  String get sched_history_content_omitted =>
      'Der Inhalt wurde aus Datenschutzgründen nicht im Verlauf gespeichert.';

  @override
  String get storage_reload => 'Aktualisieren';

  @override
  String get storage_load_failed =>
      'Speicherinformationen konnten nicht geladen werden.';

  @override
  String get storage_filter => 'Dateien filtern';

  @override
  String get storage_all_files => 'Alle Dateien';

  @override
  String get storage_audio => 'Audio';

  @override
  String get storage_no_files =>
      'Keine Medien oder Dateien in dieser Kategorie.';

  @override
  String get storage_local_missing => 'Nicht auf diesem Gerät';

  @override
  String storage_delete_action(int arg1) {
    return 'Auswahl löschen ($arg1)';
  }

  @override
  String storage_delete_selected(int arg1) {
    return 'Die ausgewählten $arg1 Medien-/Dateinachrichten werden nur von diesem Gerät entfernt. Textnachrichten und Kopien anderer Personen bleiben erhalten. Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String storage_cleanup_result(int arg1, String arg2) {
    return '$arg1 Einträge entfernt · $arg2 freigegeben';
  }

  @override
  String storage_cleanup_failed(int arg1) {
    return '$arg1 Einträge konnten nicht entfernt werden. Andere Dateien wurden aktualisiert; bitte erneut versuchen.';
  }

  @override
  String get safety_block => 'Blockieren';

  @override
  String get safety_unblock => 'Blockierung aufheben';

  @override
  String get safety_block_confirm_title => 'Diesen Kontakt blockieren?';

  @override
  String get safety_block_confirm_body =>
      'Blockierte Kontakte können dich nicht mehr anrufen und dir keine Nachrichten senden. Sie werden nicht benachrichtigt.';

  @override
  String get safety_blocked_notice => 'Kontakt blockiert';

  @override
  String get safety_unblocked_notice => 'Blockierung aufgehoben';

  @override
  String get safety_blocked_banner =>
      'Du hast diesen Kontakt blockiert. Du kannst keine Nachrichten oder Anrufe senden oder empfangen.';

  @override
  String get safety_report => 'Melden';

  @override
  String get safety_report_group => 'Gruppe melden';

  @override
  String get safety_report_title => 'Warum meldest du?';

  @override
  String get safety_report_e2ee_note =>
      'Nachrichten sind Ende-zu-Ende-verschlüsselt. Deine Meldung enthält das Konto und den gewählten Grund, aber keine Nachrichteninhalte.';

  @override
  String get safety_reason_spam => 'Spam';

  @override
  String get safety_reason_harassment => 'Belästigung oder Mobbing';

  @override
  String get safety_reason_inappropriate => 'Unangemessene Inhalte';

  @override
  String get safety_reason_child_safety => 'Kinderschutz';

  @override
  String get safety_reason_impersonation => 'Identitätsbetrug';

  @override
  String get safety_reason_other => 'Sonstiges';

  @override
  String get safety_report_note_hint => 'Details hinzufügen (optional)';

  @override
  String get safety_report_also_block => 'Kontakt auch blockieren';

  @override
  String get safety_report_submit => 'Meldung senden';

  @override
  String get safety_report_sent =>
      'Meldung gesendet. Meldungen werden innerhalb von 24 Stunden geprüft.';

  @override
  String get safety_report_failed =>
      'Die Meldung konnte nicht gesendet werden. Versuche es erneut.';

  @override
  String get safety_blocked_contacts => 'Blockierte Kontakte';

  @override
  String get safety_blocked_contacts_empty => 'Keine blockierten Kontakte';

  @override
  String get legal_consent_notice =>
      'Mit dem Fortfahren akzeptierst du die Nutzungsbedingungen und die Datenschutzerklärung.';

  @override
  String get legal_terms => 'Nutzungsbedingungen';

  @override
  String get legal_privacy => 'Datenschutzerklärung';

  @override
  String get legal_child_safety => 'Kinderschutzstandards';

  @override
  String get legal_open_failed => 'Die Seite konnte nicht geöffnet werden.';
}
