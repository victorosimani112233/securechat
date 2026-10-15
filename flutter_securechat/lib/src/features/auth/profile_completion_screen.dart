import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../contacts/contact_service.dart';
import '../../contacts/profile_name_sharing_service.dart';
import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../services/session_store.dart';

/// Oturum acik ama ad veya numara yoksa ana ekran yerine profil tamamlama.
///
/// E-postayla kurtarma yeni bir cihazda eski (bos) oturumun adini ve
/// numarasini tasiyordu; sunucu numarayi yalniz karma olarak tuttugu icin
/// geri veremez. Numara olmadan numara paylasimi ve kendi numarani rehberde
/// bulma calismiyor (QA 2026-10-13 O5).
String homeRouteFor(SessionStore session) =>
    session.isLoggedIn && profileIncomplete(session) ? '/profile' : '/';

bool profileIncomplete(SessionStore session) =>
    (session.displayName?.trim() ?? '').isEmpty ||
    (session.phoneNumber?.trim() ?? '').isEmpty;

class ProfileCompletionScreen extends StatefulWidget {
  const ProfileCompletionScreen({super.key, this.phoneStatus});

  /// Testler icin; verilmezse kapsayicidaki [ContactService] kullanilir.
  final Future<OwnPhoneStatus> Function(String phone)? phoneStatus;

  @override
  State<ProfileCompletionScreen> createState() =>
      _ProfileCompletionScreenState();
}

class _ProfileCompletionScreenState extends State<ProfileCompletionScreen> {
  final _name = TextEditingController();
  final _countryCode = TextEditingController(text: '+90');
  final _phone = TextEditingController();
  bool _initialized = false;
  bool _busy = false;
  String? _nameError;
  String? _countryCodeError;
  String? _phoneError;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final session = AppContainerScope.of(context).session;
    _name.text = session.displayName?.trim() ?? '';
    final phone = session.phoneNumber?.trim() ?? '';
    final match = RegExp(r'^(\+[0-9]{1,4}?)([0-9]{10})$').firstMatch(phone);
    if (match != null) {
      _countryCode.text = match.group(1)!;
      _phone.text = match.group(2)!;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _countryCode.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _goHome() =>
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);

  Future<void> _save() async {
    if (_busy) return;
    final l10n = context.l10n;
    final name = ProfileNameSharingService.sanitize(_name.text);
    final country = _countryCode.text.trim();
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    setState(() {
      _error = null;
      _nameError = name == null
          ? l10n.validation_name_empty
          : name.length < 2
          ? l10n.validation_name_too_short(2)
          : null;
      _countryCodeError = RegExp(r'^\+[0-9]{1,4}$').hasMatch(country)
          ? null
          : l10n.validation_country_code_non_digit;
      _phoneError = digits.length < 10
          ? l10n.validation_phone_too_short
          : digits.length > 10
          ? l10n.validation_phone_too_long
          : null;
    });
    if (_nameError != null ||
        _countryCodeError != null ||
        _phoneError != null) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final container = AppContainerScope.of(context);
    final phone = '$country$digits';
    final check = widget.phoneStatus ?? container.contacts?.ownPhoneStatus;
    setState(() => _busy = true);
    try {
      final status = check == null ? null : await check(phone);
      if (!mounted) return;
      if (status != OwnPhoneStatus.matches) {
        setState(
          () => _phoneError = status == OwnPhoneStatus.otherAccount
              ? l10n.profile_complete_phone_taken
              : status == OwnPhoneStatus.notRegistered
              ? l10n.profile_complete_phone_mismatch
              : l10n.profile_complete_check_failed,
        );
        return;
      }
      final session = container.session;
      session.displayName = name;
      session.phoneNumber = phone;
      await session.persist();
      if (mounted) _goHome();
    } catch (error, stackTrace) {
      await container.diagnosticsRuntime?.reporter.recordException(
        error,
        stackTrace,
        context: 'profile.complete',
      );
      if (mounted) setState(() => _error = l10n.profile_complete_check_failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(l10n.profile_complete_title),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_busy) ...[
                      LinearProgressIndicator(semanticsLabel: l10n.loading),
                      const SizedBox(height: 16),
                    ],
                    Text(l10n.profile_complete_description),
                    const SizedBox(height: 24),
                    TextField(
                      key: const ValueKey('profile-complete-name'),
                      controller: _name,
                      enabled: !_busy,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      maxLength: ProfileNameSharingService.maxNameLength,
                      onChanged: (_) => setState(() => _nameError = null),
                      decoration: InputDecoration(
                        labelText: l10n.register_name_label,
                        errorText: _nameError,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 90,
                          child: TextField(
                            key: const ValueKey('profile-complete-country'),
                            controller: _countryCode,
                            enabled: !_busy,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(5),
                            ],
                            onChanged: (_) =>
                                setState(() => _countryCodeError = null),
                            decoration: InputDecoration(
                              labelText: l10n.register_country_code_label,
                              errorText: _countryCodeError,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            key: const ValueKey('profile-complete-phone'),
                            controller: _phone,
                            enabled: !_busy,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [
                              AutofillHints.telephoneNumberNational,
                            ],
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                            onChanged: (_) =>
                                setState(() => _phoneError = null),
                            onSubmitted: (_) => _save(),
                            decoration: InputDecoration(
                              labelText: l10n.register_phone_label,
                              hintText: l10n.register_phone_placeholder,
                              errorText: _phoneError,
                              errorMaxLines: 3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          key: const ValueKey('profile-complete-error'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const ValueKey('profile-complete-save'),
                      onPressed: _busy ? null : _save,
                      child: Text(l10n.profile_complete_save),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      key: const ValueKey('profile-complete-later'),
                      onPressed: _busy ? null : _goHome,
                      child: Text(l10n.profile_complete_later),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
