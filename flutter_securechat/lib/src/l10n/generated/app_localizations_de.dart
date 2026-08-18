// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

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
  String get onboarding_subtitle => 'Secure messaging';

  @override
  String get onboarding_e2ee_notice =>
      'Your messages are end-to-end encrypted. No one can read them.';

  @override
  String get register_title => 'Sign Up';

  @override
  String get register_subtitle => 'Enter your details to get started.';

  @override
  String get register_name_label => 'Your name';

  @override
  String get register_name_placeholder => 'e.g. John Smith';

  @override
  String get register_country_code_label => 'Code';

  @override
  String get register_phone_label => 'Phone number';

  @override
  String get register_phone_placeholder => '5XX XXX XX XX';

  @override
  String get register_start => 'Start';

  @override
  String get contacts_permission_title => 'Contacts Access Required';

  @override
  String get contacts_permission_body =>
      'Contacts access is required for the app to work. Please grant the contacts permission so we can find your contacts and enable secure messaging.';

  @override
  String get action_retry => 'Try Again';

  @override
  String get validation_name_empty => 'Enter your name';

  @override
  String validation_name_too_short(num arg1) {
    return 'At least $arg1 characters';
  }

  @override
  String validation_name_too_long(num arg1) {
    return 'At most $arg1 characters';
  }

  @override
  String get validation_name_invalid_chars =>
      'Letters, spaces, hyphens and apostrophes only';

  @override
  String get validation_country_code_empty => 'Country code empty';

  @override
  String get validation_country_code_missing_plus => 'Must start with +';

  @override
  String get validation_country_code_non_digit => 'Digits only';

  @override
  String get validation_country_code_too_short => 'At least 1 digit';

  @override
  String get validation_country_code_too_long => 'At most 4 digits';

  @override
  String get validation_phone_empty => 'Enter your phone number';

  @override
  String get validation_phone_too_short => '10 digits required';

  @override
  String get validation_phone_too_long => '10 digits only';

  @override
  String get validation_phone_non_digit => 'Digits only';

  @override
  String get otp_title => 'Verification';

  @override
  String get otp_section_title => 'Verification Code';

  @override
  String otp_description(String arg1) {
    return 'Enter the 6-digit code sent\\nto $arg1';
  }

  @override
  String get otp_incomplete_error => 'Please enter all 6 digits';

  @override
  String get otp_resend => 'Resend Code';

  @override
  String otp_resend_countdown(num arg1) {
    return 'Resend code: ${arg1}s';
  }

  @override
  String get otp_verify => 'Verify';

  @override
  String get backup_prompt_title => 'Do you have an existing backup?';

  @override
  String get backup_prompt_body =>
      'If you previously created an encrypted backup, you can restore your chats.';

  @override
  String get backup_prompt_yes => 'Yes, restore backup';

  @override
  String get backup_prompt_no => 'No, start fresh';

  @override
  String get nav_back => 'Back';

  @override
  String get email_otp_title => 'Email Verification';

  @override
  String get email_otp_step_email => 'Your email address';

  @override
  String get email_otp_step_code => 'Verification code';

  @override
  String get email_otp_description_email =>
      'Enter your email address to verify your account. We will send the code to your email.';

  @override
  String email_otp_description_code(String arg1) {
    return 'Enter the 6-digit code sent to $arg1.';
  }

  @override
  String get email_otp_email_label => 'Email';

  @override
  String get email_otp_code_label => '6-digit code';

  @override
  String get email_otp_send => 'Send Code';

  @override
  String get email_otp_change_email => 'Use a different email';

  @override
  String get email_otp_dev_skip => 'Development Mode — Skip';

  @override
  String get email_otp_invalid_email => 'Enter a valid email';

  @override
  String get email_otp_sent => 'Code sent to your email';

  @override
  String get email_otp_smtp_disabled =>
      'Email service is not configured on the server. Please contact your administrator or use Skip in development mode.';

  @override
  String get email_otp_rate_limited =>
      'Too many attempts. Please wait a few minutes.';

  @override
  String email_otp_send_error(String arg1) {
    return 'Failed to send code: $arg1';
  }

  @override
  String get email_otp_verify_failed => 'Code invalid or expired';

  @override
  String get email_otp_incomplete => 'Enter all 6 digits';

  @override
  String get create_group_title => 'New Group';

  @override
  String get create_group_action => 'Create';

  @override
  String create_group_selected_members(num arg1) {
    return 'Selected Members ($arg1)';
  }

  @override
  String get create_group_add_by_phone => 'Add by Number';

  @override
  String get create_group_user_not_found => 'User Not Found';

  @override
  String get create_group_send_invite => 'Send Invite';

  @override
  String get create_group_close => 'Close';

  @override
  String get create_group_registered_contacts => 'Registered Contacts';

  @override
  String get create_group_search_placeholder => 'Search contacts…';

  @override
  String get invite_chooser_title => 'Send invitation';

  @override
  String get cd_remove => 'Remove';

  @override
  String get cd_search => 'Search';

  @override
  String get cd_clear => 'Clear';

  @override
  String get cd_add => 'Add';

  @override
  String get cd_more => 'More';

  @override
  String get cd_connection_status => 'Connection status';

  @override
  String get cd_new_chat_action => 'Start chat';

  @override
  String get cd_member_actions => 'Member actions';

  @override
  String get network_error_title => 'Connection Error';

  @override
  String get contacts_grant_permission => 'Grant Contacts Access';

  @override
  String get contacts_invite_short => 'Invite';

  @override
  String get settings_title => 'Settings';

  @override
  String get settings_nuke_dialog_title => 'Delete All Chats';

  @override
  String get settings_nuke_dialog_body =>
      'All chats and messages will be permanently deleted. This cannot be undone.';

  @override
  String get settings_nuke_confirm => 'Delete';

  @override
  String get settings_nuke_backup_first => 'Back Up First';

  @override
  String get settings_nuke_all_data_warning =>
      'All your messages, contacts and settings will be deleted.';

  @override
  String get settings_nuke_type_to_confirm => 'Type \\\"DELETE\\\" to confirm:';

  @override
  String get settings_nuke_type_placeholder => 'DELETE';

  @override
  String get settings_chat_theme => 'Chat Theme';

  @override
  String get settings_language => 'Language';

  @override
  String get settings_backdrop => 'Backdrop Pattern';

  @override
  String get settings_fullscreen => 'Fullscreen Mode';

  @override
  String get settings_show_message_preview => 'Show message content';

  @override
  String get settings_notification_sound => 'Notification Sound';

  @override
  String get settings_incoming_call_screen => 'Incoming call screen';

  @override
  String get settings_missed_call => 'Missed call alerts';

  @override
  String get settings_battery_optimization => 'Battery optimization';

  @override
  String get settings_scheduled_messages => 'Scheduled Messages';

  @override
  String get settings_manage_scheduled => 'Manage Scheduled Messages';

  @override
  String get settings_manage_scheduled_desc =>
      'View and edit existing scheduled messages';

  @override
  String get settings_e2ee => 'End-to-end encryption';

  @override
  String get settings_e2ee_desc =>
      'Your messages are encrypted with Signal Protocol';

  @override
  String get settings_last_seen => 'Last seen time';

  @override
  String get settings_message_storage => 'Message Storage Policy';

  @override
  String get settings_message_storage_desc =>
      'Messages are stored on this device only';

  @override
  String get settings_backup => 'Backup';

  @override
  String get settings_backup_desc => 'Back up chats encrypted or restore';

  @override
  String get settings_storage_usage => 'Storage Usage';

  @override
  String get chat_info_note_label => 'Note';

  @override
  String get chat_info_search_placeholder => 'Search messages…';

  @override
  String get conv_new_chat => 'New Chat';

  @override
  String get conv_new_group => 'New Group';

  @override
  String get conv_bulk_message => 'Bulk Message';

  @override
  String get conv_scheduled_messages => 'Scheduled Messages';

  @override
  String get conv_filter_all => 'All';

  @override
  String get conv_filter_unread => 'Unread';

  @override
  String get conv_filter_groups => 'Groups';

  @override
  String get conv_filter_favorites => 'Favorites';

  @override
  String get conv_archive => 'Archive';

  @override
  String get conv_delete => 'Delete';

  @override
  String get conv_info => 'Info';

  @override
  String get conv_delete_chat => 'Delete Chat';

  @override
  String get group_view_profile => 'View Profile';

  @override
  String get group_leave => 'Leave Group';

  @override
  String get chat_search_in_chat => 'Search in Chat';

  @override
  String get chat_export => 'Export Chat';

  @override
  String get action_close => 'Close';

  @override
  String get chat_custom_duration => 'Custom Duration';

  @override
  String get msg_action_reply => 'Reply';

  @override
  String get msg_action_copy => 'Copy';

  @override
  String get msg_action_edit => 'Edit';

  @override
  String get msg_action_edit_history => 'Edit History';

  @override
  String get msg_action_info => 'Info';

  @override
  String get msg_action_forward => 'Forward';

  @override
  String get msg_action_delete_for_me => 'Delete for me';

  @override
  String get msg_delete_title => 'Delete message';

  @override
  String get msg_delete_cancel => 'Discard';

  @override
  String get msg_edit_title => 'Edit Message';

  @override
  String get sched_title => 'Scheduled Messages';

  @override
  String get sched_delete_title => 'Delete Scheduled Message';

  @override
  String get sched_delete_body =>
      'This scheduled message will be permanently deleted.';

  @override
  String get sched_tab_create => 'Create';

  @override
  String get sched_tab_existing => 'Existing';

  @override
  String get sched_message_placeholder => 'Type your message…';

  @override
  String get sched_action_edit => 'Edit';

  @override
  String get sched_action_delete => 'Delete';

  @override
  String get sched_pick_time => 'Pick Time';

  @override
  String get sched_pick_day => 'Pick Day';

  @override
  String get sched_pick_recipient => 'Pick Recipient';

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
  String get settings_share_last_seen => 'Zuletzt online teilen';

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
  String get group_not_found => 'Group not found.';

  @override
  String get group_admin_only => 'Only admins can send messages';

  @override
  String get group_announcement_desc =>
      'Use the group as an announcement channel';

  @override
  String get mute => 'Mute';

  @override
  String get chat_lock => 'Chat lock';

  @override
  String get chat_lock_desc => 'Access with device authentication';

  @override
  String get export_history => 'Export history';

  @override
  String get make_admin => 'Make admin';

  @override
  String get no_contacts_to_add => 'No saved contacts can be added.';

  @override
  String get confirmation => 'Confirmation';

  @override
  String get confirm => 'Confirm';

  @override
  String get background_unavailable => 'Background service is unavailable.';

  @override
  String get storage_service_unavailable => 'Storage service is unavailable.';

  @override
  String get edit_mode => 'Edit mode';

  @override
  String get repeat_once => 'Once';

  @override
  String get repeat_daily => 'Daily';

  @override
  String get repeat_custom => 'Custom';

  @override
  String get weekdays_short => 'Mon,Tue,Wed,Thu,Fri,Sat,Sun';

  @override
  String get delivery_time => 'Delivery time';

  @override
  String get message_content => 'Message content';

  @override
  String get recipients => 'Recipients';

  @override
  String get recipient_required => 'Select at least one person or group';

  @override
  String get schedule => 'Schedule';

  @override
  String get update => 'Update';

  @override
  String get no_scheduled_messages => 'No scheduled messages yet.';

  @override
  String get schedule_saved => 'Scheduled message saved.';

  @override
  String get form_incomplete => 'The form is incomplete.';

  @override
  String get over_wifi => 'Over Wi-Fi';

  @override
  String get over_cellular => 'Over cellular data';

  @override
  String get photos => 'Photos';

  @override
  String get videos => 'Videos';

  @override
  String get documents => 'Documents';

  @override
  String cellular_limit(num arg1) {
    return 'Cellular limit: $arg1 MB';
  }

  @override
  String get no_chats_yet => 'No chats yet';

  @override
  String storage_summary(num arg1, num arg2, String arg3) {
    return '$arg1 messages · $arg2 files · $arg3';
  }

  @override
  String get clear_media => 'Clear media';

  @override
  String clear_media_body(String arg1) {
    return 'Media and file messages in “$arg1” will be deleted. Text messages are retained.';
  }

  @override
  String get no_exports_yet => 'No exports yet';

  @override
  String message_count(num arg1) {
    return '$arg1 messages';
  }

  @override
  String get entire_chat => 'Entire chat';

  @override
  String get admin_only_screen =>
      'This screen is available only to group admins';

  @override
  String get bulk_unavailable => 'Bulk sending is unavailable.';

  @override
  String get select_all => 'Select all';

  @override
  String get group => 'Group';

  @override
  String send_to_recipients(num arg1) {
    return 'Send to $arg1 recipients';
  }

  @override
  String bulk_result(num arg1, num arg2) {
    return '$arg1 sent, $arg2 failed.';
  }

  @override
  String get encrypted_backup => 'Encrypted Backup';

  @override
  String get backup_explanation =>
      'Chats, contacts, call logs, scheduled messages and end-to-end encryption state are stored in a password-protected .elbk file. Session access keys are excluded.';

  @override
  String get create_backup => 'Create a new backup';

  @override
  String get restore_backup_file => 'Restore a backup file';

  @override
  String get backups_on_device => 'Backups on this device';

  @override
  String get no_local_backups => 'No local backups yet';

  @override
  String get backup_password => 'Backup password';

  @override
  String get backup_unavailable => 'Backup service is unavailable.';

  @override
  String get save_encrypted_backup => 'Save encrypted backup';

  @override
  String get backup_created => 'Encrypted backup created.';

  @override
  String backup_create_failed(String arg1) {
    return 'Could not create backup: $arg1';
  }

  @override
  String get backup_restored => 'Backup restored.';

  @override
  String wrong_password_attempts(num arg1) {
    return 'Wrong password. $arg1 attempts remaining.';
  }

  @override
  String get backup_deleted_after_attempts =>
      'The backup file was deleted after five incorrect attempts.';

  @override
  String get backup_delete_failed_after_attempts =>
      'Attempt limit reached; the platform could not delete the file.';

  @override
  String get password => 'Password';

  @override
  String get password_min_length => 'At least 8 characters';

  @override
  String get password_repeat => 'Repeat password';

  @override
  String get password_too_short => 'Password must be at least 8 characters.';

  @override
  String get password_mismatch => 'Passwords do not match.';

  @override
  String get restore => 'Restore';

  @override
  String get no_call_history => 'No call history yet.';

  @override
  String get video_call => 'Video call';

  @override
  String get voice_call => 'Voice call';

  @override
  String get outgoing => 'Outgoing';

  @override
  String get incoming => 'Incoming';

  @override
  String get video => 'video';

  @override
  String get voice => 'voice';

  @override
  String get missed => 'Missed';

  @override
  String get rejected => 'Rejected';

  @override
  String get busy => 'Busy';

  @override
  String get failed => 'Failed';

  @override
  String call_description(String arg1, String arg2, String arg3) {
    return '$arg1 $arg2 call$arg3';
  }

  @override
  String get recheck_status => 'Check status again';

  @override
  String get calls_ready => 'You are ready for calls';

  @override
  String get calls_readiness_missing =>
      'Complete missing items to prevent call delays';

  @override
  String get battery_optimization_desc =>
      'Reduces Doze delays for data-only push and background work';

  @override
  String get fullscreen_call_notification => 'Full-screen call notification';

  @override
  String get fullscreen_call_notification_desc =>
      'Android 14+ lock-screen call view';

  @override
  String get notification_permission => 'Notification permission';

  @override
  String get notification_permission_desc =>
      'Message and incoming call notifications';

  @override
  String get overlay_permission => 'Display over other apps';

  @override
  String get overlay_permission_desc => 'Android background call screen';

  @override
  String get ios_call_readiness_note =>
      'On iOS, battery optimization, full-screen intent and overlay cannot be changed by the app. Incoming-call wake-up depends on APNs/CallKit and system policies.';

  @override
  String get secure_communication => 'Secure Communication';

  @override
  String get onboarding_private_subtitle => 'Your messages stay between you';

  @override
  String get onboarding_private_body =>
      'Every message is encrypted on your device; the server cannot read its content.';

  @override
  String get onboarding_direct_call => 'Direct calls';

  @override
  String get onboarding_webrtc_subtitle => 'Voice and video over WebRTC';

  @override
  String get onboarding_webrtc_body =>
      'One-to-one calls connect directly; large group calls use the Janus SFU.';

  @override
  String get onboarding_privacy_control => 'Complete privacy control';

  @override
  String get onboarding_you_decide => 'You decide';

  @override
  String get onboarding_privacy_body =>
      'View once, disappearing messages, screen protection and group export policy.';

  @override
  String get skip => 'Skip';

  @override
  String get lets_start => 'Get started';

  @override
  String get continue_action => 'Continue';

  @override
  String get notifications => 'Notifications';

  @override
  String get notifications_permission_reason => 'For new messages and calls.';

  @override
  String get contacts_permission_reason =>
      'To discover people using hashes only.';

  @override
  String get microphone => 'Microphone';

  @override
  String get microphone_permission_reason => 'For voice and video calls.';

  @override
  String get camera_permission_reason => 'For video calls.';

  @override
  String get permissions_required => 'A few permissions are required';

  @override
  String get permissions_intro =>
      'Grant the permissions you want now; you can enable the rest later in settings.';

  @override
  String get grant_permission => 'Grant permission';

  @override
  String get chat_not_found => 'Chat not found.';

  @override
  String get contact_info => 'Contact Info';

  @override
  String get starred_messages => 'Starred Messages';

  @override
  String get media => 'Media';

  @override
  String get disappearing_messages => 'Disappearing messages';

  @override
  String get contact_note => 'Contact note';

  @override
  String get tap_to_add_note => 'Tap to add a note';

  @override
  String get no_records => 'No records found';

  @override
  String get add_contact_note => 'Add contact note';

  @override
  String get off => 'Off';

  @override
  String hours(num arg1) {
    return '$arg1 hours';
  }

  @override
  String days(num arg1) {
    return '$arg1 days';
  }

  @override
  String files_selected(num arg1) {
    return '$arg1 files selected';
  }

  @override
  String get add_caption => 'Add a caption...';

  @override
  String get view_once => 'View once';

  @override
  String get view_once_protected => 'View once · screen protected';

  @override
  String get share => 'Share';

  @override
  String get tap_to_close_view_once => 'Tap to close · cannot be opened again';

  @override
  String file_open_failed(String arg1) {
    return 'Could not open file: $arg1';
  }

  @override
  String file_share_failed(String arg1) {
    return 'Could not share file: $arg1';
  }

  @override
  String get file => 'File';

  @override
  String get open_with_app => 'Open with app';

  @override
  String get media_not_found => 'Media file not found';

  @override
  String get call_service_unavailable => 'Call service could not be started.';

  @override
  String get locked_chat => 'Locked Chat';

  @override
  String get disable_export => 'Disable export';

  @override
  String get enable_export => 'Enable export';

  @override
  String get clear_chat => 'Clear chat';

  @override
  String get read_only_announcement =>
      'This group is an announcement channel where only admins can post.';

  @override
  String get no_matching_messages => 'No matching messages found';

  @override
  String get cancel_selection => 'Cancel selection';

  @override
  String messages_selected(num arg1) {
    return '$arg1 messages selected';
  }

  @override
  String get forward_selected => 'Forward selected';

  @override
  String get record_voice_message => 'Record voice message';

  @override
  String get poll => 'Poll';

  @override
  String get add_reaction => 'Add reaction';

  @override
  String get remove_star => 'Remove star';

  @override
  String get add_star => 'Star';

  @override
  String get unpin => 'Unpin';

  @override
  String get pin => 'Pin';

  @override
  String get choose_reaction => 'Choose reaction';

  @override
  String get delete_for_everyone => 'Delete for everyone';

  @override
  String get clear_chat_confirm => 'Clear this chat?';

  @override
  String get clear_chat_body =>
      'All messages on this device will be permanently deleted.';

  @override
  String get voice_message => 'Voice message';

  @override
  String get recording_start_failed => 'Could not start recording';

  @override
  String get recording_paused => 'Recording paused';

  @override
  String get recording_active => 'Recording';

  @override
  String get send => 'Send';

  @override
  String get poll_load_failed => 'Could not load poll';

  @override
  String get single_choice => 'Single choice';

  @override
  String get multiple_choice => 'Multiple choice';

  @override
  String total_votes(num arg1) {
    return '$arg1 total votes';
  }

  @override
  String get message_info => 'Message Info';

  @override
  String get sent => 'Sent';

  @override
  String get read => 'Read';

  @override
  String get delivered => 'Delivered';

  @override
  String get send_failed_no_plaintext =>
      'Sending failed. Plaintext fallback was not used.';

  @override
  String get forward_to_chat => 'Forward to chat';

  @override
  String get read_only_chat => 'Read-only chat';

  @override
  String participant_count(num arg1) {
    return '$arg1 participants';
  }

  @override
  String get create_poll => 'Create Poll';

  @override
  String get question => 'Question';

  @override
  String option_number(num arg1) {
    return 'Option $arg1';
  }

  @override
  String get add_option => 'Add option';

  @override
  String get member_export_permission => 'Members may copy and export';

  @override
  String get admin_change_only => 'Only an admin can change this';

  @override
  String remove_member_named(String arg1) {
    return 'Remove $arg1 from the group?';
  }

  @override
  String get leave_group_confirm => 'Do you want to leave this group?';

  @override
  String get archive => 'Archive';

  @override
  String get remove_favorite => 'Remove from favorites';

  @override
  String get add_favorite => 'Add to favorites';

  @override
  String get mark_read => 'Mark as read';

  @override
  String get mark_unread => 'Mark as unread';

  @override
  String delete_chat_body(String arg1) {
    return 'Permanently delete the $arg1 chat and its messages from this device?';
  }

  @override
  String get reject => 'Reject';

  @override
  String get answer => 'Answer';

  @override
  String get unmute => 'Unmute';

  @override
  String get speaker => 'Speaker';

  @override
  String get flip_camera => 'Flip';

  @override
  String get end_call => 'End';

  @override
  String get call_preparing => 'Preparing call…';

  @override
  String get incoming_call => 'Incoming call';

  @override
  String get ringing => 'Ringing…';

  @override
  String get connecting => 'Connecting…';

  @override
  String get reconnecting => 'Reconnecting…';

  @override
  String get weak_connection_disable_video =>
      'Weak connection — turn off video and continue with audio';

  @override
  String get call_ended => 'Call ended';

  @override
  String get call_rejected => 'Call rejected';

  @override
  String get connection_failed => 'Could not connect';

  @override
  String get voice_service_unavailable =>
      'Voice message service could not be started.';

  @override
  String get voice_encrypting => 'Encrypting and sending voice message…';

  @override
  String get voice_sent => 'Voice message sent.';

  @override
  String voice_send_failed(String arg1) {
    return 'Could not send voice message: $arg1';
  }

  @override
  String get file_transfer_unavailable =>
      'File transfer service could not be started.';

  @override
  String media_pick_failed(String arg1) {
    return 'Could not select media: $arg1';
  }

  @override
  String get media_encrypting => 'Encrypting and sending media…';

  @override
  String media_send_failed(String arg1) {
    return 'Could not send media: $arg1';
  }

  @override
  String media_sent(num arg1) {
    return '$arg1 media items sent encrypted.';
  }

  @override
  String media_failed(num arg1, String arg2) {
    return '$arg1 media items failed: $arg2';
  }

  @override
  String get poll_unavailable => 'Poll service is unavailable.';

  @override
  String get poll_sent => 'Poll sent.';

  @override
  String get poll_send_failed => 'Could not send poll.';

  @override
  String get vote_send_failed => 'Vote could not be sent securely.';

  @override
  String get pin_failed => 'No pin permission or signaling failed.';

  @override
  String get forward_service_unavailable =>
      'Message forwarding service could not start.';

  @override
  String forward_encrypting(num arg1, String arg2) {
    return 'Re-encrypting $arg1 messages for $arg2…';
  }

  @override
  String forward_encryption_result(num arg1, num arg2) {
    return '$arg1 messages forwarded; $arg2 could not be encrypted and were not sent.';
  }

  @override
  String forward_sent(num arg1) {
    return '$arg1 messages forwarded.';
  }

  @override
  String forward_partial(num arg1, num arg2) {
    return '$arg1 messages forwarded; $arg2 failed.';
  }

  @override
  String get reaction_failed => 'Could not send reaction.';

  @override
  String get edit_failed => 'Could not edit message.';

  @override
  String get delete_signal_failed => 'Could not send deletion signal.';

  @override
  String get export_unavailable => 'Export is unavailable.';

  @override
  String get chat_exported => 'Chat exported.';

  @override
  String get group_policy_unavailable => 'Group policy is unavailable.';

  @override
  String get export_disabled => 'Export disabled.';

  @override
  String get export_enabled => 'Export enabled.';

  @override
  String get chat_unmuted => 'Chat unmuted.';

  @override
  String get chat_muted => 'Chat muted.';

  @override
  String get invalid_voice_recording =>
      'A valid voice recording could not be created.';

  @override
  String get audio_not_found => 'Audio file not found';

  @override
  String get audio_play_failed => 'Could not play voice recording';

  @override
  String get opened => 'Opened';

  @override
  String get view_once_photo => 'View-once photo';

  @override
  String get media_no_longer_available => 'This media can no longer be opened';

  @override
  String get tap_to_open => 'Tap to open';

  @override
  String get attachment => 'Add attachment';

  @override
  String get dialpad => 'Open dial pad';

  @override
  String get remove_option => 'Remove option';

  @override
  String get auth_unavailable => 'Authentication service is not configured.';

  @override
  String rate_limit_seconds(num arg1) {
    return 'Too many requests. Wait $arg1 seconds.';
  }

  @override
  String get chat_cleared => 'Chat cleared.';

  @override
  String get no_registered_contacts =>
      'No registered contacts found. Grant contacts permission and refresh.';

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
  String get settings_open_source_licenses => 'Open-source licenses';

  @override
  String get settings_open_source_licenses_desc =>
      'Review the software licenses included in this build.';
}
