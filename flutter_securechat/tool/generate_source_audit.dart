import 'dart:io';

typedef AuditRule = ({
  RegExp pattern,
  String status,
  String target,
  String test,
  String decision,
});

typedef ProductionEvidence = ({String caller, String invariant});

void main() {
  final flutterRoot = Directory.current;
  final repositoryRoot = flutterRoot.parent;
  final sourceRoots = [
    'app',
    'crypto',
    'storage',
    'network',
    'media',
    'contacts',
  ];
  final sources = <String>[];
  for (final module in sourceRoots) {
    final root = Directory('${repositoryRoot.path}/$module/src/main/java');
    if (!root.existsSync()) continue;
    sources.addAll(
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (file) => file.path.endsWith('.kt') || file.path.endsWith('.java'),
          )
          .map((file) => _relative(file.path, repositoryRoot.path)),
    );
  }
  sources.sort();
  if (sources.length != 271) {
    throw StateError(
      'Expected 271 Kotlin/Java sources, found ${sources.length}',
    );
  }

  final dartGraph = _buildDartGraph(flutterRoot);
  final reachableDart = _reachableFrom('lib/main.dart', dartGraph);

  final rows =
      <({String source, AuditRule rule, ProductionEvidence evidence})>[];
  for (final source in sources) {
    final rule = _rules.firstWhere(
      (candidate) => candidate.pattern.hasMatch(source),
      orElse: () => throw StateError('No audit rule for $source'),
    );
    if (rule.target != '-' &&
        !File('${flutterRoot.path}/${rule.target}').existsSync()) {
      throw StateError('Missing target ${rule.target} for $source');
    }
    if (rule.test != '-' &&
        !File('${flutterRoot.path}/${rule.test}').existsSync()) {
      throw StateError('Missing test ${rule.test} for $source');
    }
    final evidence = _productionEvidence(
      source: source,
      rule: rule,
      flutterRoot: flutterRoot,
      graph: dartGraph,
      reachable: reachableDart,
    );
    rows.add((source: source, rule: rule, evidence: evidence));
  }

  final counts = <String, int>{};
  for (final row in rows) {
    counts.update(row.rule.status, (value) => value + 1, ifAbsent: () => 1);
  }
  final output = StringBuffer()
    ..writeln('# Kotlin -> Flutter Dosya-Seviyesi Audit Manifesti')
    ..writeln()
    ..writeln(
      'Bu dosya `tool/generate_source_audit.dart` ile uretilir. Kaynak sayisi,',
    )
    ..writeln(
      'hedef/test path varligi, production import reachability ve her kaynak',
    )
    ..writeln(
      'icin bir invariant bulunmasi generator tarafindan fail-fast dogrulanir.',
    )
    ..writeln('Davranis eslemesi sinif adi benzerligi degil, asagidaki ortak')
    ..writeln(
      'runtime/service hedefi ve `lib/main.dart`tan gelen caller zinciridir.',
    )
    ..writeln()
    ..writeln(
      'Durum ozeti: ${counts.entries.map((e) => '${e.key}=${e.value}').join(', ')}; toplam=${rows.length}.',
    )
    ..writeln()
    ..writeln(
      '| Kotlin/Java kaynak | Durum | Flutter/native karsiligi | Production caller | Kanit testi | Davranis / invariant |',
    )
    ..writeln('|---|---|---|---|---|---|');
  for (final row in rows) {
    final source = '[`${row.source}`](../../${row.source})';
    final target = row.rule.target == '-'
        ? '-'
        : '[`${row.rule.target}`](../${row.rule.target})';
    final test = row.rule.test == '-'
        ? '-'
        : '[`${row.rule.test}`](../${row.rule.test})';
    final caller = switch (row.evidence.caller) {
      '-' || 'ENTRYPOINT' || 'TEST_ONLY' => row.evidence.caller,
      final path => '[`$path`](../$path)',
    };
    output.writeln(
      '| $source | ${row.rule.status} | $target | $caller | $test | ${row.evidence.invariant} |',
    );
  }
  File(
    '${flutterRoot.path}/docs/SOURCE_AUDIT.md',
  ).writeAsStringSync(output.toString());
}

String _relative(String path, String root) =>
    path.substring(root.endsWith('/') ? root.length : root.length + 1);

