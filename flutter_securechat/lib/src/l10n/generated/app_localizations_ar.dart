// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get hide_keyboard => 'إخفاء لوحة المفاتيح';

  @override
  String get calls_filter_video => 'فيديو';

  @override
  String get calls_filter_empty => 'لا توجد مكالمات تطابق هذا الفلتر';

  @override
  String get group_added_notification => 'تمت إضافتك إلى مجموعة.';

  @override
  String get group_create_failed =>
      'تعذر إنشاء المجموعة. تحقق من الاتصال وحاول مجدداً.';

  @override
  String get group_call_active_voice => 'مكالمة صوتية جارية';

  @override
  String get group_call_active_video => 'مكالمة فيديو جارية';

  @override
  String get group_call_join => 'انضمام';

  @override
  String get group_call_return => 'العودة إلى المكالمة';

  @override
  String get group_call_join_failed => 'انتهت المكالمة أو تعذر الانضمام إليها.';

  @override
  String get identity_review_title => 'التحقق من الهوية';

  @override
  String get identity_review_warning =>
      'قد يعني تغير الهوية استرداد الحساب أو استخدام جهاز جديد أو وقوع هجوم. قبل الموافقة، قارن بصمة SHA-256 الحالية مع هذا الشخص وجهاً لوجه أو عبر قناة مستقلة موثوقة. لا تعتمد على رسالة في هذه المحادثة. يمكن للطرف الآخر مقارنة بصمتك على جهازه أيضاً.';

  @override
  String get identity_review_previous => 'البصمة الموثوقة سابقاً (SHA-256)';

  @override
  String get identity_review_current => 'البصمة الحالية للطرف الآخر (SHA-256)';

  @override
  String get identity_review_local => 'بصمتك (SHA-256)';

  @override
  String get identity_review_no_previous => 'لا توجد هوية موثوقة سابقاً';

  @override
  String get identity_review_unchanged =>
      'الهوية الحالية تطابق الهوية المحفوظة.';

  @override
  String get identity_review_confirm =>
      'قارنت هذه البصمة عبر قناة مستقلة موثوقة.';

  @override
  String get identity_review_approve => 'الموافقة على هذه الهوية';

  @override
  String get identity_review_approved =>
      'تمت الموافقة على الهوية. يمكنك العودة إلى المحادثة.';

  @override
  String get identity_review_stale =>
      'تغيرت الهوية أثناء المراجعة. أعد تحميلها وتحقق مجدداً.';

  @override
  String get identity_review_failed =>
      'تعذر التحقق من الهوية. لم تتم الموافقة على أي هوية جديدة.';

  @override
  String get identity_review_retry => 'إعادة تحميل الهوية';

  @override
  String get recovery_error_expired =>
      'انتهت صلاحية هذا التحقق. اطلب رمزاً جديداً أو ابدأ تحققاً جديداً.';

  @override
  String get recovery_error_trusted_device =>
      'يتطلب ربط بريد الاسترداد جهازك الموثوق والمسجل دخوله. تحقق من جلستك قبل المحاولة مجدداً.';

  @override
  String get recovery_error_signed_in =>
      'هذا الجهاز مسجل دخوله بالفعل. عد إلى حسابك بدلاً من بدء تحقق آخر.';

  @override
  String get recovery_restart => 'بدء تحقق جديد';

  @override
  String get recovery_restart_warning =>
      'ربما غيّر تسجيل الدخول السابق هوية التشفير وألغى الجلسات القديمة بالفعل. ابدأ من جديد فقط إذا تعذر الإكمال بإعادة المحاولة. سيلزم رمز بريد جديد وموافقة صريحة على الهوية. إذا تم تأكيد تسجيل الدخول السابق، فسيتم الاحتفاظ بهويته.';

  @override
  String get recovery_login_title => 'تسجيل الدخول إلى حساب موجود';

  @override
  String get session_expired_title => 'انتهت جلستك';

  @override
  String get session_expired_body =>
      'رسائلك ما زالت على هذا الجهاز. سجّل الدخول إلى الحساب نفسه مرة أخرى للمتابعة.';

  @override
  String get session_expired_start_over => 'البدء بحساب آخر';

  @override
  String get session_expired_start_over_title =>
      'إزالة الحساب القديم من هذا الجهاز؟';

  @override
  String get session_expired_start_over_body =>
      'لإنشاء حساب جديد تُحذف رسائل الحساب القديم ووسائطه ومفاتيحه من هذا الجهاز. إذا كان بإمكانك تسجيل الدخول إلى الحساب القديم ببريد الاسترداد فجرّب ذلك أولًا، وإلا فلا يمكن استعادة هذه البيانات.';

  @override
  String get session_expired_start_over_confirm => 'حذف ومتابعة';

  @override
  String get registration_device_has_account =>
      'لا يزال هذا الجهاز يحتفظ بحساب أقدم، لذلك تعذّر إنشاء حساب جديد. سجّل الدخول إلى ذلك الحساب مرة أخرى، أو أزِله من هذا الجهاز عبر «البدء بحساب آخر».';

  @override
  String get recovery_email_title => 'بريد استرداد الحساب';

  @override
  String get recovery_email_settings =>
      'إدارة استرداد الحساب على هذا الجهاز المسجل دخوله.';

  @override
  String get recovery_login_description =>
      'أدخل البريد الإلكتروني الذي أضفته إلى حسابك كعنوان استرداد. إذا كان خيار \"استخدم هذا البريد الإلكتروني أيضاً لاستعادة الحساب\" محددًا عند التسجيل فهو بريد التسجيل. يُرسل الرمز إلى هذا العنوان فقط.';

  @override
  String get recovery_enrollment_description =>
      'أكد بريد الاسترداد من هذا الجهاز الموثوق والمسجل دخوله. يمكن ربط العنوان الأول فقط؛ ولا يمكن عرضه أو استبداله هنا.';

  @override
  String get recovery_request_sent =>
      'إذا كان هذا البريد عنوان استرداد لحساب ما، فقد أُرسل رمز من ست خانات. إذا لم يصل خلال بضع دقائق فتحقق من مجلد الرسائل غير المرغوب فيها. إذا ظل مفقودًا فالأرجح أن هذا البريد ليس عنوان استرداد لأي حساب؛ يُضاف بريد الاسترداد عند التسجيل أو من الإعدادات.';

  @override
  String get recovery_send_code => 'إرسال الرمز';

  @override
  String get recovery_verify => 'تأكيد الرمز';

  @override
  String get recovery_change_email => 'استخدام بريد آخر أو طلب رمز جديد';

  @override
  String get recovery_checking => 'جارٍ التحقق من حالة الاسترداد…';

  @override
  String get recovery_retry => 'إعادة المحاولة';

  @override
  String get recovery_email_bound =>
      'تم تأكيد بريد استرداد لهذا الحساب. لا يُعرض العنوان ولا يمكن تغييره هنا.';

  @override
  String get recovery_approval_title => 'الموافقة على تسجيل الدخول';

  @override
  String get recovery_identity_warning =>
      'ينشئ تسجيل الدخول هذا هوية التشفير جديدة لحسابك. سيتغير رقم الأمان، وينبغي لجهات اتصالك التحقق منه مجدداً.';

  @override
  String get recovery_sessions_warning => 'سيتم إلغاء جلسات الحساب السابقة.';

  @override
  String get recovery_history_warning =>
      'استرداد الحساب لا يعيد الرسائل. لا يمكن استعادة سجل المحادثات إلا من نسخة احتياطية موجودة.';

  @override
  String get recovery_identity_accept =>
      'أوافق على هوية التشفير جديدة وإلغاء الجلسات السابقة.';

  @override
  String get recovery_login_accept =>
      'أوافق على تسجيل الدخول هذا وإلغاء الجلسات السابقة.';

  @override
  String get recovery_complete => 'الموافقة وتسجيل الدخول';

  @override
  String get recovery_pending_description =>
      'يجري إكمال تسجيل دخول تمت الموافقة عليه سابقاً. تعيد المحاولة إكمال تسجيل الدخول نفسه دون إنشاء هوية أخرى.';

  @override
  String get recovery_resume_unavailable =>
      'تعذر استئناف تسجيل الدخول المعلق. احتفظ ببيانات هذا الجهاز وحاول مجدداً أو تواصل مع الدعم.';

  @override
  String get recovery_error_rate_limit =>
      'محاولات كثيرة جداً. يرجى الانتظار قبل المحاولة مجدداً.';

  @override
  String get recovery_error_rejected =>
      'تعذر التحقق من الاسترداد. تحقق من بياناتك أو اطلب رمزاً جديداً.';

  @override
  String get recovery_error_generic =>
      'تعذر إكمال الاسترداد. يرجى المحاولة مجدداً.';

  @override
  String get recovery_registration_existing =>
      'يوجد حساب بهذا الرقم بالفعل. سجّل الدخول إليه من «تسجيل الدخول إلى حساب موجود» باستخدام بريد الاسترداد، أو استخدم رقمًا آخر لحساب جديد.';

  @override
  String get auth_login_unavailable =>
      'لا يمكن الوصول إلى حساب موجود عن طريق التسجيل. تسجيل الدخول إلى حساب موجود غير متاح بعد. احتفظ بجهازك الذي تم تسجيل الدخول عليه واتصل بالمسؤول.';

  @override
  String get auth_setup_failed =>
      'لم يكتمل إعداد الحساب. اتصل بالمسؤول قبل التسجيل مرة أخرى. تتطلب المحاولة الجديدة رمز بريد إلكتروني جديداً.';

  @override
  String get auth_bind_recovery_email =>
      'استخدم هذا البريد الإلكتروني أيضاً لاستعادة الحساب';

  @override
  String get auth_bind_recovery_email_hint =>
      'إذا فقدت الوصول على هذا الهاتف، يمكنك تسجيل الدخول مجدداً برمز يُرسل إلى هذا العنوان.';

  @override
  String notification_private_summary(int messageCount, int chatCount) {
    String _temp0 = intl.Intl.pluralLogic(
      messageCount,
      locale: localeName,
      other: '$messageCount رسالة',
      many: '$messageCount رسالة',
      few: '$messageCount رسائل',
      two: 'رسالتان',
      one: 'رسالة واحدة',
      zero: 'لا رسائل',
    );
    String _temp1 = intl.Intl.pluralLogic(
      chatCount,
      locale: localeName,
      other: '$chatCount محادثة',
      many: '$chatCount محادثة',
      few: '$chatCount محادثات',
      two: 'محادثتين',
      one: 'محادثة واحدة',
      zero: 'لا محادثات',
    );
    return '$_temp0 من $_temp1';
  }

  @override
  String get app_name => 'ELÇİM';

  @override
  String get group_info => 'معلومات المجموعة';

  @override
  String get group_settings => 'إعدادات المجموعة';

  @override
  String get add_member => 'إضافة عضو';

  @override
  String members_count(num arg1) {
    return 'الأعضاء ($arg1)';
  }

  @override
  String get loading => 'جارٍ التحميل…';

  @override
  String get admin => 'مشرف';

  @override
  String get you => 'أنت';

  @override
  String get remove_member => 'إزالة العضو';

  @override
  String get remove_from_group => 'إزالة من المجموعة';

  @override
  String get edit_group_name => 'تعديل اسم المجموعة';

  @override
  String get group_name => 'اسم المجموعة';

  @override
  String get save => 'حفظ';

  @override
  String get cancel => 'إلغاء';

  @override
  String get add_new_member => 'إضافة عضو جديد';

  @override
  String get user_id => 'معرّف المستخدم';

  @override
  String get add => 'إضافة';

  @override
  String get remove_member_confirm => 'إزالة العضو';

  @override
  String remove_member_message(String arg1) {
    return 'هل أنت متأكد من إزالة $arg1 من المجموعة؟';
  }

  @override
  String get remove => 'إزالة';

  @override
  String get view_info => 'عرض المعلومات';

  @override
  String get onboarding_subtitle => 'مراسلة آمنة';

  @override
  String get onboarding_e2ee_notice =>
      'رسائلك مشفّرة من طرف إلى طرف. لا يستطيع أحد قراءتها.';

  @override
  String get register_title => 'إنشاء حساب';

  @override
  String get register_subtitle => 'أدخل بياناتك للبدء.';

  @override
  String get register_name_label => 'اسمك';

  @override
  String get register_name_placeholder => 'مثال: أحمد علي';

  @override
  String get register_country_code_label => 'الرمز';

  @override
  String get register_phone_label => 'رقم الهاتف';

  @override
  String get register_phone_placeholder => '5XX XXX XX XX';

  @override
  String get register_start => 'ابدأ';

  @override
  String get contacts_permission_title => 'يلزم الوصول إلى جهات الاتصال';

  @override
  String get contacts_permission_body =>
      'يحتاج التطبيق إلى الوصول إلى جهات الاتصال ليعمل. يرجى منح الإذن حتى نجد جهات اتصالك ونتيح المراسلة الآمنة.';

  @override
  String get action_retry => 'حاول مجددًا';

  @override
  String get validation_name_empty => 'أدخل اسمك';

  @override
  String validation_name_too_short(num arg1) {
    return '$arg1 أحرف على الأقل';
  }

  @override
  String validation_name_too_long(num arg1) {
    return '$arg1 حرفًا على الأكثر';
  }

  @override
  String get validation_name_invalid_chars =>
      'أحرف ومسافات وشرطات وفواصل عليا فقط';

  @override
  String get validation_country_code_empty => 'رمز الدولة فارغ';

  @override
  String get validation_country_code_missing_plus => 'يجب أن يبدأ بـ +';

  @override
  String get validation_country_code_non_digit => 'أرقام فقط';

  @override
  String get validation_country_code_too_short => 'رقم واحد على الأقل';

  @override
  String get validation_country_code_too_long => '4 أرقام على الأكثر';

  @override
  String get validation_phone_empty => 'أدخل رقم هاتفك';

  @override
  String get validation_phone_too_short => 'يلزم 10 أرقام';

  @override
  String get validation_phone_too_long => '10 أرقام فقط';

  @override
  String get validation_phone_non_digit => 'أرقام فقط';

  @override
  String get otp_title => 'التحقق';

  @override
  String get otp_section_title => 'رمز التحقق';

  @override
  String otp_description(String arg1) {
    return 'أدخل الرمز المكوّن من 6 أرقام المرسل\\nإلى $arg1';
  }

  @override
  String get otp_incomplete_error => 'يرجى إدخال الأرقام الستة كلها';

  @override
  String get otp_resend => 'إعادة إرسال الرمز';

  @override
  String otp_resend_countdown(num arg1) {
    return 'إعادة إرسال الرمز: $arg1 ث';
  }

  @override
  String get otp_verify => 'تحقق';

  @override
  String get backup_prompt_title => 'هل لديك نسخة احتياطية؟';

  @override
  String get backup_prompt_body =>
      'إذا أنشأت نسخة احتياطية مشفّرة من قبل فيمكنك استعادة محادثاتك.';

  @override
  String get backup_prompt_yes => 'نعم، استعادة النسخة';

  @override
  String get backup_prompt_no => 'لا، البدء من جديد';

  @override
  String get nav_back => 'رجوع';

  @override
  String get email_otp_title => 'التحقق بالبريد الإلكتروني';

  @override
  String get email_otp_step_email => 'عنوان بريدك الإلكتروني';

  @override
  String get email_otp_step_code => 'رمز التحقق';

  @override
  String get email_otp_description_email =>
      'أدخل بريدك الإلكتروني للتحقق من حسابك. سنرسل الرمز إلى بريدك.';

  @override
  String email_otp_description_code(String arg1) {
    return 'أدخل الرمز المكوّن من 6 أرقام المرسل إلى $arg1.';
  }

  @override
  String get email_otp_email_label => 'البريد الإلكتروني';

  @override
  String get email_otp_code_label => 'رمز من 6 أرقام';

  @override
  String get email_otp_send => 'إرسال الرمز';

  @override
  String get email_otp_change_email => 'استخدام بريد آخر';

  @override
  String get email_otp_dev_skip => 'وضع التطوير — تخطٍّ';

  @override
  String get email_otp_invalid_email => 'أدخل بريدًا إلكترونيًا صالحًا';

  @override
  String get email_otp_sent => 'أُرسل الرمز إلى بريدك';

  @override
  String get email_otp_smtp_disabled =>
      'خدمة البريد غير مهيأة على الخادم. يرجى التواصل مع المسؤول أو استخدام «تخطٍّ» في وضع التطوير.';

  @override
  String get email_otp_rate_limited =>
      'محاولات كثيرة جدًا. يرجى الانتظار بضع دقائق.';

  @override
  String email_otp_send_error(String arg1) {
    return 'تعذّر إرسال الرمز: $arg1';
  }

  @override
  String get email_otp_verify_failed => 'الرمز غير صالح أو منتهي الصلاحية';

  @override
  String get email_otp_incomplete => 'أدخل الأرقام الستة كلها';

  @override
  String get create_group_title => 'مجموعة جديدة';

  @override
  String get create_group_action => 'إنشاء';

  @override
  String create_group_selected_members(num arg1) {
    return 'الأعضاء المحددون ($arg1)';
  }

  @override
  String get create_group_add_by_phone => 'إضافة برقم';

  @override
  String get create_group_user_not_found => 'المستخدم غير موجود';

  @override
  String get create_group_send_invite => 'إرسال دعوة';

  @override
  String get create_group_close => 'إغلاق';

  @override
  String get create_group_registered_contacts => 'جهات الاتصال المسجلة';

  @override
  String get create_group_search_placeholder => 'ابحث في جهات الاتصال…';

  @override
  String get invite_chooser_title => 'إرسال دعوة';

  @override
  String get cd_remove => 'إزالة';

  @override
  String get cd_search => 'بحث';

  @override
  String get cd_clear => 'مسح';

  @override
  String get cd_add => 'إضافة';

  @override
  String get cd_more => 'المزيد';

  @override
  String get cd_connection_status => 'حالة الاتصال';

  @override
  String get cd_new_chat_action => 'بدء محادثة';

  @override
  String get cd_member_actions => 'إجراءات العضو';

  @override
  String get network_error_title => 'خطأ في الاتصال';

  @override
  String get contacts_grant_permission => 'منح الوصول إلى جهات الاتصال';

  @override
  String get contacts_invite_short => 'دعوة';

  @override
  String contacts_on_elcim_section(int count) {
    return 'على ELÇİM ($count)';
  }

  @override
  String contacts_invite_section(int count) {
    return 'ادعُ إلى ELÇİM ($count)';
  }

  @override
  String get contacts_invite_section_body =>
      'هؤلاء الأشخاص لا يستخدمون ELÇİM بعد. ترسل الدعوة من تطبيق الرسائل الخاص بك أو من أي تطبيق تختاره؛ لا تُرسل الأرقام إلى الخادم.';

  @override
  String get contacts_invite_friends => 'ادعُ أصدقاءك';

  @override
  String get invite_via_sms => 'إرسال عبر SMS';

  @override
  String get invite_via_share => 'مشاركة مع تطبيق آخر';

  @override
  String invite_message(String link) {
    return 'مرحبًا! لنتراسل ونتصل بتشفير تام بين الطرفين على ELÇİM. يمكنك تنزيل التطبيق من هنا: $link';
  }

  @override
  String get invite_copied => 'تم نسخ الدعوة إلى الحافظة.';

  @override
  String get contacts_number_not_on_elcim => 'هذا الرقم غير مسجل على ELÇİM.';

  @override
  String get settings_title => 'الإعدادات';

  @override
  String get settings_nuke_dialog_title => 'حذف كل المحادثات';

  @override
  String get settings_nuke_dialog_body =>
      'ستُحذف كل المحادثات والرسائل نهائيًا. لا يمكن التراجع عن ذلك.';

  @override
  String get settings_nuke_confirm => 'حذف';

  @override
  String get settings_nuke_backup_first => 'النسخ الاحتياطي أولًا';

  @override
  String get settings_nuke_all_data_warning =>
      'ستُحذف كل رسائلك وجهات اتصالك وإعداداتك.';

  @override
  String get settings_nuke_type_to_confirm => 'اكتب \\\"DELETE\\\" للتأكيد:';

  @override
  String get settings_nuke_type_placeholder => 'DELETE';

  @override
  String get settings_chat_theme => 'سمة المحادثة';

  @override
  String get settings_language => 'اللغة';

  @override
  String get settings_backdrop => 'الخلفية';

  @override
  String get backdrop_drifting => 'نمط متحرك';

  @override
  String get backdrop_still => 'نمط ثابت';

  @override
  String get backdrop_plain => 'سادة';

  @override
  String get settings_fullscreen => 'وضع ملء الشاشة';

  @override
  String get settings_show_message_preview => 'إظهار محتوى الرسالة';

  @override
  String get settings_notification_sound => 'صوت الإشعار';

  @override
  String get settings_incoming_call_screen => 'شاشة المكالمة الواردة';

  @override
  String get settings_missed_call => 'تنبيهات المكالمات الفائتة';

  @override
  String get settings_battery_optimization => 'تحسين البطارية';

  @override
  String get settings_scheduled_messages => 'الرسائل المجدولة';

  @override
  String get settings_manage_scheduled => 'إدارة الرسائل المجدولة';

  @override
  String get settings_manage_scheduled_desc =>
      'عرض الرسائل المجدولة الحالية وتعديلها';

  @override
  String get settings_e2ee => 'التشفير من طرف إلى طرف';

  @override
  String get settings_e2ee_desc => 'رسائلك مشفّرة من طرف إلى طرف';

  @override
  String get settings_last_seen => 'آخر ظهور';

  @override
  String get settings_message_storage => 'سياسة تخزين الرسائل';

  @override
  String get settings_message_storage_desc =>
      'تُخزَّن الرسائل على هذا الجهاز فقط';

  @override
  String get settings_backup => 'النسخ الاحتياطي';

  @override
  String get settings_backup_desc =>
      'نسخ المحادثات احتياطيًا بشكل مشفّر أو استعادتها';

  @override
  String get settings_storage_usage => 'التخزين';

  @override
  String get create_group_and_add => 'إنشاء المجموعة وإضافة الأشخاص';

  @override
  String get recipient_action_failed =>
      'تعذر إكمال العملية. يرجى المحاولة مرة أخرى.';

  @override
  String group_members_skipped(String names) {
    return 'تعذرت إضافة $names: لم يمكن إنشاء اتصال مشفر. يمكنك إضافتهم مجددًا من معلومات المجموعة بعد أن يفتحوا ELÇİM.';
  }

  @override
  String get group_members_unreachable =>
      'تعذر إنشاء اتصال مشفر مع أي من الأشخاص المحددين. يجب أن يفتحوا أحدث إصدار من ELÇİM.';

  @override
  String get settings_share_online => 'مشاركة حالة الاتصال';

  @override
  String get settings_read_receipts => 'إيصالات القراءة';

  @override
  String get settings_read_receipts_desc =>
      'عند إيقافها لن ترسل إيصالات القراءة أو ترى إيصالات الآخرين.';

  @override
  String get message_show_more => 'عرض المزيد';

  @override
  String get message_show_less => 'عرض أقل';

  @override
  String get chat_info_note_label => 'ملاحظة';

  @override
  String get chat_info_search_placeholder => 'ابحث في الرسائل…';

  @override
  String get conv_new_chat => 'محادثة جديدة';

  @override
  String get conv_new_group => 'مجموعة جديدة';

  @override
  String get conv_bulk_message => 'رسالة جماعية';

  @override
  String get conv_scheduled_messages => 'الرسائل المجدولة';

  @override
  String get conv_filter_all => 'الكل';

  @override
  String get conv_filter_unread => 'غير المقروءة';

  @override
  String get conv_filter_groups => 'المجموعات';

  @override
  String get conv_filter_favorites => 'المفضلة';

  @override
  String get conv_archive => 'أرشفة';

  @override
  String get conv_delete => 'حذف';

  @override
  String get conv_info => 'معلومات';

  @override
  String get conv_delete_chat => 'حذف المحادثة';

  @override
  String get group_view_profile => 'عرض الملف الشخصي';

  @override
  String get group_leave => 'مغادرة المجموعة';

  @override
  String get group_not_member => 'لم تعد عضواً في هذه المجموعة.';

  @override
  String get group_leave_failed =>
      'تعذر إرسال إشعار المغادرة. تحقق من اتصالك وحاول مجدداً.';

  @override
  String get chat_search_in_chat => 'البحث في المحادثة';

  @override
  String get chat_export => 'تصدير المحادثة';

  @override
  String get action_close => 'إغلاق';

  @override
  String get chat_custom_duration => 'مدة مخصصة';

  @override
  String get msg_action_reply => 'رد';

  @override
  String get msg_action_copy => 'نسخ';

  @override
  String get message_copied => 'تم نسخ الرسالة.';

  @override
  String get msg_action_edit => 'تعديل';

  @override
  String get msg_action_edit_history => 'سجل التعديلات';

  @override
  String get msg_action_info => 'معلومات';

  @override
  String get msg_action_forward => 'إعادة توجيه';

  @override
  String get msg_action_delete_for_me => 'حذف لدي';

  @override
  String get msg_delete_title => 'حذف الرسالة';

  @override
  String get msg_delete_cancel => 'تجاهل';

  @override
  String get msg_edit_title => 'تعديل الرسالة';

  @override
  String get sched_title => 'الرسائل المجدولة';

  @override
  String get sched_delete_title => 'حذف الرسالة المجدولة';

  @override
  String get sched_delete_body => 'ستُحذف هذه الرسالة المجدولة نهائيًا.';

  @override
  String get sched_tab_create => 'إنشاء';

  @override
  String get sched_tab_existing => 'الموجودة';

  @override
  String get sched_message_placeholder => 'اكتب رسالتك…';

  @override
  String get sched_action_edit => 'تعديل';

  @override
  String get sched_action_delete => 'حذف';

  @override
  String get sched_pick_time => 'اختر الوقت';

  @override
  String get sched_pick_day => 'اختر اليوم';

  @override
  String get sched_pick_recipient => 'اختر المستلم';

  @override
  String get action_ok => 'حسنًا';

  @override
  String get conversations_title => 'الدردشات';

  @override
  String get conversations_search => 'البحث في الدردشات';

  @override
  String get nav_chats => 'الدردشات';

  @override
  String get nav_calls => 'المكالمات';

  @override
  String get nav_contacts => 'جهات الاتصال';

  @override
  String get chat_e2ee => 'مشفّرة من طرف إلى طرف';

  @override
  String get archive_remove => 'إلغاء الأرشفة';

  @override
  String get profile_photo_change => 'تغيير صورة الملف الشخصي';

  @override
  String get settings_watermark_desc => 'إظهار علامة Elçim المائية';

  @override
  String get settings_scheduled_enabled_desc => 'تمكين الإرسال في الخلفية';

  @override
  String get settings_local_data_desc =>
      'الرسائل وجهات الاتصال والوسائط والإعدادات';

  @override
  String get settings_account_data_desc =>
      'حساب الخادم وجميع البيانات على هذا الجهاز';

  @override
  String get settings_logout => 'تسجيل الخروج';

  @override
  String get settings_notification_preview_desc =>
      'معاينة الإشعارات على شاشة القفل';

  @override
  String get settings_default_notification_sound => 'صوت الإشعار الافتراضي';

  @override
  String get settings_silent => 'صامت';

  @override
  String get sound_system => 'الافتراضي للجهاز';

  @override
  String get sound_chime => 'رنين';

  @override
  String get sound_bell => 'جرس';

  @override
  String get sound_tap => 'نقرة';

  @override
  String get sound_warm => 'دافئ';

  @override
  String get sound_soft => 'ناعم';

  @override
  String get sound_melody => 'لحن';

  @override
  String get sound_flow => 'انسياب';

  @override
  String get sound_sparkle => 'بريق';

  @override
  String get sound_beep => 'صفير';

  @override
  String get sound_ding => 'دينغ';

  @override
  String get sound_preview => 'تشغيل الصوت';

  @override
  String get sound_inherit => 'استخدام إعداد التطبيق';

  @override
  String get sound_system_picker => 'مزيد من الأصوات على هذا الجهاز';

  @override
  String get sound_system_picker_desc => 'اختر أي صوت من إعدادات النظام';

  @override
  String get settings_share_last_seen => 'مشاركة آخر ظهور';

  @override
  String get settings_share_phone_number => 'مشاركة رقم هاتفي';

  @override
  String get settings_share_phone_number_desc =>
      'فقط مع من أراسلهم مباشرة، بتشفير من طرف إلى طرف. لا يمكن استرجاع الأرقام التي تمت مشاركتها سابقاً.';

  @override
  String get settings_screen_protection => 'حماية الشاشة مفعّلة';

  @override
  String get camera => 'الكاميرا';

  @override
  String get gallery => 'المعرض';

  @override
  String get profile_photo_remove => 'إزالة الصورة';

  @override
  String get settings_delete_local_data => 'حذف جميع البيانات المحلية';

  @override
  String get settings_delete_account => 'حذف الحساب نهائيًا';

  @override
  String get settings_delete_account_body =>
      'سيتم حذف حساب الخادم وجميع البيانات على هذا الجهاز. لا يمكن التراجع عن ذلك.';

  @override
  String get theme_system => 'النظام';

  @override
  String get theme_light => 'فاتح';

  @override
  String get theme_dark => 'داكن';

  @override
  String get settings_content_hidden => 'محتوى الرسالة مخفي';

  @override
  String get settings_content_visible => 'المحتوى ظاهر';

  @override
  String get settings_privacy => 'الخصوصية';

  @override
  String get settings_last_seen_hidden => 'آخر ظهور غير مشارك';

  @override
  String get settings_last_seen_shared => 'آخر ظهور مشارك';

  @override
  String get settings_fullscreen_ios_desc =>
      'يحافظ iOS على مناطق النظام ويستخدم تخطيطًا ممتدًا للحواف';

  @override
  String get settings_fullscreen_android_desc =>
      'إخفاء أشرطة نظام Android داخل التطبيق';

  @override
  String get settings_auto_download => 'التنزيل التلقائي';

  @override
  String get settings_auto_download_desc => 'قواعد Wi-Fi وبيانات الهاتف';

  @override
  String get settings_call_readiness => 'جاهزية المكالمات';

  @override
  String get settings_call_readiness_desc =>
      'أذونات البطارية والإشعارات وشاشة القفل';

  @override
  String get settings_bulk_message => 'رسالة جماعية';

  @override
  String get settings_bulk_message_desc => 'إرسال آمن إلى عدة دردشات';

  @override
  String get settings_storage_desc => 'استخدام الوسائط والدردشات';

  @override
  String get settings_presence_immediate_desc =>
      'تُرسل التغييرات فورًا إلى بروتوكول حالة الاتصال';

  @override
  String get settings_screen_protection_desc =>
      'يمنع Android التقاط الشاشة، ويغطي iOS المحتوى في مبدّل التطبيقات.';

  @override
  String get group_not_found => 'المجموعة غير موجودة.';

  @override
  String get group_admin_only => 'يمكن للمشرفين فقط إرسال الرسائل';

  @override
  String get group_announcement_desc => 'استخدام المجموعة كقناة إعلانات';

  @override
  String get mute => 'كتم';

  @override
  String get chat_lock => 'قفل المحادثة';

  @override
  String get chat_lock_desc => 'الوصول بكلمة مرور للمحادثة';

  @override
  String get chat_lock_create_title => 'تعيين كلمة مرور للمحادثة';

  @override
  String get chat_lock_create_body =>
      'ستُطلب كلمة المرور هذه كلما فُتحت هذه المحادثة على هذا الجهاز.';

  @override
  String get chat_lock_unlock_title => 'فتح قفل المحادثة';

  @override
  String chat_lock_unlock_body(String chatName) {
    return 'أدخل كلمة مرور $chatName.';
  }

  @override
  String get chat_lock_unlock_action => 'فتح القفل';

  @override
  String get chat_lock_wrong_password => 'كلمة المرور غير صحيحة.';

  @override
  String get chat_lock_update_failed => 'تعذّر تحديث قفل المحادثة.';

  @override
  String get export_history => 'سجل التصدير';

  @override
  String get make_admin => 'تعيين مشرفًا';

  @override
  String get no_contacts_to_add => 'لا توجد جهات اتصال محفوظة يمكن إضافتها.';

  @override
  String get confirmation => 'تأكيد';

  @override
  String get confirm => 'تأكيد';

  @override
  String get background_unavailable => 'خدمة الخلفية غير متاحة.';

  @override
  String get storage_service_unavailable => 'خدمة التخزين غير متاحة.';

  @override
  String get edit_mode => 'وضع التعديل';

  @override
  String get repeat_once => 'مرة واحدة';

  @override
  String get repeat_daily => 'يوميًا';

  @override
  String get repeat_custom => 'مخصص';

  @override
  String get weekdays_short => 'إثن,ثلا,أرب,خمي,جمع,سبت,أحد';

  @override
  String get schedule_days_label => 'الأيام';

  @override
  String get schedule_days_empty => 'اختر الأيام';

  @override
  String get delivery_time => 'وقت التسليم';

  @override
  String get message_content => 'محتوى الرسالة';

  @override
  String get recipients => 'المستلمون';

  @override
  String get recipient_required => 'اختر شخصًا أو مجموعة واحدة على الأقل';

  @override
  String get schedule => 'جدولة';

  @override
  String get update => 'تحديث';

  @override
  String get no_scheduled_messages => 'لا توجد رسائل مجدولة بعد.';

  @override
  String get schedule_saved => 'تم حفظ الرسالة المجدولة.';

  @override
  String get form_incomplete => 'النموذج غير مكتمل.';

  @override
  String get over_wifi => 'عبر Wi-Fi';

  @override
  String get over_cellular => 'عبر بيانات الجوال';

  @override
  String get photos => 'الصور';

  @override
  String get videos => 'مقاطع الفيديو';

  @override
  String get documents => 'المستندات';

  @override
  String cellular_limit(num arg1) {
    return 'حد بيانات الجوال: $arg1 ميغابايت';
  }

  @override
  String get no_chats_yet => 'لا توجد محادثات بعد';

  @override
  String storage_summary(num arg1, num arg2, String arg3) {
    return '$arg1 رسالة · $arg2 ملف · $arg3';
  }

  @override
  String get clear_media => 'مسح الوسائط';

  @override
  String clear_media_body(String arg1) {
    return 'ستُحذف رسائل الوسائط والملفات في «$arg1». تُحفظ الرسائل النصية.';
  }

  @override
  String get no_exports_yet => 'لا توجد عمليات تصدير بعد';

  @override
  String message_count(num arg1) {
    return '$arg1 رسالة';
  }

  @override
  String get entire_chat => 'المحادثة كاملة';

  @override
  String get admin_only_screen => 'هذه الشاشة متاحة لمشرفي المجموعة فقط';

  @override
  String get bulk_unavailable => 'الإرسال الجماعي غير متاح.';

  @override
  String get bulk_explainer_title => 'يُرسل إلى كل واحد على حدة';

  @override
  String get bulk_explainer_body =>
      'تُرسل الرسالة نفسها إلى كل محادثة محددة كرسالة منفصلة. لا يرى المستلمون بعضهم ولا تُنشأ مجموعة.';

  @override
  String get bulk_search_hint => 'ابحث عن أشخاص أو مجموعات';

  @override
  String bulk_selected_count(Object arg1, Object arg2) {
    return 'تم تحديد $arg1 من $arg2';
  }

  @override
  String get bulk_no_recipients => 'لا توجد محادثات للإرسال إليها';

  @override
  String get bulk_no_results => 'لا توجد محادثات مطابقة';

  @override
  String get bulk_message_required => 'اكتب رسالتك أولًا';

  @override
  String get select_all => 'تحديد الكل';

  @override
  String get group => 'مجموعة';

  @override
  String send_to_recipients(num arg1) {
    return 'إرسال إلى $arg1 مستلمين';
  }

  @override
  String bulk_result(num arg1, num arg2) {
    return 'أُرسلت $arg1، وفشلت $arg2.';
  }

  @override
  String get encrypted_backup => 'نسخة احتياطية مشفّرة';

  @override
  String get backup_explanation =>
      'تُحفظ المحادثات وجهات الاتصال وسجلات المكالمات والرسائل المجدولة وحالة التشفير من طرف إلى طرف في ملف .elbk محمي بكلمة مرور. لا تُضمَّن مفاتيح الوصول إلى الجلسة.';

  @override
  String get create_backup => 'إنشاء نسخة احتياطية جديدة';

  @override
  String get restore_backup_file => 'استعادة ملف نسخة احتياطية';

  @override
  String get backups_on_device => 'النسخ الاحتياطية على هذا الجهاز';

  @override
  String get no_local_backups => 'لا توجد نسخ احتياطية محلية بعد';

  @override
  String get backup_password => 'كلمة مرور النسخة الاحتياطية';

  @override
  String get backup_unavailable => 'خدمة النسخ الاحتياطي غير متاحة.';

  @override
  String get save_encrypted_backup => 'حفظ نسخة احتياطية مشفّرة';

  @override
  String get backup_created => 'تم إنشاء النسخة الاحتياطية المشفّرة.';

  @override
  String backup_create_failed(String arg1) {
    return 'تعذّر إنشاء النسخة الاحتياطية: $arg1';
  }

  @override
  String get backup_restored => 'تمت استعادة النسخة الاحتياطية.';

  @override
  String wrong_password_attempts(num arg1) {
    return 'كلمة مرور خاطئة. المحاولات المتبقية: $arg1.';
  }

  @override
  String get backup_deleted_after_attempts =>
      'حُذف ملف النسخة الاحتياطية بعد خمس محاولات خاطئة.';

  @override
  String get backup_delete_failed_after_attempts =>
      'بلغت حد المحاولات؛ تعذّر على النظام حذف الملف.';

  @override
  String get password => 'كلمة المرور';

  @override
  String get password_min_length => '8 أحرف على الأقل';

  @override
  String get password_repeat => 'أعد كتابة كلمة المرور';

  @override
  String get password_too_short => 'يجب ألا تقل كلمة المرور عن 8 أحرف.';

  @override
  String get password_mismatch => 'كلمتا المرور غير متطابقتين.';

  @override
  String get restore => 'استعادة';

  @override
  String get no_call_history => 'لا يوجد سجل مكالمات بعد.';

  @override
  String get video_call => 'مكالمة فيديو';

  @override
  String get voice_call => 'مكالمة صوتية';

  @override
  String get outgoing => 'صادرة';

  @override
  String get incoming => 'واردة';

  @override
  String get video => 'فيديو';

  @override
  String get voice => 'صوتية';

  @override
  String get missed => 'فائتة';

  @override
  String get rejected => 'مرفوضة';

  @override
  String get busy => 'مشغول';

  @override
  String get failed => 'فشلت';

  @override
  String call_description(String arg1, String arg2, String arg3) {
    return '$arg1 $arg2 مكالمة$arg3';
  }

  @override
  String get recheck_status => 'التحقق من الحالة مجددًا';

  @override
  String get calls_ready => 'أنت جاهز لإجراء المكالمات';

  @override
  String get calls_readiness_missing =>
      'أكمل العناصر الناقصة لتجنب تأخر المكالمات';

  @override
  String get battery_optimization_desc =>
      'يقلل تأخيرات وضع Doze للإشعارات التي تحمل بيانات فقط والعمل في الخلفية';

  @override
  String get fullscreen_call_notification => 'إشعار مكالمة بملء الشاشة';

  @override
  String get fullscreen_call_notification_desc =>
      'عرض المكالمة على شاشة القفل في Android 14 وما بعده';

  @override
  String get notification_permission => 'إذن الإشعارات';

  @override
  String get notification_permission_desc =>
      'إشعارات الرسائل والمكالمات الواردة';

  @override
  String get ios_call_readiness_note =>
      'في iOS لا يستطيع التطبيق تغيير تحسين البطارية ولا الإشعار بملء الشاشة. يعتمد التنبيه بالمكالمة الواردة على APNs وCallKit وسياسات النظام.';

  @override
  String get secure_communication => 'اتصال آمن';

  @override
  String get onboarding_private_subtitle => 'رسائلك تبقى بينكم';

  @override
  String get onboarding_private_body =>
      'تُشفَّر كل رسالة على جهازك؛ ولا يستطيع الخادم قراءة محتواها.';

  @override
  String get onboarding_direct_call => 'مكالمات مباشرة';

  @override
  String get onboarding_webrtc_subtitle => 'صوت وفيديو عبر WebRTC';

  @override
  String get onboarding_webrtc_body =>
      'تتصل المكالمات الفردية والمكالمات الجماعية حتى 8 أشخاص مباشرة بين الأجهزة.';

  @override
  String get onboarding_privacy_control => 'تحكم كامل في الخصوصية';

  @override
  String get onboarding_you_decide => 'القرار لك';

  @override
  String get onboarding_privacy_body =>
      'العرض لمرة واحدة، والرسائل المؤقتة، وحماية الشاشة، وسياسة تصدير المجموعات.';

  @override
  String get skip => 'تخطٍّ';

  @override
  String get lets_start => 'لنبدأ';

  @override
  String get continue_action => 'متابعة';

  @override
  String get notifications => 'الإشعارات';

  @override
  String get notifications_permission_reason => 'للرسائل والمكالمات الجديدة.';

  @override
  String get contacts_permission_reason =>
      'لاكتشاف الأشخاص باستخدام قيم التجزئة فقط.';

  @override
  String get microphone => 'الميكروفون';

  @override
  String get microphone_permission_reason =>
      'للمكالمات الصوتية ومكالمات الفيديو.';

  @override
  String get camera_permission_reason => 'لمكالمات الفيديو.';

  @override
  String get permissions_required => 'بعض الأذونات مطلوبة';

  @override
  String get permissions_intro =>
      'امنح الأذونات التي تريدها الآن؛ ويمكنك تفعيل الباقي لاحقًا من الإعدادات.';

  @override
  String get grant_permission => 'منح الإذن';

  @override
  String get permission_granted => 'تم منح الإذن';

  @override
  String get chat_not_found => 'المحادثة غير موجودة.';

  @override
  String get contact_info => 'معلومات جهة الاتصال';

  @override
  String get starred_messages => 'الرسائل المميزة بنجمة';

  @override
  String get media => 'الوسائط';

  @override
  String get disappearing_messages => 'الرسائل المؤقتة';

  @override
  String disappearing_timer_enabled_by_you(String duration) {
    return 'ضبطت الرسائل المؤقتة على $duration.';
  }

  @override
  String get disappearing_timer_disabled_by_you => 'أوقفت الرسائل المؤقتة.';

  @override
  String disappearing_timer_enabled_by_peer(String sender, String duration) {
    return 'ضبط $sender الرسائل المؤقتة على $duration.';
  }

  @override
  String disappearing_timer_disabled_by_peer(String sender) {
    return 'أوقف $sender الرسائل المؤقتة.';
  }

  @override
  String get contact_note => 'ملاحظة جهة الاتصال';

  @override
  String get tap_to_add_note => 'انقر لإضافة ملاحظة';

  @override
  String get no_records => 'لا توجد سجلات';

  @override
  String get add_contact_note => 'إضافة ملاحظة لجهة الاتصال';

  @override
  String get off => 'إيقاف';

  @override
  String hours(num arg1) {
    return '$arg1 ساعة';
  }

  @override
  String days(num arg1) {
    return '$arg1 يوم';
  }

  @override
  String files_selected(num arg1) {
    return 'تم تحديد $arg1 ملف';
  }

  @override
  String get add_caption => 'أضف تعليقًا...';

  @override
  String get view_once => 'عرض لمرة واحدة';

  @override
  String get view_once_protected => 'عرض لمرة واحدة · الشاشة محمية';

  @override
  String get share => 'مشاركة';

  @override
  String get tap_to_close_view_once => 'انقر للإغلاق · لا يمكن فتحها مجددًا';

  @override
  String file_open_failed(String arg1) {
    return 'تعذّر فتح الملف: $arg1';
  }

  @override
  String file_share_failed(String arg1) {
    return 'تعذّر مشاركة الملف: $arg1';
  }

  @override
  String get file => 'ملف';

  @override
  String get open_with_app => 'فتح بتطبيق';

  @override
  String get media_not_found => 'ملف الوسائط غير موجود';

  @override
  String get call_service_unavailable => 'تعذّر تشغيل خدمة المكالمات.';

  @override
  String get locked_chat => 'محادثة مقفلة';

  @override
  String get disable_export => 'تعطيل التصدير';

  @override
  String get enable_export => 'تفعيل التصدير';

  @override
  String get clear_chat => 'مسح المحادثة';

  @override
  String get read_only_announcement =>
      'هذه المجموعة قناة إعلانات لا ينشر فيها إلا المشرفون.';

  @override
  String get no_matching_messages => 'لا توجد رسائل مطابقة';

  @override
  String get cancel_selection => 'إلغاء التحديد';

  @override
  String messages_selected(num arg1) {
    return 'تم تحديد $arg1 رسالة';
  }

  @override
  String get forward_selected => 'إعادة توجيه المحدد';

  @override
  String get record_voice_message => 'تسجيل رسالة صوتية';

  @override
  String get poll => 'استطلاع';

  @override
  String get add_reaction => 'إضافة تفاعل';

  @override
  String get remove_star => 'إزالة النجمة';

  @override
  String get add_star => 'تمييز بنجمة';

  @override
  String get unpin => 'إلغاء التثبيت';

  @override
  String get pin => 'تثبيت';

  @override
  String get choose_reaction => 'اختر تفاعلًا';

  @override
  String get delete_for_everyone => 'حذف لدى الجميع';

  @override
  String get clear_chat_confirm => 'مسح هذه المحادثة؟';

  @override
  String get clear_chat_body => 'ستُحذف كل الرسائل على هذا الجهاز نهائيًا.';

  @override
  String get clear_group_history_body =>
      'ستُحذف رسائل هذه المجموعة من هذا الجهاز فقط. ستبقى المجموعة وعضويتك فيها، ولن تتأثر رسائل الأعضاء الآخرين.';

  @override
  String get voice_message => 'رسالة صوتية';

  @override
  String get recording_start_failed => 'تعذّر بدء التسجيل';

  @override
  String get recording_paused => 'التسجيل متوقف مؤقتًا';

  @override
  String get recording_active => 'جارٍ التسجيل';

  @override
  String get send => 'إرسال';

  @override
  String get poll_load_failed => 'تعذّر تحميل الاستطلاع';

  @override
  String get single_choice => 'اختيار واحد';

  @override
  String get multiple_choice => 'اختيارات متعددة';

  @override
  String total_votes(num arg1) {
    return 'إجمالي الأصوات: $arg1';
  }

  @override
  String get message_info => 'معلومات الرسالة';

  @override
  String get sent => 'أُرسلت';

  @override
  String get read => 'قُرئت';

  @override
  String get delivered => 'سُلّمت';

  @override
  String get send_failed_no_plaintext =>
      'فشل الإرسال. لم يُستخدم إرسال نص غير مشفّر.';

  @override
  String get forward_to_chat => 'إعادة التوجيه إلى محادثة';

  @override
  String get read_only_chat => 'محادثة للقراءة فقط';

  @override
  String participant_count(num arg1) {
    return '$arg1 مشارك';
  }

  @override
  String get create_poll => 'إنشاء استطلاع';

  @override
  String get question => 'السؤال';

  @override
  String option_number(num arg1) {
    return 'الخيار $arg1';
  }

  @override
  String get add_option => 'إضافة خيار';

  @override
  String get member_export_permission => 'يمكن للأعضاء النسخ والتصدير';

  @override
  String get admin_change_only => 'يمكن للمشرف فقط تغيير هذا';

  @override
  String remove_member_named(String arg1) {
    return 'إزالة $arg1 من المجموعة؟';
  }

  @override
  String get leave_group_confirm => 'هل تريد مغادرة هذه المجموعة؟';

  @override
  String get archive => 'الأرشيف';

  @override
  String get remove_favorite => 'إزالة من المفضلة';

  @override
  String get add_favorite => 'إضافة إلى المفضلة';

  @override
  String get mark_read => 'تحديد كمقروءة';

  @override
  String get mark_unread => 'تحديد كغير مقروءة';

  @override
  String delete_chat_body(String arg1) {
    return 'حذف محادثة $arg1 ورسائلها نهائيًا من هذا الجهاز؟';
  }

  @override
  String get reject => 'رفض';

  @override
  String get answer => 'رد';

  @override
  String get unmute => 'إلغاء الكتم';

  @override
  String get speaker => 'مكبر الصوت';

  @override
  String get flip_camera => 'قلب';

  @override
  String get end_call => 'إنهاء';

  @override
  String get call_preparing => 'جارٍ تجهيز المكالمة…';

  @override
  String get incoming_call => 'مكالمة واردة';

  @override
  String get ringing => 'يرن…';

  @override
  String get connecting => 'جارٍ الاتصال…';

  @override
  String get reconnecting => 'جارٍ إعادة الاتصال…';

  @override
  String get weak_connection_disable_video =>
      'الاتصال ضعيف — أوقف الفيديو وتابع بالصوت';

  @override
  String get call_ended => 'انتهت المكالمة';

  @override
  String get call_rejected => 'رُفضت المكالمة';

  @override
  String get connection_failed => 'تعذّر الاتصال';

  @override
  String get voice_service_unavailable => 'تعذّر تشغيل خدمة الرسائل الصوتية.';

  @override
  String get voice_encrypting => 'جارٍ تشفير الرسالة الصوتية وإرسالها…';

  @override
  String get voice_sent => 'أُرسلت الرسالة الصوتية.';

  @override
  String voice_send_failed(String arg1) {
    return 'تعذّر إرسال الرسالة الصوتية: $arg1';
  }

  @override
  String get file_transfer_unavailable => 'تعذّر تشغيل خدمة نقل الملفات.';

  @override
  String media_pick_failed(String arg1) {
    return 'تعذّر اختيار الوسائط: $arg1';
  }

  @override
  String get media_encrypting => 'جارٍ تشفير الوسائط وإرسالها…';

  @override
  String media_send_failed(String arg1) {
    return 'تعذّر إرسال الوسائط: $arg1';
  }

  @override
  String media_sent(num arg1) {
    return 'أُرسل $arg1 عنصر وسائط مشفّرًا.';
  }

  @override
  String media_failed(num arg1, String arg2) {
    return 'فشل $arg1 عنصر وسائط: $arg2';
  }

  @override
  String get poll_unavailable => 'خدمة الاستطلاعات غير متاحة.';

  @override
  String get poll_sent => 'أُرسل الاستطلاع.';

  @override
  String get poll_send_failed => 'تعذّر إرسال الاستطلاع.';

  @override
  String get vote_send_failed => 'تعذّر إرسال التصويت بأمان.';

  @override
  String get pin_failed => 'لا يوجد إذن بالتثبيت أو فشل الإرسال.';

  @override
  String get forward_service_unavailable =>
      'تعذّر تشغيل خدمة إعادة توجيه الرسائل.';

  @override
  String forward_encrypting(num arg1, String arg2) {
    return 'جارٍ إعادة تشفير $arg1 رسالة لـ $arg2…';
  }

  @override
  String forward_encryption_result(num arg1, num arg2) {
    return 'أُعيد توجيه $arg1 رسالة؛ وتعذّر تشفير $arg2 فلم تُرسل.';
  }

  @override
  String forward_sent(num arg1) {
    return 'أُعيد توجيه $arg1 رسالة.';
  }

  @override
  String forward_partial(num arg1, num arg2) {
    return 'أُعيد توجيه $arg1 رسالة؛ وفشلت $arg2.';
  }

  @override
  String get reaction_failed => 'تعذّر إرسال التفاعل.';

  @override
  String get edit_failed => 'تعذّر تعديل الرسالة.';

  @override
  String get delete_signal_failed => 'تعذّر إرسال إشارة الحذف.';

  @override
  String get export_unavailable => 'التصدير غير متاح.';

  @override
  String get chat_exported => 'تم تصدير المحادثة.';

  @override
  String get group_policy_unavailable => 'سياسة المجموعة غير متاحة.';

  @override
  String get export_disabled => 'تم تعطيل التصدير.';

  @override
  String get export_enabled => 'تم تفعيل التصدير.';

  @override
  String get chat_unmuted => 'أُلغي كتم المحادثة.';

  @override
  String get chat_muted => 'كُتمت المحادثة.';

  @override
  String get invalid_voice_recording => 'تعذّر إنشاء تسجيل صوتي صالح.';

  @override
  String get audio_not_found => 'الملف الصوتي غير موجود';

  @override
  String get audio_play_failed => 'تعذّر تشغيل التسجيل الصوتي';

  @override
  String get opened => 'فُتحت';

  @override
  String get view_once_photo => 'صورة لعرض واحد';

  @override
  String get media_no_longer_available => 'لم يعد بالإمكان فتح هذه الوسائط';

  @override
  String get tap_to_open => 'انقر للفتح';

  @override
  String get attachment => 'إضافة مرفق';

  @override
  String get dialpad => 'فتح لوحة الأرقام';

  @override
  String get remove_option => 'إزالة الخيار';

  @override
  String get auth_unavailable => 'خدمة المصادقة غير مهيأة.';

  @override
  String rate_limit_seconds(num arg1) {
    return 'طلبات كثيرة جدًا. انتظر $arg1 ثانية.';
  }

  @override
  String get chat_cleared => 'تم مسح المحادثة.';

  @override
  String get no_registered_contacts =>
      'لم يُعثر على جهات اتصال مسجلة. امنح إذن جهات الاتصال ثم حدّث.';

  @override
  String get contacts_secure_directory_unavailable_title =>
      'دليل جهات الاتصال الآمن غير متاح';

  @override
  String get contacts_secure_directory_unavailable_body =>
      'لا يوفّر الخادم بروتوكول الدليل الخاص بعد. لم تُستخدم طريقة أقل أمانًا، وتبقى جهات الاتصال المؤكدة سابقًا على جهازك فقط.';

  @override
  String get contacts_secure_directory_server_upgrade_title =>
      'يلزم تحديث الخادم';

  @override
  String get contacts_secure_directory_server_upgrade_body =>
      'تم الاتصال، لكن وحدة دليل جهات الاتصال الآمن غير مفعلة على الخادم. لم تُرسل بيانات دفتر عناوينك؛ أعد المحاولة بعد تحديث الخادم.';

  @override
  String get contacts_secure_directory_verification_failed_body =>
      'تعذر التحقق من دليل جهات الاتصال الآمن. لم تُستخدم طريقة البحث القديمة حفاظًا على خصوصيتك.';

  @override
  String get contacts_sync_failed_body =>
      'تعذرت مزامنة جهات الاتصال. لم تتغير المطابقات الآمنة الموجودة على هذا الجهاز؛ يمكنك المحاولة مجددًا.';

  @override
  String get clear_search => 'مسح البحث';

  @override
  String get conversations_archived_title => 'الدردشات المؤرشفة';

  @override
  String get conversations_no_results => 'لم يتم العثور على نتائج';

  @override
  String get conversations_no_results_body =>
      'جرّب عبارة بحث أو مرشحًا مختلفًا.';

  @override
  String get conversations_empty_body =>
      'استخدم القائمة في أعلى اليمين لبدء دردشة آمنة جديدة.';

  @override
  String get conversation_typing => 'يكتب…';

  @override
  String get conversation_locked_preview => 'هذه الدردشة مخفية';

  @override
  String get conversations_messages_section => 'في الرسائل';

  @override
  String get signaling_disconnected => 'انقطع الاتصال بالخادم';

  @override
  String get connected => 'متصل';

  @override
  String get chat_online => 'متصل الآن';

  @override
  String chat_last_seen(String time) {
    return 'آخر ظهور $time';
  }

  @override
  String get chat_encryption_notice => 'الرسائل مشفرة من طرف إلى طرف.';

  @override
  String get chat_today => 'اليوم';

  @override
  String get chat_yesterday => 'أمس';

  @override
  String get chat_pinned_message => 'رسالة مثبتة';

  @override
  String get chat_admins_only => 'يمكن للمشرفين فقط إرسال الرسائل';

  @override
  String get chat_message_hint => 'اكتب رسالة…';

  @override
  String get chat_scroll_bottom => 'الانتقال إلى أحدث رسالة';

  @override
  String get chat_you => 'أنت';

  @override
  String get chat_edited => 'معدّلة';

  @override
  String get chat_attachment_options => 'خيارات المرفقات';

  @override
  String get chat_empty_secure => 'لا توجد رسائل في هذه الدردشة الآمنة بعد.';

  @override
  String get chat_previous_result => 'النتيجة السابقة';

  @override
  String get chat_next_result => 'النتيجة التالية';

  @override
  String get sending => 'جارٍ الإرسال';

  @override
  String get return_to_call => 'العودة إلى المكالمة';

  @override
  String get settings_open_source_licenses => 'تراخيص البرمجيات مفتوحة المصدر';

  @override
  String get settings_open_source_licenses_desc =>
      'راجع تراخيص البرمجيات المضمنة في هذا الإصدار.';

  @override
  String get settings_about => 'حول';

  @override
  String get settings_about_desc => 'الإصدار وملاحظات الأمان والتراخيص';

  @override
  String get about_security_title => 'الأمان';

  @override
  String get about_security_body =>
      'تُشفَّر الرسائل من طرف إلى طرف قبل مغادرة الجهاز، وتشتق آلية التدوير مفتاحًا جديدًا لكل رسالة. لا يخزّن الخادم النص الصريح ولا سجل المحادثات؛ وقد يبقى غلاف مشفّر لم يُسلَّم بعد في طابور مؤقت في الذاكرة فقط حتى الإقرار بالاستلام أو انتهاء صلاحيته. قاعدة البيانات المحلية مشفّرة بـ SQLCipher.';

  @override
  String get about_version => 'الإصدار';

  @override
  String get missed_call => 'مكالمة فائتة';

  @override
  String get missed_video_call => 'مكالمة فيديو فائتة';

  @override
  String get missed_voice_call => 'مكالمة صوتية فائتة';

  @override
  String missed_call_from(Object peer) {
    return 'من $peer';
  }

  @override
  String get missed_calls_channel => 'المكالمات الفائتة';

  @override
  String get missed_calls_channel_desc =>
      'إشعارات المكالمات التي لم يتم الرد عليها';

  @override
  String get messages_channel => 'رسائل elçim';

  @override
  String get messages_channel_silent => 'رسائل elçim (صامت)';

  @override
  String get messages_channel_desc => 'إشعارات الرسائل الآمنة الواردة';

  @override
  String get messages_channel_silent_desc => 'الرسائل المكتومة أو داخل التطبيق';

  @override
  String get security_number_changed =>
      'تغير رقم الأمان. ربما أعاد هذا الشخص تثبيت التطبيق. إذا لم تكن متأكدًا، فتحقق من هويته عبر قناة أخرى.';

  @override
  String get security_message_unreadable =>
      'تعذّر فك تشفير إحدى الرسائل ولا يمكن عرضها. يمكنك أن تطلب من المُرسِل إرسالها مرة أخرى.';

  @override
  String get chat_jump_to_replied_message =>
      'الانتقال إلى الرسالة التي تم الرد عليها';

  @override
  String get contacts_empty_body =>
      'تتم مطابقة جهات اتصالك عبر التجزئة فقط. سيظهر هنا كل من يستخدم elçim.';

  @override
  String get calls_empty_body =>
      'تُدرج هنا المكالمات الصادرة والواردة. لا يُسجَّل محتوى المكالمات أبدًا.';

  @override
  String get group_unknown_member => 'عضو غير معروف';

  @override
  String get backup_passwords_match => 'يجب أن تتطابق كلمتا المرور';

  @override
  String get sched_tab_history => 'السجل';

  @override
  String get sched_history_note =>
      'لا تعني حالة الإرسال أن المستلم قد استلم الرسالة أو قرأها.';

  @override
  String get sched_history_empty => 'لا يوجد سجل إرسال بعد.';

  @override
  String get sched_history_locked => 'محتوى محادثة مقفلة';

  @override
  String get sched_history_sent => 'تم الإرسال';

  @override
  String get sched_history_partial_failure => 'فشل جزئي';

  @override
  String get sched_history_failed => 'تعذر الإرسال';

  @override
  String get sched_history_encryption_failed => 'فشل التشفير';

  @override
  String get sched_history_delivery_failed => 'فشل النقل';

  @override
  String get sched_history_details => 'تفاصيل الإرسال';

  @override
  String get sched_history_executed_at => 'وقت الإرسال';

  @override
  String get sched_history_status => 'الحالة';

  @override
  String get sched_history_content_omitted =>
      'لم يُحفظ المحتوى في السجل حفاظًا على الخصوصية.';

  @override
  String get storage_reload => 'تحديث';

  @override
  String get storage_load_failed => 'تعذّر تحميل معلومات التخزين.';

  @override
  String get storage_filter => 'تصفية الملفات';

  @override
  String get storage_all_files => 'كل الملفات';

  @override
  String get storage_audio => 'الصوت';

  @override
  String get storage_no_files => 'لا توجد وسائط أو ملفات في هذه الفئة.';

  @override
  String get storage_local_missing => 'غير موجود على هذا الجهاز';

  @override
  String storage_delete_action(int arg1) {
    return 'حذف المحدد ($arg1)';
  }

  @override
  String storage_delete_selected(int arg1) {
    return 'ستُحذف رسائل الوسائط والملفات المحددة وعددها $arg1 من هذا الجهاز فقط. ستبقى الرسائل النصية ونسخ الآخرين. لا يمكن التراجع عن ذلك.';
  }

  @override
  String storage_cleanup_result(int arg1, String arg2) {
    return 'حُذف $arg1 سجل · تم توفير $arg2';
  }

  @override
  String storage_cleanup_failed(int arg1) {
    return 'تعذّر حذف $arg1 سجل. تم تحديث الملفات الأخرى؛ يمكنك المحاولة مجددًا.';
  }

  @override
  String get safety_block => 'حظر';

  @override
  String get safety_unblock => 'إلغاء الحظر';

  @override
  String get safety_block_confirm_title => 'حظر جهة الاتصال هذه؟';

  @override
  String get safety_block_confirm_body =>
      'لن تتمكن جهات الاتصال المحظورة من الاتصال بك أو مراسلتك. ولا يتم إعلامها.';

  @override
  String get safety_blocked_notice => 'تم حظر جهة الاتصال';

  @override
  String get safety_unblocked_notice => 'تم إلغاء حظر جهة الاتصال';

  @override
  String get safety_blocked_banner =>
      'لقد حظرت جهة الاتصال هذه. لم يعد بإمكانك إرسال الرسائل أو المكالمات أو تلقيها.';

  @override
  String get safety_report => 'إبلاغ';

  @override
  String get safety_report_group => 'الإبلاغ عن المجموعة';

  @override
  String get safety_report_title => 'لماذا تُبلغ؟';

  @override
  String get safety_report_e2ee_note =>
      'الرسائل مشفّرة من طرف إلى طرف. يتضمن بلاغك الحساب والسبب الذي تختاره، دون أي محتوى للرسائل.';

  @override
  String get safety_reason_spam => 'رسائل مزعجة';

  @override
  String get safety_reason_harassment => 'تحرش أو تنمر';

  @override
  String get safety_reason_inappropriate => 'محتوى غير لائق';

  @override
  String get safety_reason_child_safety => 'سلامة الأطفال';

  @override
  String get safety_reason_impersonation => 'انتحال شخصية';

  @override
  String get safety_reason_other => 'أخرى';

  @override
  String get safety_report_note_hint => 'أضف تفاصيل (اختياري)';

  @override
  String get safety_report_also_block => 'حظر جهة الاتصال هذه أيضًا';

  @override
  String get safety_report_submit => 'إرسال البلاغ';

  @override
  String get safety_report_sent =>
      'أُرسل البلاغ. تُراجع البلاغات خلال 24 ساعة.';

  @override
  String get safety_report_failed => 'تعذّر إرسال البلاغ. حاول مجددًا.';

  @override
  String get safety_blocked_contacts => 'جهات الاتصال المحظورة';

  @override
  String get safety_blocked_contacts_empty => 'لا توجد جهات اتصال محظورة';

  @override
  String get legal_consent_notice =>
      'بالمتابعة فإنك توافق على شروط الاستخدام وسياسة الخصوصية.';

  @override
  String get legal_terms => 'شروط الاستخدام';

  @override
  String get legal_privacy => 'سياسة الخصوصية';

  @override
  String get legal_child_safety => 'معايير سلامة الأطفال';

  @override
  String get legal_open_failed => 'تعذّر فتح الصفحة.';

  @override
  String get logout_confirm_title => 'تسجيل الخروج؟';

  @override
  String get logout_confirm_body =>
      'يحذف تسجيل الخروج كل الرسائل والوسائط وسجل المكالمات والنسخ الاحتياطية المحلية على هذا الجهاز. يبقى حسابك على الخادم، لكن سجلك لن يعود عند تسجيل الدخول مجددًا.';

  @override
  String get logout_no_recovery_title =>
      'قد لا تتمكن من العودة إلى هذا الحساب أبداً';

  @override
  String get logout_no_recovery_body =>
      'لا يوجد بريد إلكتروني للاسترداد مرتبط بهذا الحساب. إذا سجلت الخروج فلن تتمكن من تسجيل الدخول إلى هذا الحساب أو بهذا الرقم مرة أخرى. أضف بريداً إلكترونياً للاسترداد أولاً.';

  @override
  String get logout_recovery_unknown_body =>
      'تعذر التحقق من بريد الاسترداد الآن. إذا لم يكن هناك بريد استرداد مرتبط فلن تتمكن من تسجيل الدخول إلى هذا الحساب بعد الخروج.';

  @override
  String get logout_no_recovery_ack => 'أفهم أنني قد أفقد هذا الحساب';

  @override
  String get logout_add_recovery => 'إضافة بريد الاسترداد';

  @override
  String get logout_anyway => 'تسجيل الخروج على أي حال';

  @override
  String get call_no_answer => 'لا رد';

  @override
  String get view_once_unsupported_type =>
      'لا يمكن فتح هذا النوع من الملفات للعرض لمرة واحدة.';

  @override
  String get view_once_only_photo_or_text =>
      'يمكن إرسال الصور والملفات النصية فقط للعرض لمرة واحدة.';

  @override
  String get recipient_no_results => 'لا توجد جهات اتصال مطابقة';

  @override
  String get contacts_sync => 'مزامنة جهات الاتصال';

  @override
  String get unknown_contact => 'جهة اتصال غير معروفة';

  @override
  String get not_in_contacts_banner => 'هذا الشخص ليس ضمن جهات اتصالك';

  @override
  String get not_in_contacts_hint => 'إذا كنت لا تعرفه، فكن حذرًا قبل الرد.';

  @override
  String get not_in_contacts_no_number =>
      'لم يشارك رقمه، لذا لا يمكن إضافته إلى جهات اتصالك.';

  @override
  String get add_to_contacts => 'إضافة إلى جهات الاتصال';

  @override
  String get add_to_contacts_failed => 'تعذر فتح جهات الاتصال.';

  @override
  String get settings_share_profile_name => 'مشاركة اسم ملفي الشخصي';

  @override
  String get settings_share_profile_name_desc =>
      'فقط مع من تراسلهم مباشرة، ومشفّرًا من طرف إلى طرف. يراه من لا يحفظك في جهات اتصاله بصيغة ~الاسم.';

  @override
  String get view_once_message => 'رسالة لعرض واحد';

  @override
  String get message_no_longer_available => 'لم يعد بالإمكان فتح هذه الرسالة';

  @override
  String get view_once_video => 'فيديو لعرض واحد';

  @override
  String get view_once_file => 'ملف لعرض واحد';

  @override
  String get poll_view_once_unsupported =>
      'لا يمكن إرسال الاستطلاعات للعرض لمرة واحدة.';

  @override
  String get recovery_reminder_banner =>
      'أضف بريدًا للاسترداد حتى لا تفقد حسابك';

  @override
  String get identity_recovery_banner =>
      'لم تعد هوية هذا الجهاز تطابق حسابك، لذا لن تصلك رسائل جديدة. سجّل الدخول مجددًا ببريد الاسترداد.';

  @override
  String get profile_name_title => 'اسمك';

  @override
  String get profile_name_hint => 'الاسم الذي يراه من تراسلهم';

  @override
  String get profile_name_add => 'أضف اسمك';

  @override
  String get profile_name_edit => 'غيّر اسمك';

  @override
  String get profile_complete_title => 'أكمل ملفك الشخصي';

  @override
  String get profile_complete_description =>
      'لم تتم استعادة اسمك ورقمك مع حسابك. أدخلهما مرة أخرى ليتمكن الآخرون من العثور عليك ورؤية اسمك.';

  @override
  String get profile_complete_save => 'حفظ';

  @override
  String get profile_complete_later => 'ليس الآن';

  @override
  String get profile_complete_phone_mismatch =>
      'هذا الرقم لا يطابق حسابك. أدخل الرقم الذي سجلت به.';

  @override
  String get profile_complete_phone_taken => 'هذا الرقم يخص حسابًا آخر.';

  @override
  String get profile_complete_check_failed =>
      'تعذر التحقق من رقمك. تحقق من اتصالك وحاول مرة أخرى.';

  @override
  String get mention_suggestions_label => 'الأعضاء الذين يمكنك الإشارة إليهم';

  @override
  String get group_description => 'وصف المجموعة';

  @override
  String get group_description_add => 'إضافة وصف للمجموعة';

  @override
  String get group_photo_choose => 'اختيار صورة';

  @override
  String get group_photo_remove => 'إزالة الصورة';

  @override
  String get group_photo_change => 'تغيير صورة المجموعة';
}
