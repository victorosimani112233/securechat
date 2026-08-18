import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('tr'),
  ];

  /// No description provided for @app_name.
  ///
  /// In en, this message translates to:
  /// **'ELÇİM'**
  String get app_name;

  /// No description provided for @group_info.
  ///
  /// In en, this message translates to:
  /// **'Group Info'**
  String get group_info;

  /// No description provided for @group_settings.
  ///
  /// In en, this message translates to:
  /// **'Group Settings'**
  String get group_settings;

  /// No description provided for @add_member.
  ///
  /// In en, this message translates to:
  /// **'Add Member'**
  String get add_member;

  /// Migrated from Android string members_count.
  ///
  /// In en, this message translates to:
  /// **'Members ({arg1})'**
  String members_count(num arg1);

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @remove_member.
  ///
  /// In en, this message translates to:
  /// **'Remove Member'**
  String get remove_member;

  /// No description provided for @remove_from_group.
  ///
  /// In en, this message translates to:
  /// **'Remove from Group'**
  String get remove_from_group;

  /// No description provided for @edit_group_name.
  ///
  /// In en, this message translates to:
  /// **'Edit Group Name'**
  String get edit_group_name;

  /// No description provided for @group_name.
  ///
  /// In en, this message translates to:
  /// **'Group Name'**
  String get group_name;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @add_new_member.
  ///
  /// In en, this message translates to:
  /// **'Add New Member'**
  String get add_new_member;

  /// No description provided for @user_id.
  ///
  /// In en, this message translates to:
  /// **'User ID'**
  String get user_id;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @remove_member_confirm.
  ///
  /// In en, this message translates to:
  /// **'Remove Member'**
  String get remove_member_confirm;

  /// Migrated from Android string remove_member_message.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to remove {arg1} from the group?'**
  String remove_member_message(String arg1);

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @view_info.
  ///
  /// In en, this message translates to:
  /// **'View Info'**
  String get view_info;

  /// No description provided for @onboarding_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Secure messaging'**
  String get onboarding_subtitle;

  /// No description provided for @onboarding_e2ee_notice.
  ///
  /// In en, this message translates to:
  /// **'Your messages are end-to-end encrypted. No one can read them.'**
  String get onboarding_e2ee_notice;

  /// No description provided for @register_title.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get register_title;

  /// No description provided for @register_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your details to get started.'**
  String get register_subtitle;

  /// No description provided for @register_name_label.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get register_name_label;

  /// No description provided for @register_name_placeholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. John Smith'**
  String get register_name_placeholder;

  /// No description provided for @register_country_code_label.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get register_country_code_label;

  /// No description provided for @register_phone_label.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get register_phone_label;

  /// No description provided for @register_phone_placeholder.
  ///
  /// In en, this message translates to:
  /// **'5XX XXX XX XX'**
  String get register_phone_placeholder;

  /// No description provided for @register_start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get register_start;

  /// No description provided for @contacts_permission_title.
  ///
  /// In en, this message translates to:
  /// **'Contacts Access Required'**
  String get contacts_permission_title;

  /// No description provided for @contacts_permission_body.
  ///
  /// In en, this message translates to:
  /// **'Contacts access is required for the app to work. Please grant the contacts permission so we can find your contacts and enable secure messaging.'**
  String get contacts_permission_body;

  /// No description provided for @action_retry.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get action_retry;

  /// No description provided for @validation_name_empty.
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get validation_name_empty;

  /// Migrated from Android string validation_name_too_short.
  ///
  /// In en, this message translates to:
  /// **'At least {arg1} characters'**
  String validation_name_too_short(num arg1);

  /// Migrated from Android string validation_name_too_long.
  ///
  /// In en, this message translates to:
  /// **'At most {arg1} characters'**
  String validation_name_too_long(num arg1);

  /// No description provided for @validation_name_invalid_chars.
  ///
  /// In en, this message translates to:
  /// **'Letters, spaces, hyphens and apostrophes only'**
  String get validation_name_invalid_chars;

  /// No description provided for @validation_country_code_empty.
  ///
  /// In en, this message translates to:
  /// **'Country code empty'**
  String get validation_country_code_empty;

  /// No description provided for @validation_country_code_missing_plus.
  ///
  /// In en, this message translates to:
  /// **'Must start with +'**
  String get validation_country_code_missing_plus;

  /// No description provided for @validation_country_code_non_digit.
  ///
  /// In en, this message translates to:
  /// **'Digits only'**
  String get validation_country_code_non_digit;

  /// No description provided for @validation_country_code_too_short.
  ///
  /// In en, this message translates to:
  /// **'At least 1 digit'**
  String get validation_country_code_too_short;

  /// No description provided for @validation_country_code_too_long.
  ///
  /// In en, this message translates to:
  /// **'At most 4 digits'**
  String get validation_country_code_too_long;

  /// No description provided for @validation_phone_empty.
  ///
  /// In en, this message translates to:
  /// **'Enter your phone number'**
  String get validation_phone_empty;

  /// No description provided for @validation_phone_too_short.
  ///
  /// In en, this message translates to:
  /// **'10 digits required'**
  String get validation_phone_too_short;

  /// No description provided for @validation_phone_too_long.
  ///
  /// In en, this message translates to:
  /// **'10 digits only'**
  String get validation_phone_too_long;

  /// No description provided for @validation_phone_non_digit.
  ///
  /// In en, this message translates to:
  /// **'Digits only'**
  String get validation_phone_non_digit;

  /// No description provided for @otp_title.
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get otp_title;

  /// No description provided for @otp_section_title.
  ///
  /// In en, this message translates to:
  /// **'Verification Code'**
  String get otp_section_title;

  /// Migrated from Android string otp_description.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code sent\\nto {arg1}'**
  String otp_description(String arg1);

  /// No description provided for @otp_incomplete_error.
  ///
  /// In en, this message translates to:
  /// **'Please enter all 6 digits'**
  String get otp_incomplete_error;

  /// No description provided for @otp_resend.
  ///
  /// In en, this message translates to:
  /// **'Resend Code'**
  String get otp_resend;

  /// Migrated from Android string otp_resend_countdown.
  ///
  /// In en, this message translates to:
  /// **'Resend code: {arg1}s'**
  String otp_resend_countdown(num arg1);

  /// No description provided for @otp_verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get otp_verify;

  /// No description provided for @backup_prompt_title.
  ///
  /// In en, this message translates to:
  /// **'Do you have an existing backup?'**
  String get backup_prompt_title;

  /// No description provided for @backup_prompt_body.
  ///
  /// In en, this message translates to:
  /// **'If you previously created an encrypted backup, you can restore your chats.'**
  String get backup_prompt_body;

  /// No description provided for @backup_prompt_yes.
  ///
  /// In en, this message translates to:
  /// **'Yes, restore backup'**
  String get backup_prompt_yes;

  /// No description provided for @backup_prompt_no.
  ///
  /// In en, this message translates to:
  /// **'No, start fresh'**
  String get backup_prompt_no;

  /// No description provided for @nav_back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get nav_back;

  /// No description provided for @email_otp_title.
  ///
  /// In en, this message translates to:
  /// **'Email Verification'**
  String get email_otp_title;

  /// No description provided for @email_otp_step_email.
  ///
  /// In en, this message translates to:
  /// **'Your email address'**
  String get email_otp_step_email;

  /// No description provided for @email_otp_step_code.
  ///
  /// In en, this message translates to:
  /// **'Verification code'**
  String get email_otp_step_code;

  /// No description provided for @email_otp_description_email.
  ///
  /// In en, this message translates to:
  /// **'Enter your email address to verify your account. We will send the code to your email.'**
  String get email_otp_description_email;

  /// Migrated from Android string email_otp_description_code.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code sent to {arg1}.'**
  String email_otp_description_code(String arg1);

  /// No description provided for @email_otp_email_label.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email_otp_email_label;

  /// No description provided for @email_otp_code_label.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get email_otp_code_label;

  /// No description provided for @email_otp_send.
  ///
  /// In en, this message translates to:
  /// **'Send Code'**
  String get email_otp_send;

  /// No description provided for @email_otp_change_email.
  ///
  /// In en, this message translates to:
  /// **'Use a different email'**
  String get email_otp_change_email;

  /// No description provided for @email_otp_dev_skip.
  ///
  /// In en, this message translates to:
  /// **'Development Mode — Skip'**
  String get email_otp_dev_skip;

  /// No description provided for @email_otp_invalid_email.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get email_otp_invalid_email;

  /// No description provided for @email_otp_sent.
  ///
  /// In en, this message translates to:
  /// **'Code sent to your email'**
  String get email_otp_sent;

  /// No description provided for @email_otp_smtp_disabled.
  ///
  /// In en, this message translates to:
  /// **'Email service is not configured on the server. Please contact your administrator or use \'Skip\' in development mode.'**
  String get email_otp_smtp_disabled;

  /// No description provided for @email_otp_rate_limited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a few minutes.'**
  String get email_otp_rate_limited;

  /// Migrated from Android string email_otp_send_error.
  ///
  /// In en, this message translates to:
  /// **'Failed to send code: {arg1}'**
  String email_otp_send_error(String arg1);

  /// No description provided for @email_otp_verify_failed.
  ///
  /// In en, this message translates to:
  /// **'Code invalid or expired'**
  String get email_otp_verify_failed;

  /// No description provided for @email_otp_incomplete.
  ///
  /// In en, this message translates to:
  /// **'Enter all 6 digits'**
  String get email_otp_incomplete;

  /// No description provided for @create_group_title.
  ///
  /// In en, this message translates to:
  /// **'New Group'**
  String get create_group_title;

  /// No description provided for @create_group_action.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create_group_action;

  /// Migrated from Android string create_group_selected_members.
  ///
  /// In en, this message translates to:
  /// **'Selected Members ({arg1})'**
  String create_group_selected_members(num arg1);

  /// No description provided for @create_group_add_by_phone.
  ///
  /// In en, this message translates to:
  /// **'Add by Number'**
  String get create_group_add_by_phone;

  /// No description provided for @create_group_user_not_found.
  ///
  /// In en, this message translates to:
  /// **'User Not Found'**
  String get create_group_user_not_found;

  /// No description provided for @create_group_send_invite.
  ///
  /// In en, this message translates to:
  /// **'Send Invite'**
  String get create_group_send_invite;

  /// No description provided for @create_group_close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get create_group_close;

  /// No description provided for @create_group_registered_contacts.
  ///
  /// In en, this message translates to:
  /// **'Registered Contacts'**
  String get create_group_registered_contacts;

  /// No description provided for @create_group_search_placeholder.
  ///
  /// In en, this message translates to:
  /// **'Search contacts…'**
  String get create_group_search_placeholder;

  /// No description provided for @invite_chooser_title.
  ///
  /// In en, this message translates to:
  /// **'Send invitation'**
  String get invite_chooser_title;

  /// No description provided for @cd_remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get cd_remove;

  /// No description provided for @cd_search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get cd_search;

  /// No description provided for @cd_clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get cd_clear;

  /// No description provided for @cd_add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get cd_add;

  /// No description provided for @cd_more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get cd_more;

  /// No description provided for @cd_connection_status.
  ///
  /// In en, this message translates to:
  /// **'Connection status'**
  String get cd_connection_status;

  /// No description provided for @cd_new_chat_action.
  ///
  /// In en, this message translates to:
  /// **'Start chat'**
  String get cd_new_chat_action;

  /// No description provided for @cd_member_actions.
  ///
  /// In en, this message translates to:
  /// **'Member actions'**
  String get cd_member_actions;

  /// No description provided for @network_error_title.
  ///
  /// In en, this message translates to:
  /// **'Connection Error'**
  String get network_error_title;

  /// No description provided for @contacts_grant_permission.
  ///
  /// In en, this message translates to:
  /// **'Grant Contacts Access'**
  String get contacts_grant_permission;

  /// No description provided for @contacts_invite_short.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get contacts_invite_short;

  /// No description provided for @settings_title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings_title;

  /// No description provided for @settings_nuke_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Delete All Chats'**
  String get settings_nuke_dialog_title;

  /// No description provided for @settings_nuke_dialog_body.
  ///
  /// In en, this message translates to:
  /// **'All chats and messages will be permanently deleted. This cannot be undone.'**
  String get settings_nuke_dialog_body;

  /// No description provided for @settings_nuke_confirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get settings_nuke_confirm;

  /// No description provided for @settings_nuke_backup_first.
  ///
  /// In en, this message translates to:
  /// **'Back Up First'**
  String get settings_nuke_backup_first;

  /// No description provided for @settings_nuke_all_data_warning.
  ///
  /// In en, this message translates to:
  /// **'All your messages, contacts and settings will be deleted.'**
  String get settings_nuke_all_data_warning;

  /// No description provided for @settings_nuke_type_to_confirm.
  ///
  /// In en, this message translates to:
  /// **'Type \\\"DELETE\\\" to confirm:'**
  String get settings_nuke_type_to_confirm;

  /// No description provided for @settings_nuke_type_placeholder.
  ///
  /// In en, this message translates to:
  /// **'DELETE'**
  String get settings_nuke_type_placeholder;

  /// No description provided for @settings_chat_theme.
  ///
  /// In en, this message translates to:
  /// **'Chat Theme'**
  String get settings_chat_theme;

  /// No description provided for @settings_language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settings_language;

  /// No description provided for @settings_backdrop.
  ///
  /// In en, this message translates to:
  /// **'Backdrop Pattern'**
  String get settings_backdrop;

  /// No description provided for @settings_fullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen Mode'**
  String get settings_fullscreen;

  /// No description provided for @settings_show_message_preview.
  ///
  /// In en, this message translates to:
  /// **'Show message content'**
  String get settings_show_message_preview;

  /// No description provided for @settings_notification_sound.
  ///
  /// In en, this message translates to:
  /// **'Notification Sound'**
  String get settings_notification_sound;

  /// No description provided for @settings_incoming_call_screen.
  ///
  /// In en, this message translates to:
  /// **'Incoming call screen'**
  String get settings_incoming_call_screen;

  /// No description provided for @settings_missed_call.
  ///
  /// In en, this message translates to:
  /// **'Missed call alerts'**
  String get settings_missed_call;

  /// No description provided for @settings_battery_optimization.
  ///
  /// In en, this message translates to:
  /// **'Battery optimization'**
  String get settings_battery_optimization;

  /// No description provided for @settings_scheduled_messages.
  ///
  /// In en, this message translates to:
  /// **'Scheduled Messages'**
  String get settings_scheduled_messages;

  /// No description provided for @settings_manage_scheduled.
  ///
  /// In en, this message translates to:
  /// **'Manage Scheduled Messages'**
  String get settings_manage_scheduled;

  /// No description provided for @settings_manage_scheduled_desc.
  ///
  /// In en, this message translates to:
  /// **'View and edit existing scheduled messages'**
  String get settings_manage_scheduled_desc;

  /// No description provided for @settings_e2ee.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encryption'**
  String get settings_e2ee;

  /// No description provided for @settings_e2ee_desc.
  ///
  /// In en, this message translates to:
  /// **'Your messages are encrypted with Signal Protocol'**
  String get settings_e2ee_desc;

  /// No description provided for @settings_last_seen.
  ///
  /// In en, this message translates to:
  /// **'Last seen time'**
  String get settings_last_seen;

  /// No description provided for @settings_message_storage.
  ///
  /// In en, this message translates to:
  /// **'Message Storage Policy'**
  String get settings_message_storage;

  /// No description provided for @settings_message_storage_desc.
  ///
  /// In en, this message translates to:
  /// **'Messages are stored on this device only'**
  String get settings_message_storage_desc;

  /// No description provided for @settings_backup.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get settings_backup;

  /// No description provided for @settings_backup_desc.
  ///
  /// In en, this message translates to:
  /// **'Back up chats encrypted or restore'**
  String get settings_backup_desc;

  /// No description provided for @settings_storage_usage.
  ///
  /// In en, this message translates to:
  /// **'Storage Usage'**
  String get settings_storage_usage;

  /// No description provided for @chat_info_note_label.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get chat_info_note_label;

  /// No description provided for @chat_info_search_placeholder.
  ///
  /// In en, this message translates to:
  /// **'Search messages…'**
  String get chat_info_search_placeholder;

  /// No description provided for @conv_new_chat.
  ///
  /// In en, this message translates to:
  /// **'New Chat'**
  String get conv_new_chat;

  /// No description provided for @conv_new_group.
  ///
  /// In en, this message translates to:
  /// **'New Group'**
  String get conv_new_group;

  /// No description provided for @conv_bulk_message.
  ///
  /// In en, this message translates to:
  /// **'Bulk Message'**
  String get conv_bulk_message;

  /// No description provided for @conv_scheduled_messages.
  ///
  /// In en, this message translates to:
  /// **'Scheduled Messages'**
  String get conv_scheduled_messages;

  /// No description provided for @conv_filter_all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get conv_filter_all;

  /// No description provided for @conv_filter_unread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get conv_filter_unread;

  /// No description provided for @conv_filter_groups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get conv_filter_groups;

  /// No description provided for @conv_filter_favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get conv_filter_favorites;

  /// No description provided for @conv_archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get conv_archive;

  /// No description provided for @conv_delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get conv_delete;

  /// No description provided for @conv_info.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get conv_info;

  /// No description provided for @conv_delete_chat.
  ///
  /// In en, this message translates to:
  /// **'Delete Chat'**
  String get conv_delete_chat;

  /// No description provided for @group_view_profile.
  ///
  /// In en, this message translates to:
  /// **'View Profile'**
  String get group_view_profile;

  /// No description provided for @group_leave.
  ///
  /// In en, this message translates to:
  /// **'Leave Group'**
  String get group_leave;

  /// No description provided for @chat_search_in_chat.
  ///
  /// In en, this message translates to:
  /// **'Search in Chat'**
  String get chat_search_in_chat;

  /// No description provided for @chat_export.
  ///
  /// In en, this message translates to:
  /// **'Export Chat'**
  String get chat_export;

  /// No description provided for @action_close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get action_close;

  /// No description provided for @chat_custom_duration.
  ///
  /// In en, this message translates to:
  /// **'Custom Duration'**
  String get chat_custom_duration;

  /// No description provided for @msg_action_reply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get msg_action_reply;

  /// No description provided for @msg_action_copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get msg_action_copy;

  /// No description provided for @msg_action_edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get msg_action_edit;

  /// No description provided for @msg_action_edit_history.
  ///
  /// In en, this message translates to:
  /// **'Edit History'**
  String get msg_action_edit_history;

  /// No description provided for @msg_action_info.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get msg_action_info;

  /// No description provided for @msg_action_forward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get msg_action_forward;

  /// No description provided for @msg_action_delete_for_me.
  ///
  /// In en, this message translates to:
  /// **'Delete for me'**
  String get msg_action_delete_for_me;

  /// No description provided for @msg_delete_title.
  ///
  /// In en, this message translates to:
  /// **'Delete message'**
  String get msg_delete_title;

  /// No description provided for @msg_delete_cancel.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get msg_delete_cancel;

  /// No description provided for @msg_edit_title.
  ///
  /// In en, this message translates to:
  /// **'Edit Message'**
  String get msg_edit_title;

  /// No description provided for @sched_title.
  ///
  /// In en, this message translates to:
  /// **'Scheduled Messages'**
  String get sched_title;

  /// No description provided for @sched_delete_title.
  ///
  /// In en, this message translates to:
  /// **'Delete Scheduled Message'**
  String get sched_delete_title;

  /// No description provided for @sched_delete_body.
  ///
  /// In en, this message translates to:
  /// **'This scheduled message will be permanently deleted.'**
  String get sched_delete_body;

  /// No description provided for @sched_tab_create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get sched_tab_create;

  /// No description provided for @sched_tab_existing.
  ///
  /// In en, this message translates to:
  /// **'Existing'**
  String get sched_tab_existing;

  /// No description provided for @sched_message_placeholder.
  ///
  /// In en, this message translates to:
  /// **'Type your message…'**
  String get sched_message_placeholder;

  /// No description provided for @sched_action_edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get sched_action_edit;

  /// No description provided for @sched_action_delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get sched_action_delete;

  /// No description provided for @sched_pick_time.
  ///
  /// In en, this message translates to:
  /// **'Pick Time'**
  String get sched_pick_time;

  /// No description provided for @sched_pick_day.
  ///
  /// In en, this message translates to:
  /// **'Pick Day'**
  String get sched_pick_day;

  /// No description provided for @sched_pick_recipient.
  ///
  /// In en, this message translates to:
  /// **'Pick Recipient'**
  String get sched_pick_recipient;

  /// No description provided for @action_ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get action_ok;

  /// No description provided for @conversations_title.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get conversations_title;

  /// No description provided for @conversations_search.
  ///
  /// In en, this message translates to:
  /// **'Search chats'**
  String get conversations_search;

  /// No description provided for @nav_chats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get nav_chats;

  /// No description provided for @nav_calls.
  ///
  /// In en, this message translates to:
  /// **'Calls'**
  String get nav_calls;

  /// No description provided for @nav_contacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get nav_contacts;

  /// No description provided for @chat_e2ee.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encrypted'**
  String get chat_e2ee;

  /// No description provided for @archive_remove.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get archive_remove;

  /// No description provided for @profile_photo_change.
  ///
  /// In en, this message translates to:
  /// **'Change profile photo'**
  String get profile_photo_change;

  /// No description provided for @settings_watermark_desc.
  ///
  /// In en, this message translates to:
  /// **'Show the Elçim watermark'**
  String get settings_watermark_desc;

  /// No description provided for @settings_scheduled_enabled_desc.
  ///
  /// In en, this message translates to:
  /// **'Enable background delivery'**
  String get settings_scheduled_enabled_desc;

  /// No description provided for @settings_local_data_desc.
  ///
  /// In en, this message translates to:
  /// **'Messages, contacts, media and settings'**
  String get settings_local_data_desc;

  /// No description provided for @settings_account_data_desc.
  ///
  /// In en, this message translates to:
  /// **'Server account and all data on this device'**
  String get settings_account_data_desc;

  /// No description provided for @settings_logout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get settings_logout;

  /// No description provided for @settings_notification_preview_desc.
  ///
  /// In en, this message translates to:
  /// **'Lock-screen notification preview'**
  String get settings_notification_preview_desc;

  /// No description provided for @settings_default_notification_sound.
  ///
  /// In en, this message translates to:
  /// **'Default notification sound'**
  String get settings_default_notification_sound;

  /// No description provided for @settings_silent.
  ///
  /// In en, this message translates to:
  /// **'Silent'**
  String get settings_silent;

  /// No description provided for @settings_share_last_seen.
  ///
  /// In en, this message translates to:
  /// **'Share last seen'**
  String get settings_share_last_seen;

  /// No description provided for @settings_screen_protection.
  ///
  /// In en, this message translates to:
  /// **'Screen protection enabled'**
  String get settings_screen_protection;

  /// No description provided for @camera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// No description provided for @gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// No description provided for @profile_photo_remove.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get profile_photo_remove;

  /// No description provided for @settings_delete_local_data.
  ///
  /// In en, this message translates to:
  /// **'Delete all local data'**
  String get settings_delete_local_data;

  /// No description provided for @settings_delete_account.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete account'**
  String get settings_delete_account;

  /// No description provided for @settings_delete_account_body.
  ///
  /// In en, this message translates to:
  /// **'Your server account and all data on this device will be deleted. This cannot be undone.'**
  String get settings_delete_account_body;

  /// No description provided for @theme_system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get theme_system;

  /// No description provided for @theme_light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get theme_light;

  /// No description provided for @theme_dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get theme_dark;

  /// No description provided for @settings_content_hidden.
  ///
  /// In en, this message translates to:
  /// **'Message content hidden'**
  String get settings_content_hidden;

  /// No description provided for @settings_content_visible.
  ///
  /// In en, this message translates to:
  /// **'Content visible'**
  String get settings_content_visible;

  /// No description provided for @settings_privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settings_privacy;

  /// No description provided for @settings_last_seen_hidden.
  ///
  /// In en, this message translates to:
  /// **'Last seen is not shared'**
  String get settings_last_seen_hidden;

  /// No description provided for @settings_last_seen_shared.
  ///
  /// In en, this message translates to:
  /// **'Last seen is shared'**
  String get settings_last_seen_shared;

  /// No description provided for @settings_fullscreen_ios_desc.
  ///
  /// In en, this message translates to:
  /// **'iOS keeps system areas visible and uses an edge-to-edge layout'**
  String get settings_fullscreen_ios_desc;

  /// No description provided for @settings_fullscreen_android_desc.
  ///
  /// In en, this message translates to:
  /// **'Hide Android system bars inside the app'**
  String get settings_fullscreen_android_desc;

  /// No description provided for @settings_auto_download.
  ///
  /// In en, this message translates to:
  /// **'Automatic download'**
  String get settings_auto_download;

  /// No description provided for @settings_auto_download_desc.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi and mobile data rules'**
  String get settings_auto_download_desc;

  /// No description provided for @settings_call_readiness.
  ///
  /// In en, this message translates to:
  /// **'Call readiness'**
  String get settings_call_readiness;

  /// No description provided for @settings_call_readiness_desc.
  ///
  /// In en, this message translates to:
  /// **'Battery, notification and lock-screen permissions'**
  String get settings_call_readiness_desc;

  /// No description provided for @settings_bulk_message.
  ///
  /// In en, this message translates to:
  /// **'Bulk message'**
  String get settings_bulk_message;

  /// No description provided for @settings_bulk_message_desc.
  ///
  /// In en, this message translates to:
  /// **'Send securely to multiple chats'**
  String get settings_bulk_message_desc;

  /// No description provided for @settings_storage_desc.
  ///
  /// In en, this message translates to:
  /// **'Media and chat usage'**
  String get settings_storage_desc;

  /// No description provided for @settings_presence_immediate_desc.
  ///
  /// In en, this message translates to:
  /// **'Changes are sent to the online presence protocol immediately'**
  String get settings_presence_immediate_desc;

  /// No description provided for @settings_screen_protection_desc.
  ///
  /// In en, this message translates to:
  /// **'Android blocks screen capture; iOS covers content in the app switcher.'**
  String get settings_screen_protection_desc;

  /// No description provided for @group_not_found.
  ///
  /// In en, this message translates to:
  /// **'Group not found.'**
  String get group_not_found;

  /// No description provided for @group_admin_only.
  ///
  /// In en, this message translates to:
  /// **'Only admins can send messages'**
  String get group_admin_only;

  /// No description provided for @group_announcement_desc.
  ///
  /// In en, this message translates to:
  /// **'Use the group as an announcement channel'**
  String get group_announcement_desc;

  /// No description provided for @mute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// No description provided for @chat_lock.
  ///
  /// In en, this message translates to:
  /// **'Chat lock'**
  String get chat_lock;

  /// No description provided for @chat_lock_desc.
  ///
  /// In en, this message translates to:
  /// **'Access with device authentication'**
  String get chat_lock_desc;

  /// No description provided for @export_history.
  ///
  /// In en, this message translates to:
  /// **'Export history'**
  String get export_history;

  /// No description provided for @make_admin.
  ///
  /// In en, this message translates to:
  /// **'Make admin'**
  String get make_admin;

  /// No description provided for @no_contacts_to_add.
  ///
  /// In en, this message translates to:
  /// **'No saved contacts can be added.'**
  String get no_contacts_to_add;

  /// No description provided for @confirmation.
  ///
  /// In en, this message translates to:
  /// **'Confirmation'**
  String get confirmation;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @background_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Background service is unavailable.'**
  String get background_unavailable;

  /// No description provided for @storage_service_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Storage service is unavailable.'**
  String get storage_service_unavailable;

  /// No description provided for @edit_mode.
  ///
  /// In en, this message translates to:
  /// **'Edit mode'**
  String get edit_mode;

  /// No description provided for @repeat_once.
  ///
  /// In en, this message translates to:
  /// **'Once'**
  String get repeat_once;

  /// No description provided for @repeat_daily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get repeat_daily;

  /// No description provided for @repeat_custom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get repeat_custom;

  /// No description provided for @weekdays_short.
  ///
  /// In en, this message translates to:
  /// **'Mon,Tue,Wed,Thu,Fri,Sat,Sun'**
  String get weekdays_short;

  /// No description provided for @delivery_time.
  ///
  /// In en, this message translates to:
  /// **'Delivery time'**
  String get delivery_time;

  /// No description provided for @message_content.
  ///
  /// In en, this message translates to:
  /// **'Message content'**
  String get message_content;

  /// No description provided for @recipients.
  ///
  /// In en, this message translates to:
  /// **'Recipients'**
  String get recipients;

  /// No description provided for @recipient_required.
  ///
  /// In en, this message translates to:
  /// **'Select at least one person or group'**
  String get recipient_required;

  /// No description provided for @schedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get schedule;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @no_scheduled_messages.
  ///
  /// In en, this message translates to:
  /// **'No scheduled messages yet.'**
  String get no_scheduled_messages;

  /// No description provided for @schedule_saved.
  ///
  /// In en, this message translates to:
  /// **'Scheduled message saved.'**
  String get schedule_saved;

  /// No description provided for @form_incomplete.
  ///
  /// In en, this message translates to:
  /// **'The form is incomplete.'**
  String get form_incomplete;

  /// No description provided for @over_wifi.
  ///
  /// In en, this message translates to:
  /// **'Over Wi-Fi'**
  String get over_wifi;

  /// No description provided for @over_cellular.
  ///
  /// In en, this message translates to:
  /// **'Over cellular data'**
  String get over_cellular;

  /// No description provided for @photos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photos;

  /// No description provided for @videos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get videos;

  /// No description provided for @documents.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get documents;

  /// Migrated from Android string cellular_limit.
  ///
  /// In en, this message translates to:
  /// **'Cellular limit: {arg1} MB'**
  String cellular_limit(num arg1);

  /// No description provided for @no_chats_yet.
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get no_chats_yet;

  /// Migrated from Android string storage_summary.
  ///
  /// In en, this message translates to:
  /// **'{arg1} messages · {arg2} files · {arg3}'**
  String storage_summary(num arg1, num arg2, String arg3);

  /// No description provided for @clear_media.
  ///
  /// In en, this message translates to:
  /// **'Clear media'**
  String get clear_media;

  /// Migrated from Android string clear_media_body.
  ///
  /// In en, this message translates to:
  /// **'Media and file messages in “{arg1}” will be deleted. Text messages are retained.'**
  String clear_media_body(String arg1);

  /// No description provided for @no_exports_yet.
  ///
  /// In en, this message translates to:
  /// **'No exports yet'**
  String get no_exports_yet;

  /// Migrated from Android string message_count.
  ///
  /// In en, this message translates to:
  /// **'{arg1} messages'**
  String message_count(num arg1);

  /// No description provided for @entire_chat.
  ///
  /// In en, this message translates to:
  /// **'Entire chat'**
  String get entire_chat;

  /// No description provided for @admin_only_screen.
  ///
  /// In en, this message translates to:
  /// **'This screen is available only to group admins'**
  String get admin_only_screen;

  /// No description provided for @bulk_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Bulk sending is unavailable.'**
  String get bulk_unavailable;

  /// No description provided for @select_all.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get select_all;

  /// No description provided for @group.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get group;

  /// Migrated from Android string send_to_recipients.
  ///
  /// In en, this message translates to:
  /// **'Send to {arg1} recipients'**
  String send_to_recipients(num arg1);

  /// Migrated from Android string bulk_result.
  ///
  /// In en, this message translates to:
  /// **'{arg1} sent, {arg2} failed.'**
  String bulk_result(num arg1, num arg2);

  /// No description provided for @encrypted_backup.
  ///
  /// In en, this message translates to:
  /// **'Encrypted Backup'**
  String get encrypted_backup;

  /// No description provided for @backup_explanation.
  ///
  /// In en, this message translates to:
  /// **'Chats, contacts, call logs, scheduled messages and end-to-end encryption state are stored in a password-protected .elbk file. Session access keys are excluded.'**
  String get backup_explanation;

  /// No description provided for @create_backup.
  ///
  /// In en, this message translates to:
  /// **'Create a new backup'**
  String get create_backup;

  /// No description provided for @restore_backup_file.
  ///
  /// In en, this message translates to:
  /// **'Restore a backup file'**
  String get restore_backup_file;

  /// No description provided for @backups_on_device.
  ///
  /// In en, this message translates to:
  /// **'Backups on this device'**
  String get backups_on_device;

  /// No description provided for @no_local_backups.
  ///
  /// In en, this message translates to:
  /// **'No local backups yet'**
  String get no_local_backups;

  /// No description provided for @backup_password.
  ///
  /// In en, this message translates to:
  /// **'Backup password'**
  String get backup_password;

  /// No description provided for @backup_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Backup service is unavailable.'**
  String get backup_unavailable;

  /// No description provided for @save_encrypted_backup.
  ///
  /// In en, this message translates to:
  /// **'Save encrypted backup'**
  String get save_encrypted_backup;

  /// No description provided for @backup_created.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup created.'**
  String get backup_created;

  /// Migrated from Android string backup_create_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not create backup: {arg1}'**
  String backup_create_failed(String arg1);

  /// No description provided for @backup_restored.
  ///
  /// In en, this message translates to:
  /// **'Backup restored.'**
  String get backup_restored;

  /// Migrated from Android string wrong_password_attempts.
  ///
  /// In en, this message translates to:
  /// **'Wrong password. {arg1} attempts remaining.'**
  String wrong_password_attempts(num arg1);

  /// No description provided for @backup_deleted_after_attempts.
  ///
  /// In en, this message translates to:
  /// **'The backup file was deleted after five incorrect attempts.'**
  String get backup_deleted_after_attempts;

  /// No description provided for @backup_delete_failed_after_attempts.
  ///
  /// In en, this message translates to:
  /// **'Attempt limit reached; the platform could not delete the file.'**
  String get backup_delete_failed_after_attempts;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @password_min_length.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters'**
  String get password_min_length;

  /// No description provided for @password_repeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat password'**
  String get password_repeat;

  /// No description provided for @password_too_short.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters.'**
  String get password_too_short;

  /// No description provided for @password_mismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get password_mismatch;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @no_call_history.
  ///
  /// In en, this message translates to:
  /// **'No call history yet.'**
  String get no_call_history;

  /// No description provided for @video_call.
  ///
  /// In en, this message translates to:
  /// **'Video call'**
  String get video_call;

  /// No description provided for @voice_call.
  ///
  /// In en, this message translates to:
  /// **'Voice call'**
  String get voice_call;

  /// No description provided for @outgoing.
  ///
  /// In en, this message translates to:
  /// **'Outgoing'**
  String get outgoing;

  /// No description provided for @incoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get incoming;

  /// No description provided for @video.
  ///
  /// In en, this message translates to:
  /// **'video'**
  String get video;

  /// No description provided for @voice.
  ///
  /// In en, this message translates to:
  /// **'voice'**
  String get voice;

  /// No description provided for @missed.
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get missed;

  /// No description provided for @rejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejected;

  /// No description provided for @busy.
  ///
  /// In en, this message translates to:
  /// **'Busy'**
  String get busy;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// Migrated from Android string call_description.
  ///
  /// In en, this message translates to:
  /// **'{arg1} {arg2} call{arg3}'**
  String call_description(String arg1, String arg2, String arg3);

  /// No description provided for @recheck_status.
  ///
  /// In en, this message translates to:
  /// **'Check status again'**
  String get recheck_status;

  /// No description provided for @calls_ready.
  ///
  /// In en, this message translates to:
  /// **'You are ready for calls'**
  String get calls_ready;

  /// No description provided for @calls_readiness_missing.
  ///
  /// In en, this message translates to:
  /// **'Complete missing items to prevent call delays'**
  String get calls_readiness_missing;

  /// No description provided for @battery_optimization_desc.
  ///
  /// In en, this message translates to:
  /// **'Reduces Doze delays for data-only push and background work'**
  String get battery_optimization_desc;

  /// No description provided for @fullscreen_call_notification.
  ///
  /// In en, this message translates to:
  /// **'Full-screen call notification'**
  String get fullscreen_call_notification;

  /// No description provided for @fullscreen_call_notification_desc.
  ///
  /// In en, this message translates to:
  /// **'Android 14+ lock-screen call view'**
  String get fullscreen_call_notification_desc;

  /// No description provided for @notification_permission.
  ///
  /// In en, this message translates to:
  /// **'Notification permission'**
  String get notification_permission;

  /// No description provided for @notification_permission_desc.
  ///
  /// In en, this message translates to:
  /// **'Message and incoming call notifications'**
  String get notification_permission_desc;

  /// No description provided for @overlay_permission.
  ///
  /// In en, this message translates to:
  /// **'Display over other apps'**
  String get overlay_permission;

  /// No description provided for @overlay_permission_desc.
  ///
  /// In en, this message translates to:
  /// **'Android background call screen'**
  String get overlay_permission_desc;

  /// No description provided for @ios_call_readiness_note.
  ///
  /// In en, this message translates to:
  /// **'On iOS, battery optimization, full-screen intent and overlay cannot be changed by the app. Incoming-call wake-up depends on APNs/CallKit and system policies.'**
  String get ios_call_readiness_note;

  /// No description provided for @secure_communication.
  ///
  /// In en, this message translates to:
  /// **'Secure Communication'**
  String get secure_communication;

  /// No description provided for @onboarding_private_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Your messages stay between you'**
  String get onboarding_private_subtitle;

  /// No description provided for @onboarding_private_body.
  ///
  /// In en, this message translates to:
  /// **'Every message is encrypted on your device; the server cannot read its content.'**
  String get onboarding_private_body;

  /// No description provided for @onboarding_direct_call.
  ///
  /// In en, this message translates to:
  /// **'Direct calls'**
  String get onboarding_direct_call;

  /// No description provided for @onboarding_webrtc_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Voice and video over WebRTC'**
  String get onboarding_webrtc_subtitle;

  /// No description provided for @onboarding_webrtc_body.
  ///
  /// In en, this message translates to:
  /// **'One-to-one calls connect directly; large group calls use the Janus SFU.'**
  String get onboarding_webrtc_body;

  /// No description provided for @onboarding_privacy_control.
  ///
  /// In en, this message translates to:
  /// **'Complete privacy control'**
  String get onboarding_privacy_control;

  /// No description provided for @onboarding_you_decide.
  ///
  /// In en, this message translates to:
  /// **'You decide'**
  String get onboarding_you_decide;

  /// No description provided for @onboarding_privacy_body.
  ///
  /// In en, this message translates to:
  /// **'View once, disappearing messages, screen protection and group export policy.'**
  String get onboarding_privacy_body;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @lets_start.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get lets_start;

  /// No description provided for @continue_action.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continue_action;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @notifications_permission_reason.
  ///
  /// In en, this message translates to:
  /// **'For new messages and calls.'**
  String get notifications_permission_reason;

  /// No description provided for @contacts_permission_reason.
  ///
  /// In en, this message translates to:
  /// **'To discover people using hashes only.'**
  String get contacts_permission_reason;

  /// No description provided for @microphone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get microphone;

  /// No description provided for @microphone_permission_reason.
  ///
  /// In en, this message translates to:
  /// **'For voice and video calls.'**
  String get microphone_permission_reason;

  /// No description provided for @camera_permission_reason.
  ///
  /// In en, this message translates to:
  /// **'For video calls.'**
  String get camera_permission_reason;

  /// No description provided for @permissions_required.
  ///
  /// In en, this message translates to:
  /// **'A few permissions are required'**
  String get permissions_required;

  /// No description provided for @permissions_intro.
  ///
  /// In en, this message translates to:
  /// **'Grant the permissions you want now; you can enable the rest later in settings.'**
  String get permissions_intro;

  /// No description provided for @grant_permission.
  ///
  /// In en, this message translates to:
  /// **'Grant permission'**
  String get grant_permission;

  /// No description provided for @chat_not_found.
  ///
  /// In en, this message translates to:
  /// **'Chat not found.'**
  String get chat_not_found;

  /// No description provided for @contact_info.
  ///
  /// In en, this message translates to:
  /// **'Contact Info'**
  String get contact_info;

  /// No description provided for @starred_messages.
  ///
  /// In en, this message translates to:
  /// **'Starred Messages'**
  String get starred_messages;

  /// No description provided for @media.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get media;

  /// No description provided for @disappearing_messages.
  ///
  /// In en, this message translates to:
  /// **'Disappearing messages'**
  String get disappearing_messages;

  /// No description provided for @contact_note.
  ///
  /// In en, this message translates to:
  /// **'Contact note'**
  String get contact_note;

  /// No description provided for @tap_to_add_note.
  ///
  /// In en, this message translates to:
  /// **'Tap to add a note'**
  String get tap_to_add_note;

  /// No description provided for @no_records.
  ///
  /// In en, this message translates to:
  /// **'No records found'**
  String get no_records;

  /// No description provided for @add_contact_note.
  ///
  /// In en, this message translates to:
  /// **'Add contact note'**
  String get add_contact_note;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// Migrated from Android string hours.
  ///
  /// In en, this message translates to:
  /// **'{arg1} hours'**
  String hours(num arg1);

  /// Migrated from Android string days.
  ///
  /// In en, this message translates to:
  /// **'{arg1} days'**
  String days(num arg1);

  /// Migrated from Android string files_selected.
  ///
  /// In en, this message translates to:
  /// **'{arg1} files selected'**
  String files_selected(num arg1);

  /// No description provided for @add_caption.
  ///
  /// In en, this message translates to:
  /// **'Add a caption...'**
  String get add_caption;

  /// No description provided for @view_once.
  ///
  /// In en, this message translates to:
  /// **'View once'**
  String get view_once;

  /// No description provided for @view_once_protected.
  ///
  /// In en, this message translates to:
  /// **'View once · screen protected'**
  String get view_once_protected;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @tap_to_close_view_once.
  ///
  /// In en, this message translates to:
  /// **'Tap to close · cannot be opened again'**
  String get tap_to_close_view_once;

  /// Migrated from Android string file_open_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not open file: {arg1}'**
  String file_open_failed(String arg1);

  /// Migrated from Android string file_share_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not share file: {arg1}'**
  String file_share_failed(String arg1);

  /// No description provided for @file.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get file;

  /// No description provided for @open_with_app.
  ///
  /// In en, this message translates to:
  /// **'Open with app'**
  String get open_with_app;

  /// No description provided for @media_not_found.
  ///
  /// In en, this message translates to:
  /// **'Media file not found'**
  String get media_not_found;

  /// No description provided for @call_service_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Call service could not be started.'**
  String get call_service_unavailable;

  /// No description provided for @locked_chat.
  ///
  /// In en, this message translates to:
  /// **'Locked Chat'**
  String get locked_chat;

  /// No description provided for @disable_export.
  ///
  /// In en, this message translates to:
  /// **'Disable export'**
  String get disable_export;

  /// No description provided for @enable_export.
  ///
  /// In en, this message translates to:
  /// **'Enable export'**
  String get enable_export;

  /// No description provided for @clear_chat.
  ///
  /// In en, this message translates to:
  /// **'Clear chat'**
  String get clear_chat;

  /// No description provided for @read_only_announcement.
  ///
  /// In en, this message translates to:
  /// **'This group is an announcement channel where only admins can post.'**
  String get read_only_announcement;

  /// No description provided for @no_matching_messages.
  ///
  /// In en, this message translates to:
  /// **'No matching messages found'**
  String get no_matching_messages;

  /// No description provided for @cancel_selection.
  ///
  /// In en, this message translates to:
  /// **'Cancel selection'**
  String get cancel_selection;

  /// Migrated from Android string messages_selected.
  ///
  /// In en, this message translates to:
  /// **'{arg1} messages selected'**
  String messages_selected(num arg1);

  /// No description provided for @forward_selected.
  ///
  /// In en, this message translates to:
  /// **'Forward selected'**
  String get forward_selected;

  /// No description provided for @record_voice_message.
  ///
  /// In en, this message translates to:
  /// **'Record voice message'**
  String get record_voice_message;

  /// No description provided for @poll.
  ///
  /// In en, this message translates to:
  /// **'Poll'**
  String get poll;

  /// No description provided for @add_reaction.
  ///
  /// In en, this message translates to:
  /// **'Add reaction'**
  String get add_reaction;

  /// No description provided for @remove_star.
  ///
  /// In en, this message translates to:
  /// **'Remove star'**
  String get remove_star;

  /// No description provided for @add_star.
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get add_star;

  /// No description provided for @unpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpin;

  /// No description provided for @pin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pin;

  /// No description provided for @choose_reaction.
  ///
  /// In en, this message translates to:
  /// **'Choose reaction'**
  String get choose_reaction;

  /// No description provided for @delete_for_everyone.
  ///
  /// In en, this message translates to:
  /// **'Delete for everyone'**
  String get delete_for_everyone;

  /// No description provided for @clear_chat_confirm.
  ///
  /// In en, this message translates to:
  /// **'Clear this chat?'**
  String get clear_chat_confirm;

  /// No description provided for @clear_chat_body.
  ///
  /// In en, this message translates to:
  /// **'All messages on this device will be permanently deleted.'**
  String get clear_chat_body;

  /// No description provided for @voice_message.
  ///
  /// In en, this message translates to:
  /// **'Voice message'**
  String get voice_message;

  /// No description provided for @recording_start_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not start recording'**
  String get recording_start_failed;

  /// No description provided for @recording_paused.
  ///
  /// In en, this message translates to:
  /// **'Recording paused'**
  String get recording_paused;

  /// No description provided for @recording_active.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get recording_active;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @poll_load_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not load poll'**
  String get poll_load_failed;

  /// No description provided for @single_choice.
  ///
  /// In en, this message translates to:
  /// **'Single choice'**
  String get single_choice;

  /// No description provided for @multiple_choice.
  ///
  /// In en, this message translates to:
  /// **'Multiple choice'**
  String get multiple_choice;

  /// Migrated from Android string total_votes.
  ///
  /// In en, this message translates to:
  /// **'{arg1} total votes'**
  String total_votes(num arg1);

  /// No description provided for @message_info.
  ///
  /// In en, this message translates to:
  /// **'Message Info'**
  String get message_info;

  /// No description provided for @sent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sent;

  /// No description provided for @read.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get read;

  /// No description provided for @delivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get delivered;

  /// No description provided for @send_failed_no_plaintext.
  ///
  /// In en, this message translates to:
  /// **'Sending failed. Plaintext fallback was not used.'**
  String get send_failed_no_plaintext;

  /// No description provided for @forward_to_chat.
  ///
  /// In en, this message translates to:
  /// **'Forward to chat'**
  String get forward_to_chat;

  /// No description provided for @read_only_chat.
  ///
  /// In en, this message translates to:
  /// **'Read-only chat'**
  String get read_only_chat;

  /// Migrated from Android string participant_count.
  ///
  /// In en, this message translates to:
  /// **'{arg1} participants'**
  String participant_count(num arg1);

  /// No description provided for @create_poll.
  ///
  /// In en, this message translates to:
  /// **'Create Poll'**
  String get create_poll;

  /// No description provided for @question.
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get question;

  /// Migrated from Android string option_number.
  ///
  /// In en, this message translates to:
  /// **'Option {arg1}'**
  String option_number(num arg1);

  /// No description provided for @add_option.
  ///
  /// In en, this message translates to:
  /// **'Add option'**
  String get add_option;

  /// No description provided for @member_export_permission.
  ///
  /// In en, this message translates to:
  /// **'Members may copy and export'**
  String get member_export_permission;

  /// No description provided for @admin_change_only.
  ///
  /// In en, this message translates to:
  /// **'Only an admin can change this'**
  String get admin_change_only;

  /// Migrated from Android string remove_member_named.
  ///
  /// In en, this message translates to:
  /// **'Remove {arg1} from the group?'**
  String remove_member_named(String arg1);

  /// No description provided for @leave_group_confirm.
  ///
  /// In en, this message translates to:
  /// **'Do you want to leave this group?'**
  String get leave_group_confirm;

  /// No description provided for @archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// No description provided for @remove_favorite.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get remove_favorite;

  /// No description provided for @add_favorite.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get add_favorite;

  /// No description provided for @mark_read.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get mark_read;

  /// No description provided for @mark_unread.
  ///
  /// In en, this message translates to:
  /// **'Mark as unread'**
  String get mark_unread;

  /// Migrated from Android string delete_chat_body.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete the {arg1} chat and its messages from this device?'**
  String delete_chat_body(String arg1);

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @answer.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get answer;

  /// No description provided for @unmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// No description provided for @speaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get speaker;

  /// No description provided for @flip_camera.
  ///
  /// In en, this message translates to:
  /// **'Flip'**
  String get flip_camera;

  /// No description provided for @end_call.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get end_call;

  /// No description provided for @call_preparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing call…'**
  String get call_preparing;

  /// No description provided for @incoming_call.
  ///
  /// In en, this message translates to:
  /// **'Incoming call'**
  String get incoming_call;

  /// No description provided for @ringing.
  ///
  /// In en, this message translates to:
  /// **'Ringing…'**
  String get ringing;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connecting;

  /// No description provided for @reconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get reconnecting;

  /// No description provided for @weak_connection_disable_video.
  ///
  /// In en, this message translates to:
  /// **'Weak connection — turn off video and continue with audio'**
  String get weak_connection_disable_video;

  /// No description provided for @call_ended.
  ///
  /// In en, this message translates to:
  /// **'Call ended'**
  String get call_ended;

  /// No description provided for @call_rejected.
  ///
  /// In en, this message translates to:
  /// **'Call rejected'**
  String get call_rejected;

  /// No description provided for @connection_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect'**
  String get connection_failed;

  /// No description provided for @voice_service_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Voice message service could not be started.'**
  String get voice_service_unavailable;

  /// No description provided for @voice_encrypting.
  ///
  /// In en, this message translates to:
  /// **'Encrypting and sending voice message…'**
  String get voice_encrypting;

  /// No description provided for @voice_sent.
  ///
  /// In en, this message translates to:
  /// **'Voice message sent.'**
  String get voice_sent;

  /// Migrated from Android string voice_send_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not send voice message: {arg1}'**
  String voice_send_failed(String arg1);

  /// No description provided for @file_transfer_unavailable.
  ///
  /// In en, this message translates to:
  /// **'File transfer service could not be started.'**
  String get file_transfer_unavailable;

  /// Migrated from Android string media_pick_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not select media: {arg1}'**
  String media_pick_failed(String arg1);

  /// No description provided for @media_encrypting.
  ///
  /// In en, this message translates to:
  /// **'Encrypting and sending media…'**
  String get media_encrypting;

  /// Migrated from Android string media_send_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not send media: {arg1}'**
  String media_send_failed(String arg1);

  /// Migrated from Android string media_sent.
  ///
  /// In en, this message translates to:
  /// **'{arg1} media items sent encrypted.'**
  String media_sent(num arg1);

  /// Migrated from Android string media_failed.
  ///
  /// In en, this message translates to:
  /// **'{arg1} media items failed: {arg2}'**
  String media_failed(num arg1, String arg2);

  /// No description provided for @poll_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Poll service is unavailable.'**
  String get poll_unavailable;

  /// No description provided for @poll_sent.
  ///
  /// In en, this message translates to:
  /// **'Poll sent.'**
  String get poll_sent;

  /// No description provided for @poll_send_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not send poll.'**
  String get poll_send_failed;

  /// No description provided for @vote_send_failed.
  ///
  /// In en, this message translates to:
  /// **'Vote could not be sent securely.'**
  String get vote_send_failed;

  /// No description provided for @pin_failed.
  ///
  /// In en, this message translates to:
  /// **'No pin permission or signaling failed.'**
  String get pin_failed;

  /// No description provided for @forward_service_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Message forwarding service could not start.'**
  String get forward_service_unavailable;

  /// Migrated from Android string forward_encrypting.
  ///
  /// In en, this message translates to:
  /// **'Re-encrypting {arg1} messages for {arg2}…'**
  String forward_encrypting(num arg1, String arg2);

  /// Migrated from Android string forward_encryption_result.
  ///
  /// In en, this message translates to:
  /// **'{arg1} messages forwarded; {arg2} could not be encrypted and were not sent.'**
  String forward_encryption_result(num arg1, num arg2);

  /// Migrated from Android string forward_sent.
  ///
  /// In en, this message translates to:
  /// **'{arg1} messages forwarded.'**
  String forward_sent(num arg1);

  /// Migrated from Android string forward_partial.
  ///
  /// In en, this message translates to:
  /// **'{arg1} messages forwarded; {arg2} failed.'**
  String forward_partial(num arg1, num arg2);

  /// No description provided for @reaction_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not send reaction.'**
  String get reaction_failed;

  /// No description provided for @edit_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not edit message.'**
  String get edit_failed;

  /// No description provided for @delete_signal_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not send deletion signal.'**
  String get delete_signal_failed;

  /// No description provided for @export_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Export is unavailable.'**
  String get export_unavailable;

  /// No description provided for @chat_exported.
  ///
  /// In en, this message translates to:
  /// **'Chat exported.'**
  String get chat_exported;

  /// No description provided for @group_policy_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Group policy is unavailable.'**
  String get group_policy_unavailable;

  /// No description provided for @export_disabled.
  ///
  /// In en, this message translates to:
  /// **'Export disabled.'**
  String get export_disabled;

  /// No description provided for @export_enabled.
  ///
  /// In en, this message translates to:
  /// **'Export enabled.'**
  String get export_enabled;

  /// No description provided for @chat_unmuted.
  ///
  /// In en, this message translates to:
  /// **'Chat unmuted.'**
  String get chat_unmuted;

  /// No description provided for @chat_muted.
  ///
  /// In en, this message translates to:
  /// **'Chat muted.'**
  String get chat_muted;

  /// No description provided for @invalid_voice_recording.
  ///
  /// In en, this message translates to:
  /// **'A valid voice recording could not be created.'**
  String get invalid_voice_recording;

  /// No description provided for @audio_not_found.
  ///
  /// In en, this message translates to:
  /// **'Audio file not found'**
  String get audio_not_found;

  /// No description provided for @audio_play_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not play voice recording'**
  String get audio_play_failed;

  /// No description provided for @opened.
  ///
  /// In en, this message translates to:
  /// **'Opened'**
  String get opened;

  /// No description provided for @view_once_photo.
  ///
  /// In en, this message translates to:
  /// **'View-once photo'**
  String get view_once_photo;

  /// No description provided for @media_no_longer_available.
  ///
  /// In en, this message translates to:
  /// **'This media can no longer be opened'**
  String get media_no_longer_available;

  /// No description provided for @tap_to_open.
  ///
  /// In en, this message translates to:
  /// **'Tap to open'**
  String get tap_to_open;

  /// No description provided for @attachment.
  ///
  /// In en, this message translates to:
  /// **'Add attachment'**
  String get attachment;

  /// No description provided for @dialpad.
  ///
  /// In en, this message translates to:
  /// **'Open dial pad'**
  String get dialpad;

  /// No description provided for @remove_option.
  ///
  /// In en, this message translates to:
  /// **'Remove option'**
  String get remove_option;

  /// No description provided for @auth_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Authentication service is not configured.'**
  String get auth_unavailable;

  /// Migrated from Android string rate_limit_seconds.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Wait {arg1} seconds.'**
  String rate_limit_seconds(num arg1);

  /// No description provided for @chat_cleared.
  ///
  /// In en, this message translates to:
  /// **'Chat cleared.'**
  String get chat_cleared;

  /// No description provided for @no_registered_contacts.
  ///
  /// In en, this message translates to:
  /// **'No registered contacts found. Grant contacts permission and refresh.'**
  String get no_registered_contacts;

  /// No description provided for @contacts_secure_directory_unavailable_title.
  ///
  /// In en, this message translates to:
  /// **'Secure contact directory unavailable'**
  String get contacts_secure_directory_unavailable_title;

  /// No description provided for @contacts_secure_directory_unavailable_body.
  ///
  /// In en, this message translates to:
  /// **'The server does not provide the private-directory protocol yet. No less-secure fallback was used; previously verified contacts remain only on your device.'**
  String get contacts_secure_directory_unavailable_body;

  /// No description provided for @contacts_secure_directory_server_upgrade_title.
  ///
  /// In en, this message translates to:
  /// **'Server update required'**
  String get contacts_secure_directory_server_upgrade_title;

  /// No description provided for @contacts_secure_directory_server_upgrade_body.
  ///
  /// In en, this message translates to:
  /// **'The connection succeeded, but the secure directory module is not enabled on the server. Your address-book data was not sent; try again after the server is updated.'**
  String get contacts_secure_directory_server_upgrade_body;

  /// No description provided for @contacts_secure_directory_verification_failed_body.
  ///
  /// In en, this message translates to:
  /// **'Secure directory verification could not be completed. Legacy discovery was not used in order to protect your privacy.'**
  String get contacts_secure_directory_verification_failed_body;

  /// No description provided for @contacts_sync_failed_body.
  ///
  /// In en, this message translates to:
  /// **'Contact sync could not be completed. Existing secure matches on this device were left unchanged; you can try again.'**
  String get contacts_sync_failed_body;

  /// No description provided for @clear_search.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clear_search;

  /// No description provided for @conversations_archived_title.
  ///
  /// In en, this message translates to:
  /// **'Archived Chats'**
  String get conversations_archived_title;

  /// No description provided for @conversations_no_results.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get conversations_no_results;

  /// No description provided for @conversations_no_results_body.
  ///
  /// In en, this message translates to:
  /// **'Try a different search term or filter.'**
  String get conversations_no_results_body;

  /// No description provided for @conversations_empty_body.
  ///
  /// In en, this message translates to:
  /// **'Use the menu in the top-right to start a new secure chat.'**
  String get conversations_empty_body;

  /// No description provided for @conversation_typing.
  ///
  /// In en, this message translates to:
  /// **'typing…'**
  String get conversation_typing;

  /// No description provided for @conversation_locked_preview.
  ///
  /// In en, this message translates to:
  /// **'This chat is hidden'**
  String get conversation_locked_preview;

  /// No description provided for @conversations_messages_section.
  ///
  /// In en, this message translates to:
  /// **'In messages'**
  String get conversations_messages_section;

  /// No description provided for @signaling_disconnected.
  ///
  /// In en, this message translates to:
  /// **'Server connection lost'**
  String get signaling_disconnected;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @chat_online.
  ///
  /// In en, this message translates to:
  /// **'online'**
  String get chat_online;

  /// No description provided for @chat_last_seen.
  ///
  /// In en, this message translates to:
  /// **'last seen {time}'**
  String chat_last_seen(String time);

  /// No description provided for @chat_encryption_notice.
  ///
  /// In en, this message translates to:
  /// **'Messages are end-to-end encrypted.'**
  String get chat_encryption_notice;

  /// No description provided for @chat_today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get chat_today;

  /// No description provided for @chat_yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get chat_yesterday;

  /// No description provided for @chat_pinned_message.
  ///
  /// In en, this message translates to:
  /// **'Pinned Message'**
  String get chat_pinned_message;

  /// No description provided for @chat_admins_only.
  ///
  /// In en, this message translates to:
  /// **'Only admins can send messages'**
  String get chat_admins_only;

  /// No description provided for @chat_message_hint.
  ///
  /// In en, this message translates to:
  /// **'Write a message…'**
  String get chat_message_hint;

  /// No description provided for @chat_scroll_bottom.
  ///
  /// In en, this message translates to:
  /// **'Go to newest message'**
  String get chat_scroll_bottom;

  /// No description provided for @chat_you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get chat_you;

  /// No description provided for @chat_edited.
  ///
  /// In en, this message translates to:
  /// **'edited'**
  String get chat_edited;

  /// No description provided for @chat_attachment_options.
  ///
  /// In en, this message translates to:
  /// **'Attachment options'**
  String get chat_attachment_options;

  /// No description provided for @chat_empty_secure.
  ///
  /// In en, this message translates to:
  /// **'There are no messages in this secure chat yet.'**
  String get chat_empty_secure;

  /// No description provided for @chat_previous_result.
  ///
  /// In en, this message translates to:
  /// **'Previous result'**
  String get chat_previous_result;

  /// No description provided for @chat_next_result.
  ///
  /// In en, this message translates to:
  /// **'Next result'**
  String get chat_next_result;

  /// No description provided for @sending.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get sending;

  /// No description provided for @return_to_call.
  ///
  /// In en, this message translates to:
  /// **'Return to call'**
  String get return_to_call;

  /// No description provided for @settings_open_source_licenses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get settings_open_source_licenses;

  /// No description provided for @settings_open_source_licenses_desc.
  ///
  /// In en, this message translates to:
  /// **'Review the software licenses included in this build.'**
  String get settings_open_source_licenses_desc;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'de', 'en', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