Map<String, Set<String>> _buildDartGraph(Directory flutterRoot) {
  final graph = <String, Set<String>>{};
  final lib = Directory('${flutterRoot.path}/lib');
  final dartFiles = lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList(growable: false);
  final directive = RegExp(
    r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  for (final file in dartFiles) {
    final relative = _relative(file.path, flutterRoot.path);
    final dependencies = <String>{};
    for (final match in directive.allMatches(file.readAsStringSync())) {
      final reference = match.group(1)!;
      final resolved = _resolveDartReference(
        from: file,
        reference: reference,
        flutterRoot: flutterRoot,
      );
      if (resolved != null) dependencies.add(resolved);
    }
    graph[relative] = dependencies;
  }
  return graph;
}

String? _resolveDartReference({
  required File from,
  required String reference,
  required Directory flutterRoot,
}) {
  if (reference.startsWith('dart:') ||
      (reference.startsWith('package:') &&
          !reference.startsWith('package:flutter_securechat/'))) {
    return null;
  }
  if (reference.startsWith('package:flutter_securechat/')) {
    return 'lib/${reference.substring('package:flutter_securechat/'.length)}';
  }
  final resolved = File.fromUri(from.parent.uri.resolve(reference));
  if (!resolved.path.startsWith('${flutterRoot.path}/lib/')) return null;
  return _relative(resolved.path, flutterRoot.path);
}

Set<String> _reachableFrom(String entrypoint, Map<String, Set<String>> graph) {
  if (!graph.containsKey(entrypoint)) {
    throw StateError('Missing Dart entrypoint $entrypoint');
  }
  final reachable = <String>{};
  final pending = <String>[entrypoint];
  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    if (!reachable.add(current)) continue;
    for (final dependency in graph[current] ?? const <String>{}) {
      if (graph.containsKey(dependency)) pending.add(dependency);
    }
  }
  return reachable;
}

ProductionEvidence _productionEvidence({
  required String source,
  required AuditRule rule,
  required Directory flutterRoot,
  required Map<String, Set<String>> graph,
  required Set<String> reachable,
}) {
  if (rule.decision.trim().isEmpty) {
    throw StateError('Missing behavior invariant for $source');
  }
  if (rule.target == '-') {
    if (rule.status != 'DECISION') {
      throw StateError('Only DECISION may omit a production target: $source');
    }
    return (caller: '-', invariant: rule.decision);
  }
  if (rule.target.startsWith('test/')) {
    if (rule.status != 'MERGED') {
      throw StateError('Only a MERGED test fixture may be test-only: $source');
    }
    return (caller: 'TEST_ONLY', invariant: rule.decision);
  }
  if (rule.target.startsWith('lib/')) {
    if (!reachable.contains(rule.target)) {
      throw StateError(
        'Target ${rule.target} for $source is not reachable from lib/main.dart',
      );
    }
    if (rule.target == 'lib/main.dart') {
      return (caller: 'ENTRYPOINT', invariant: rule.decision);
    }
    final callers =
        graph.entries
            .where(
              (entry) =>
                  reachable.contains(entry.key) &&
                  entry.value.contains(rule.target),
            )
            .map((entry) => entry.key)
            .toList(growable: false)
          ..sort();
    if (callers.isEmpty) {
      throw StateError(
        'No direct production caller for ${rule.target} ($source)',
      );
    }
    return (caller: callers.first, invariant: rule.decision);
  }

  final manifest = rule.target.contains('/src/debug/')
      ? 'android/app/src/debug/AndroidManifest.xml'
      : 'android/app/src/main/AndroidManifest.xml';
  final manifestFile = File('${flutterRoot.path}/$manifest');
  if (!manifestFile.existsSync()) {
    throw StateError('Missing platform caller manifest for $source');
  }
  final simpleName = rule.target.split('/').last.replaceAll('.kt', '');
  if (!manifestFile.readAsStringSync().contains(simpleName)) {
    throw StateError('$manifest does not register $simpleName for $source');
  }
  return (caller: manifest, invariant: rule.decision);
}

AuditRule _rule(
  String pattern,
  String status,
  String target,
  String test,
  String decision,
) => (
  pattern: RegExp(pattern),
  status: status,
  target: target,
  test: test,
  decision: decision,
);

final _rules = <AuditRule>[
  _rule(
    r'app/.*/diagnostics/HybridLegacyTelemetry\.kt$',
    'DECISION',
    '-',
    '-',
    'Flutter plaintext legacy envelope kabul etmez; guvenlik nedeniyle bu sayac ve legacy yol tasinmadi.',
  ),
  _rule(
    r'app/.*/diagnostics/(CrashLogFormatter|CrashReporter)\.kt$',
    'COVERED',
    'lib/src/diagnostics/crash_reporter.dart',
    'test/crash_reporter_test.dart',
    'App-private JSON rapor, whitelist/redaction, atomik yazim, rotation, paylasma ve temizleme.',
  ),
  _rule(
    r'app/.*/monitoring/',
    'COVERED',
    'lib/src/diagnostics/crash_reporter.dart',
    'test/crash_reporter_test.dart',
    'Non-fatal reporter production container ve Flutter/root/platform global handlerlarina bagli.',
  ),
  _rule(
    r'app/.*/debug/CallNotificationTester\.kt$',
    'COVERED',
    'lib/src/debug/notification_debug_harness.dart',
    'test/notification_debug_harness_test.dart',
    "kDebugMode-only incoming/missed/message notification harness production containerdan release'te cikar.",
  ),
  _rule(
    r'app/.*/debug/TestNotificationReceiver\.kt$',
    'PLATFORM',
    'android/app/src/debug/kotlin/com/securechat/app/debug/TestNotificationReceiver.kt',
    'test/notification_debug_harness_test.dart',
    'ADB receiver yalniz Android debug source-set/manifestte; release manifestine birlesmez.',
  ),
  _rule(
    r'app/.*/data/MissedCallTracker\.kt$',
    'COVERED',
    'lib/src/notifications/missed_call_tracker.dart',
    'test/missed_call_tracker_test.dart',
    '30 saniye dedup timer, conversation unread, private bildirim ve voice/video callback bagli.',
  ),
  _rule(
    r'app/.*/data/NotifDismissReceiver\.kt$',
    'COVERED',
    'lib/src/notifications/message_notification_service.dart',
    'test/message_notification_module_test.dart',
    'Tap/dismiss ve foreground active-notification reconciliation tekli/summary sayaclarini temizler.',
  ),
  _rule(
    r'app/.*/ui/components/CallQualityIndicator\.kt$',
    'COVERED',
    'lib/src/features/calls/call_quality_indicator.dart',
    'test/call_quality_indicator_test.dart',
    'Uc cubuk kalite gostergesi, reconnect pulse/banner ve video-kapat sesli-devam aksiyonu bagli.',
  ),
  _rule(
    r'network/.*/(NetworkMonitor|NetworkTypeProvider)\.kt$',
    'COVERED',
    'lib/src/network/network_monitor.dart',
    'test/network_monitor_module_test.dart',
    'Android/iOS sistem ag akisi socket reconnect ve auto-download policy girdisine bagli.',
  ),
  _rule(
    r'network/.*/(WebSocketDebugger|ServerCompatibilityChecker)\.kt$',
    'COVERED',
    'lib/src/network/socket_diagnostics.dart',
    'test/socket_diagnostics_test.dart',
    'Pinli client ile health/authenticated WebSocket probe; token, user, header ve body rapora girmez.',
  ),
  _rule(
    r'network/.*/telemetry/',
    'COVERED',
    'lib/src/network/socket_diagnostics.dart',
    'test/socket_diagnostics_test.dart',
    'Iceriksiz connection/failure/reconnect/auth sayaclari production signaling yoluna bagli.',
  ),
  _rule(
    r'app/.*/data/BackgroundBlurStore\.kt$|media/.*/BackgroundBlurProcessor\.kt$',
    'DECISION',
    '-',
    '-',
    'Kotlin production CallManager CPU blur processorunu acikca no-op/emergency-disabled tutar; devre disi karar korundu.',
  ),
  _rule(
    r'network/.*/P2PMessageTransport\.kt$',
    'DECISION',
    '-',
    '-',
    'Kotlin production graphinda kullanilmayan alternatif WebRTC data-channel transportu; signaling tasimasi korunur.',
  ),
  _rule(
    r'app/.*/data/DemoDataSeeder\.kt$',
    'MERGED',
    'test/support/test_app_container.dart',
    'test/widget_test.dart',
    'Kotlin demo seeder yalniz test fixture verisine eslendi; production kaynak ve bootstrap demo veri icermez.',
  ),
  _rule(
    r'app/.*/backup/|app/.*/ui/screen/Backup|app/.*/Backup',
    'COVERED',
    'lib/src/backup/backup_service.dart',
    'test/backup_module_test.dart',
    'Crypto, restore, account check ve UI ortak backup modülünde.',
  ),
  _rule(
    r'app/.*/crypto/(GroupSenderKey|PreKeyBundle|SessionEnsurer)',
    'COVERED',
    'lib/src/crypto/signal_protocol_crypto_service.dart',
    'test/signal_protocol_crypto_service_test.dart',
    'Signal session/SenderKey production servisine birlestirildi.',
  ),
  _rule(
    r'app/.*/crypto/OneToOneFileCipherImpl',
    'COVERED',
    'lib/src/media/file_transfer_manager.dart',
    'test/media_module_test.dart',
    'Dosya chunk AEAD transfer katmaninda.',
  ),
  _rule(
    r'app/.*/data/(AppLifecycleObserver|BootReceiver|DisappearingMessageWorker|PendingTimerFlusher|SenderKeyRotationWorker|WebSocketDrainWorker)',
    'PLATFORM',
    'lib/src/background/background_tasks.dart',
    'test/background_module_test.dart',
    'WorkManager/BGTask ve foreground catch-up ortak background runtime icine birlestirildi.',
  ),
  _rule(
    r'app/.*/data/(AuthInterceptor|UserIdentityProviderImpl|UserSession)\.kt$',
    'COVERED',
    'lib/src/services/session_store.dart',
    'test/auth_flow_test.dart',
    'Token/session/identity provider encrypted session ve auth coordinator ile.',
  ),
  _rule(
    r'app/.*/data/(AutoDownloadDecider|AutoDownloadPolicy|AutoDownloadPolicyStore|ChatStorageAnalyzer)',
    'COVERED',
    'lib/src/storage/storage_management_service.dart',
    'test/storage_management_module_test.dart',
    'Policy ve analiz encrypted storage service icinde.',
  ),
  _rule(
    r'app/.*/data/(ExportBannerAckStore|OnboardingAckStore)',
    'COVERED',
    'lib/src/onboarding/onboarding_service.dart',
    'test/onboarding_module_test.dart',
    'Ack state encrypted cryptoState bolgesinde.',
  ),
  _rule(
    r'app/.*/data/(FcmTokenManager|SecureChatFcmService)',
    'PLATFORM',
    'lib/src/push/push_service.dart',
    'test/push_module_test.dart',
    'FCM/APNs ortak metadata-only push coordinator ile.',
  ),
  _rule(
    r'app/.*/data/CallActionReceiver',
    'PLATFORM',
    'android/app/src/main/kotlin/com/securechat/app/SecureChatConnectionService.kt',
    'test/media_module_test.dart',
    'Android Telecom action native bridge uzerinden Dart state machine e aktarilir.',
  ),
  _rule(
    r'app/.*/data/PreKeyUploader',
    'COVERED',
    'lib/src/auth/auth_coordinator.dart',
    'test/auth_flow_test.dart',
    'Registration sonrasi authenticated prekey upload akisi.',
  ),
  _rule(
    r'app/.*/data/IncomingMessageHandler|app/.*/data/incoming/',
    'COVERED',
    'lib/src/incoming/incoming_message_handler.dart',
    'test/incoming_module_test.dart',
    'Parser ve typed handlerlar tek fail-closed incoming orchestrator icinde.',
  ),
  _rule(
    r'app/.*/di/',
    'MERGED',
    'lib/src/services/app_container.dart',
    'test/services_test.dart',
    'Hilt providerlari explicit AppContainer composition root ile degistirildi.',
  ),
  _rule(
    r'app/.*/domain/error/',
    'MERGED',
    'lib/src/domain/send_message_use_case.dart',
    'test/send_message_use_case_test.dart',
    'Typed send sonucu ve exception sinirlari use-case icinde.',
  ),
  _rule(
    r'app/.*/domain/usecase/(AddGroupMember|PromoteToAdmin|RemoveGroupMember|SetGroupReadOnly|ToggleExportPolicy|UpdateGroupName)',
    'COVERED',
    'lib/src/groups/group_management_service.dart',
    'test/group_management_module_test.dart',
    'Grup yetki/mutation use-case leri ortak serviste.',
  ),
  _rule(
    r'app/.*/domain/usecase/(MarkAsRead|MarkConversationAsUnread|ObserveMessages)',
    'COVERED',
    'lib/src/chat/read_receipt_service.dart',
    'test/read_receipt_module_test.dart',
    'DAO read/unread ve receipt rezervasyon akisi.',
  ),
  _rule(
    r'app/.*/domain/usecase/PinMessage',
    'COVERED',
    'lib/src/chat/message_interaction_service.dart',
    'test/message_interaction_test.dart',
    'Admin kontrollu pin/unpin interaction servisine birlestirildi.',
  ),
  _rule(
    r'app/.*/domain/usecase/RecordExportEvent',
    'COVERED',
    'lib/src/export/export_audit_service.dart',
    'test/backup_module_test.dart',
    'Encrypted admin audit fanout servisine birlestirildi.',
  ),
  _rule(
    r'app/.*/domain/usecase/SendMessage',
    'COVERED',
    'lib/src/domain/send_message_use_case.dart',
    'test/send_message_use_case_test.dart',
    'No-plaintext-fallback production gonderim use-case i.',
  ),
  _rule(
    r'app/.*/navigation/|app/.*/SecureChatActivity|app/.*/IncomingCallActivity',
    'PLATFORM',
    'lib/src/app.dart',
    'test/widget_test.dart',
    'Compose Activity/NavHost yerine Flutter route tree; incoming call Telecom/CallKit ile acilir.',
  ),
  _rule(
    r'app/.*/SecureChatApplication',
    'MERGED',
    'lib/src/services/app_container.dart',
    'test/services_test.dart',
    'Application/Hilt baslatma async Flutter composition root a tasindi.',
  ),
  _rule(
    r'app/.*/resolver/|app/.*/usecase/UpdateContactNames',
    'COVERED',
    'lib/src/contacts/contact_service.dart',
    'test/contact_service_test.dart',
    'Native contact sync/name resolution ortak contact servisinde.',
  ),
  _rule(
    r'app/.*/scheduler/',
    'PLATFORM',
    'lib/src/background/scheduled_message_service.dart',
    'test/background_module_test.dart',
    'Alarm/receiver/worker davranisi Android WorkManager ve iOS BGTask scheduler ile.',
  ),
  _rule(
    r'app/.*/ui/components/(AvatarGenerator|EmptyStateView|ErrorDialog|GlassComponents|SecurityBadge|ThemeManager)',
    'MERGED',
    'lib/src/theme/secure_chat_theme.dart',
    'test/accessibility_responsive_test.dart',
    'Compose presentational componentleri Flutter theme/widget ve ekranlara birlestirildi.',
  ),
  _rule(
    r'app/.*/ui/components/OngoingCallBar',
    'COVERED',
    'lib/src/features/calls/ongoing_call_bar.dart',
    'test/ongoing_call_bar_test.dart',
    'Aktif/connecting arama global route bandi, sure ve tap-to-return davranisiyla tasindi.',
  ),
  _rule(
    r'app/.*/ui/components/(CallControls|CallReadinessBanner|VideoRenderer)',
    'MERGED',
    'lib/src/features/calls/call_screen.dart',
    'test/media_module_test.dart',
    'Call presentation ve RTC renderer call screen/state icinde.',
  ),
  _rule(
    r'app/.*/ui/components/ConnectionStatusIndicator|app/.*/ui/components/RefreshableContent',
    'MERGED',
    'lib/src/features/conversations/conversations_screen.dart',
    'test/network_resilience_test.dart',
    'Connection state ve refresh UI ana conversation akisi icinde.',
  ),
  _rule(
    r'app/.*/ui/components/CountryCodePicker|app/.*/ui/util/(PhoneFormValidation|PhoneVisualTransformation)',
    'MERGED',
    'lib/src/features/auth/auth_screen.dart',
    'test/auth_flow_test.dart',
    'Telefon giris/normalize/validation ortak auth formunda.',
  ),
  _rule(
    r'app/.*/ui/components/Haptic',
    'COVERED',
    'lib/src/widgets/haptics.dart',
    'test/haptics_test.dart',
    'Send, message long-press, swipe threshold ve call controls haptic davranisi tasindi.',
  ),
  _rule(
    r'app/.*/ui/components/(MessageDateDivider|SecureChatActionSheet|Shimmer|TypingIndicator)',
    'MERGED',
    'lib/src/features/chat/chat_screen.dart',
    'test/widget_test.dart',
    'Compose mikro-bilesen davranislari Flutter Material chat widgetlarina birlestirildi.',
  ),
  _rule(
    r'app/.*/ui/screen/(PhoneVerification|OtpVerification|EmailOtp|Splash)Screen|app/.*/ui/screen/OtpApiClient',
    'MERGED',
    'lib/src/features/auth/auth_screen.dart',
    'test/auth_flow_test.dart',
    'Auth asamalari tek stateful Flutter auth/launch akisinda.',
  ),
  _rule(
    r'app/.*/ui/screen/(Onboarding|PermissionWalkthrough)Screen',
    'MERGED',
    'lib/src/features/onboarding/launch_flow.dart',
    'test/onboarding_module_test.dart',
    'Onboarding ve platform izin adimlari ortak launch flow icinde.',
  ),
  _rule(
    r'app/.*/ui/screen/(CreateGroup|AddGroupMember|GroupInfo)Screen',
    'MERGED',
    'lib/src/features/groups/group_info_screen.dart',
    'test/group_management_module_test.dart',
    'Grup olusturma/uye/admin akislarinin UI ve servisi.',
  ),
  _rule(
    r'app/.*/ui/screen/AutoDownloadSettingsScreen',
    'COVERED',
    'lib/src/features/settings/auto_download_screen.dart',
    'test/storage_management_module_test.dart',
    'Policy UI eslemesi.',
  ),
  _rule(
    r'app/.*/ui/screen/BulkMessageScreen',
    'COVERED',
    'lib/src/features/bulk/bulk_message_screen.dart',
    'test/bulk_message_module_test.dart',
    'Guvenli alici bazli bulk send UI.',
  ),
  _rule(
    r'app/.*/ui/screen/(CallHistory|CallReadiness|Call)Screen|app/.*/ui/screen/call/',
    'COVERED',
    'lib/src/features/calls/call_screen.dart',
    'test/media_module_test.dart',
    'Call route/state/controls; history/readiness ayri Flutter routelarinda.',
  ),
  _rule(
    r'app/.*/ui/screen/ChatInfoScreen',
    'COVERED',
    'lib/src/features/chat/chat_info_screen.dart',
    'test/chat_info_module_test.dart',
    'Chat info filtre/preference/timer UI.',
  ),
  _rule(
    r'app/.*/ui/screen/ChatScreen|app/.*/ui/screen/chat/',
    'COVERED',
    'lib/src/features/chat/chat_screen.dart',
    'test/message_interaction_test.dart',
    'Chat banner/input/bubble/view-once davranislari ortak ekranda.',
  ),
  _rule(
    r'app/.*/ui/screen/ContactsScreen',
    'COVERED',
    'lib/src/features/contacts/contacts_screen.dart',
    'test/contact_service_test.dart',
    'Rehber/discovery UI.',
  ),
  _rule(
    r'app/.*/ui/screen/ConversationsScreen',
    'COVERED',
    'lib/src/features/conversations/conversations_screen.dart',
    'test/conversation_management_module_test.dart',
    'Sohbet listesi yonetimi.',
  ),
  _rule(
    r'app/.*/ui/screen/ExportHistoryScreen',
    'COVERED',
    'lib/src/features/export/export_history_screen.dart',
    'test/backup_module_test.dart',
    'Admin audit history UI.',
  ),
  _rule(
    r'app/.*/ui/screen/MediaPreviewScreen',
    'COVERED',
    'lib/src/features/chat/media_preview_screen.dart',
    'test/media_preview_module_test.dart',
    'Picker preview/caption/view-once UI.',
  ),
  _rule(
    r'app/.*/ui/screen/ScheduledMessagesScreen',
    'COVERED',
    'lib/src/features/scheduled/scheduled_messages_screen.dart',
    'test/background_module_test.dart',
    'Planli mesaj CRUD UI.',
  ),
  _rule(
    r'app/.*/ui/screen/SettingsScreen',
    'COVERED',
    'lib/src/features/settings/settings_screen.dart',
    'test/settings_module_test.dart',
    'Encrypted preference/account UI.',
  ),
  _rule(
    r'app/.*/ui/screen/StorageUsageScreen',
    'COVERED',
    'lib/src/features/settings/storage_usage_screen.dart',
    'test/storage_management_module_test.dart',
    'Storage analiz/cleanup UI.',
  ),
  _rule(
    r'app/.*/ui/theme/viewmodel/OngoingCallBarViewModel',
    'MERGED',
    'lib/src/features/calls/ongoing_call_bar.dart',
    'test/ongoing_call_bar_test.dart',
    'CallManager session streami global arama bandi ve lokal sure tickerini besler.',
  ),
  _rule(
    r'app/.*/ui/theme/viewmodel/(CallViewModel|CallHistoryViewModel)',
    'MERGED',
    'lib/src/media/call_manager.dart',
    'test/media_module_test.dart',
    'ViewModel state Dart service streamleri ve StatefulWidget tarafindan sahiplenilir.',
  ),
  _rule(
    r'app/.*/ui/theme/viewmodel/(AddGroupMember|CreateGroup|GroupInfo)ViewModel',
    'MERGED',
    'lib/src/groups/group_management_service.dart',
    'test/group_management_module_test.dart',
    'Grup state/use-case service icinde.',
  ),
  _rule(
    r'app/.*/ui/theme/viewmodel/(AutoDownload|StorageUsage)ViewModel',
    'MERGED',
    'lib/src/storage/storage_management_service.dart',
    'test/storage_management_module_test.dart',
    'Storage state service + StatefulWidget icinde.',
  ),
  _rule(
    r'app/.*/ui/theme/viewmodel/BulkMessageViewModel',
    'MERGED',
    'lib/src/bulk/bulk_message_service.dart',
    'test/bulk_message_module_test.dart',
    'Bulk state service icinde.',
  ),
  _rule(
    r'app/.*/ui/theme/viewmodel/ChatInfoViewModel',
    'MERGED',
    'lib/src/chat/chat_info_service.dart',
    'test/chat_info_module_test.dart',
    'Chat-info state service icinde.',
  ),
  _rule(
    r'app/.*/ui/theme/viewmodel/ChatViewModel|app/.*/ui/viewmodel/chat/',
    'MERGED',
    'lib/src/chat/message_interaction_service.dart',
    'test/message_interaction_test.dart',
    'Chat alt yoneticileri interaction/read-receipt/incoming servislerine bolundu.',
  ),
  _rule(
    r'app/.*/ui/theme/viewmodel/ContactsViewModel',
    'MERGED',
    'lib/src/contacts/contact_service.dart',
    'test/contact_service_test.dart',
    'Contact state service/stream icinde.',
  ),
  _rule(
    r'app/.*/ui/theme/viewmodel/ConversationsViewModel',
    'MERGED',
    'lib/src/services/conversation_repository.dart',
    'test/conversation_management_module_test.dart',
    'Conversation state repository streaminde.',
  ),
  _rule(
    r'app/.*/ui/theme/viewmodel/ExportHistoryViewModel',
    'MERGED',
    'lib/src/export/export_audit_service.dart',
    'test/backup_module_test.dart',
    'Export history state DAO/service icinde.',
  ),
  _rule(
    r'app/.*/ui/theme/viewmodel/ScheduledMessageViewModel',
    'MERGED',
    'lib/src/background/scheduled_message_service.dart',
    'test/background_module_test.dart',
    'Planli mesaj state service icinde.',
  ),
  _rule(
    r'app/.*/ui/theme/viewmodel/SettingsViewModel',
    'MERGED',
    'lib/src/settings/settings_service.dart',
    'test/settings_module_test.dart',
    'Settings state encrypted service streaminde.',
  ),
  _rule(
    r'app/.*/ui/theme/',
    'MERGED',
    'lib/src/theme/secure_chat_theme.dart',
    'test/accessibility_responsive_test.dart',
    'Compose token/type/glass/backdrop ThemeData ve AzureBackdrop a birlestirildi.',
  ),
  _rule(
    r'app/.*/ui/util/(FileOpenHelper|BatteryOptimizationHelper|CallReadinessHelper)',
    'PLATFORM',
    'lib/src/platform/native_bridge.dart',
    'test/call_readiness_module_test.dart',
    'Platform intent/permission davranisi method-channel ile.',
  ),
  _rule(
    r'app/.*/ui/util/TimeFormatter',
    'MERGED',
    'lib/src/features/chat/chat_screen.dart',
    'test/widget_test.dart',
    'Dart DateTime/localization formatlamasi ekranlarda.',
  ),
  _rule(
    r'app/.*/util/(FileOpenHelper|BatteryOptimizationHelper|CallReadinessHelper)',
    'PLATFORM',
    'lib/src/platform/native_bridge.dart',
    'test/call_readiness_module_test.dart',
    'Platform intent/permission davranisi method-channel ile.',
  ),
  _rule(
    r'app/.*/util/(PhoneVisualTransformation|TimeFormatter)',
    'MERGED',
    'lib/src/features/auth/auth_screen.dart',
    'test/auth_flow_test.dart',
    'Dart input/date presentation icine birlestirildi.',
  ),
  _rule(
    r'app/src/main/java/com/securechat/telecom/',
    'PLATFORM',
    'android/app/src/main/kotlin/com/securechat/app/SecureChatConnectionService.kt',
    'test/media_module_test.dart',
    'Android self-managed Telecom; iOS CallKit AppDelegate; Dart CallManager cift yonlu.',
  ),
  _rule(
    r'contacts/',
    'COVERED',
    'lib/src/contacts/contact_service.dart',
    'test/contact_service_test.dart',
    'Model/repository/permission/hash/discovery tek cross-platform contact modulunde.',
  ),
  _rule(
    r'crypto/.*/CallCryptoManager|crypto/.*/model/CallEncryptionKeys',
    'COVERED',
    'lib/src/crypto/call_crypto_manager.dart',
    'test/crypto_module_test.dart',
    'Call key derive ve zeroize.',
  ),
  _rule(
    r'crypto/.*/KeyStoreManager',
    'PLATFORM',
    'lib/src/services/key_material_store.dart',
    'test/crypto_module_test.dart',
    'Android Keystore/iOS Keychain master material wrapper.',
  ),
  _rule(
    r'crypto/.*/(MessageEncryptor|PreKeyManager|SecureChatProtocolStore|SecureChatSenderKeyStore|SessionManager)|crypto/.*/store/|crypto/.*/model/(EncryptedEnvelope|KeyBundle)|crypto/.*/ByteArrayExt',
    'COVERED',
    'lib/src/crypto/signal_protocol_crypto_service.dart',
    'test/libsignal_wire_compat_test.dart',
    'Signal V3 records/wire/store saf-Dart runtime ve Java 2.8.1 capraz testinde.',
  ),
  _rule(
    r'crypto/.*/di/',
    'MERGED',
    'lib/src/services/app_container.dart',
    'test/crypto_module_test.dart',
    'DI explicit composition root ile.',
  ),
  _rule(
    r'media/.*/BackgroundBlurProcessor',
    'DECISION',
    '-',
    '-',
    'Kotlin production yolunda emergency-disabled no-op.',
  ),
  _rule(
    r'media/.*/(AudioStreamer|VideoStreamer|CallAudioManager|CallManager|IncomingCallHandler|RingtonePlayer)|media/.*/model/',
    'COVERED',
    'lib/src/media/call_manager.dart',
    'test/media_module_test.dart',
    'WebRTC media, audio route, call state ve ringtone native/plugin katmaninda.',
  ),
  _rule(
    r'media/.*/(CallForegroundService|CallNotificationManager)',
    'PLATFORM',
    'lib/src/media/native_call_integration.dart',
    'test/android_call_notification_contract_test.dart',
    'Android tek-ID CallStyle yasam dongusu ve iOS CallKit ortak typed native action katmanina bagli.',
  ),
  _rule(
    r'media/.*/FileTransferManager|media/.*/crypto/',
    'COVERED',
    'lib/src/media/file_transfer_manager.dart',
    'test/media_module_test.dart',
    'Encrypted chunk transfer ve cipher sozlesmesi.',
  ),
  _rule(
    r'media/.*/di/',
    'MERGED',
    'lib/src/services/app_container.dart',
    'test/media_module_test.dart',
    'DI explicit composition root ile.',
  ),
  _rule(
    r'network/.*/IceServerFetcher',
    'COVERED',
    'lib/src/media/ice_server_fetcher.dart',
    'test/media_module_test.dart',
    'Authenticated dynamic ICE/TURN fetch.',
  ),
  _rule(
    r'network/.*/JanusClient',
    'COVERED',
    'lib/src/media/janus_client.dart',
    'test/media_module_test.dart',
    'Janus VideoRoom protocol/runtime.',
  ),
  _rule(
    r'network/.*/OfflineMessageQueue|network/.*/StuckMessageRecovery',
    'COVERED',
    'lib/src/network/network_resilience.dart',
    'test/network_resilience_test.dart',
    'Encrypted offline queue/stuck recovery.',
  ),
  _rule(
    r'network/.*/PeerConnectionManager|network/.*/model/(CallAction|CallType|PeerState)',
    'COVERED',
    'lib/src/media/media_engine.dart',
    'test/media_module_test.dart',
    'flutter_webrtc engine ve call state modelleri.',
  ),
  _rule(
    r'network/.*/SignalMessage|network/.*/model/(ConnectionState|DecryptedMessage|GroupAction|PendingMessage)',
    'COVERED',
    'lib/src/core/signal_message.dart',
    'test/services_test.dart',
    'Typed signaling union ve domain modelleri.',
  ),
  _rule(
    r'network/.*/SignalingClient',
    'COVERED',
    'lib/src/services/signaling_service.dart',
    'test/network_resilience_test.dart',
    'Bearer WebSocket, reconnect/backoff ve typed decode.',
  ),
  _rule(
    r'network/.*/di/',
    'MERGED',
    'lib/src/services/app_container.dart',
    'test/network_resilience_test.dart',
    'DI explicit composition root ile.',
  ),
  _rule(
    r'storage/.*/crypto/|storage/.*/dao/|storage/.*/entity/|storage/.*/model/|storage/.*/Converters',
    'COVERED',
    'lib/src/storage/secure_chat_database.dart',
    'test/legacy_room_migration_test.dart',
    'Encrypted DAO/entity ve Room v1-v22 binary import eslemesi.',
  ),
  _rule(
    r'storage/.*/(DataCleanupManager|SecureChatDatabase)',
    'COVERED',
    'lib/src/storage/secure_chat_database.dart',
    'test/storage_management_module_test.dart',
    'Atomik encrypted snapshot ve scoped cleanup.',
  ),
  _rule(
    r'storage/.*/di/',
    'MERGED',
    'lib/src/services/app_container.dart',
    'test/services_test.dart',
    'Room/Hilt composition explicit container ve native legacy importer ile.',
  ),
  _rule(
    r'storage/.*/domain/',
    'COVERED',
    'lib/src/core/models.dart',
    'test/services_test.dart',
    'Conversation/LocalMessage ortak domain modelleri.',
  ),
  _rule(
    r'storage/.*/repository/',
    'COVERED',
    'lib/src/services/conversation_repository.dart',
    'test/services_test.dart',
    'Repository DAO-backed stream/send adapteri.',
  ),
  _rule(
    r'storage/.*/resolver/',
    'COVERED',
    'lib/src/contacts/contact_service.dart',
    'test/contact_service_test.dart',
    'Contact display-name resolution.',
  ),
];
