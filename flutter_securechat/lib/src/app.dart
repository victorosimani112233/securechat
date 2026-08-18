import 'dart:async';

import 'package:flutter/material.dart';

import 'features/auth/auth_screen.dart';
import 'l10n/generated/app_localizations.dart';
import 'features/backup/backup_screen.dart';
import 'features/bulk/bulk_message_screen.dart';
import 'features/calls/call_screen.dart';
import 'features/calls/call_readiness_screen.dart';
import 'features/calls/ongoing_call_bar.dart';
import 'features/chat/chat_screen.dart';
import 'features/chat/chat_info_screen.dart';
import 'features/contacts/contacts_screen.dart';
import 'features/export/export_history_screen.dart';
import 'features/groups/group_info_screen.dart';
import 'features/onboarding/launch_flow.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/auto_download_screen.dart';
import 'features/settings/storage_usage_screen.dart';
import 'features/scheduled/scheduled_messages_screen.dart';
import 'core/models.dart';
import 'services/app_container.dart';
import 'settings/settings_service.dart';
import 'theme/secure_chat_theme.dart';
import 'widgets/main_shell.dart';

class SecureChatFlutterApp extends StatefulWidget {
  const SecureChatFlutterApp({super.key, required this.container});

  final AppContainer container;

  @override
  State<SecureChatFlutterApp> createState() => _SecureChatFlutterAppState();
}

class _SecureChatFlutterAppState extends State<SecureChatFlutterApp>
    with WidgetsBindingObserver {
  StreamSubscription<AppSettingsState>? _settingsSubscription;
  StreamSubscription<String>? _notificationTapSubscription;
  StreamSubscription<void>? _callOpenSubscription;
  late ThemeMode _themeMode;
  Locale? _locale;
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final _AppNavigatorObserver _navigatorObserver;
  String? _activeRoute;
  String? _pendingNotificationConversationId;
  bool _pendingCallOpen = false;

  @override
  void initState() {
    super.initState();
    _themeMode = _themeModeFor(
      widget.container.settingsRuntime?.service.current.theme ??
          AppThemePreference.system,
    );
    _locale = _localeFor(
      widget.container.settingsRuntime?.service.current.language ??
          _languagePreferenceFor(widget.container.session.languagePreference),
    );
    _navigatorObserver = _AppNavigatorObserver(_onRouteChanged);
    _settingsSubscription = widget.container.settingsRuntime?.service.states
        .listen((settings) {
          if (!mounted) return;
          setState(() {
            _themeMode = _themeModeFor(settings.theme);
            _locale = _localeFor(settings.language);
          });
        });
    final notifications = widget.container.notificationRuntime?.coordinator;
    notifications?.setAppForeground(true);
    _notificationTapSubscription = notifications?.taps.listen(
      _openNotificationConversation,
    );
    _callOpenSubscription = widget.container.mediaRuntime?.calls.openRequests
        .listen((_) => _openCallScreen());
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = widget.container.lifecycleRuntime;
    if (lifecycle != null) {
      _runLifecycle(lifecycle.enterForeground());
    } else {
      _runLifecycle(
        widget.container.backgroundRuntime?.runForegroundMaintenance() ??
            Future.value(),
      );
    }
  }

  @override
  void dispose() {
    _settingsSubscription?.cancel();
    _notificationTapSubscription?.cancel();
    _callOpenSubscription?.cancel();
    _navigatorObserver.dispose();
    _runLifecycle(widget.container.dispose());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.container.notificationRuntime?.coordinator.setAppForeground(true);
      _runLifecycle(
        widget.container.lifecycleRuntime?.enterForeground() ?? Future.value(),
      );
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.container.notificationRuntime?.coordinator.setAppForeground(false);
      _runLifecycle(
        widget.container.lifecycleRuntime?.enterBackground() ?? Future.value(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppContainerScope(
      container: widget.container,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        navigatorObservers: [_navigatorObserver],
        title: 'Elcim',
        locale: _locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        debugShowCheckedModeBanner: false,
        theme: SecureChatTheme.light(),
        darkTheme: SecureChatTheme.dark(),
        themeMode: _themeMode,
        builder: (context, child) {
          final calls = widget.container.mediaRuntime?.calls;
          return OngoingCallAppFrame(
            activeRoute: _navigatorObserver.activeRoute,
            initialSession: calls?.currentSession,
            sessions: calls?.sessions,
            onReturnToCall: _openCallScreen,
            child: child ?? const SizedBox.shrink(),
          );
        },
        routes: {
          '/launch': (_) => const LaunchScreen(),
          '/onboarding': (_) => const OnboardingScreen(),
          '/permissions': (_) => const PermissionWalkthroughScreen(),
          '/bulk-message': (_) => const BulkMessageScreen(),
          '/auth': (_) => const AuthScreen(),
          '/': (_) => const MainShell(),
          '/chat': (_) => const ChatScreen(),
          '/contacts': (_) => const ContactsScreen(),
          '/calls': (_) => const CallScreen(),
          '/call-readiness': (_) => const CallReadinessScreen(),
          '/settings': (_) => const SettingsScreen(),
          '/scheduled-messages': (_) => const ScheduledMessagesScreen(),
          '/backup': (_) => const BackupScreen(),
          '/export-history': (_) => const ExportHistoryScreen(),
          '/group-info': (_) => const GroupInfoScreen(),
          '/auto-download': (_) => const AutoDownloadScreen(),
          '/storage-usage': (_) => const StorageUsageScreen(),
          '/chat-info': (_) => const ChatInfoScreen(),
        },
        initialRoute: '/launch',
        onGenerateInitialRoutes: (_) => [
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/launch'),
            builder: (_) => const LaunchScreen(),
          ),
        ],
      ),
    );
  }

  Future<void> _openNotificationConversation(String conversationId) async {
    if (conversationId.isEmpty) return;
    if (_activeRoute == null || _activeRoute == '/launch') {
      _pendingNotificationConversationId = conversationId;
      return;
    }
    final conversations = await widget.container.conversations
        .watchConversations()
        .first;
    final conversation = conversations.where(
      (item) => item.id == conversationId || item.peerId == conversationId,
    );
    final selected = conversation.isEmpty
        ? Conversation(
            id: conversationId,
            peerId: conversationId,
            peerName: conversationId,
            peerPhone: '',
          )
        : conversation.first;
    if (!mounted) return;
    _navigatorKey.currentState?.pushNamed('/chat', arguments: selected);
  }

  void _openCallScreen() {
    if (!mounted || _activeRoute == '/calls') return;
    if (_activeRoute == null || _activeRoute == '/launch') {
      _pendingCallOpen = true;
      return;
    }
    _navigatorKey.currentState?.pushNamed('/calls');
  }

  void _onRouteChanged(String? routeName) {
    _activeRoute = routeName;
    if (routeName == null || routeName == '/launch') return;
    final pending = _pendingNotificationConversationId;
    final openCall = _pendingCallOpen;
    _pendingCallOpen = false;
    if (pending != null) _pendingNotificationConversationId = null;
    if (pending == null && !openCall) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (openCall) {
        _openCallScreen();
      } else if (pending != null) {
        unawaited(_openNotificationConversation(pending));
      }
    });
  }
}

class _AppNavigatorObserver extends NavigatorObserver {
  _AppNavigatorObserver(this.onRouteChanged);

  final ValueChanged<String?> onRouteChanged;
  final activeRoute = ValueNotifier<String?>(null);

  void _setActiveRoute(String? routeName) {
    activeRoute.value = routeName;
    onRouteChanged(routeName);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _setActiveRoute(route.settings.name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _setActiveRoute(previousRoute?.settings.name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _setActiveRoute(newRoute?.settings.name);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _setActiveRoute(previousRoute?.settings.name);
  }

  void dispose() => activeRoute.dispose();
}

ThemeMode _themeModeFor(AppThemePreference preference) => switch (preference) {
  AppThemePreference.light => ThemeMode.light,
  AppThemePreference.dark => ThemeMode.dark,
  AppThemePreference.system => ThemeMode.system,
};

Locale? _localeFor(AppLanguagePreference preference) => switch (preference) {
  AppLanguagePreference.tr => const Locale('tr'),
  AppLanguagePreference.en => const Locale('en'),
  AppLanguagePreference.de => const Locale('de'),
  AppLanguagePreference.ar => const Locale('ar'),
  AppLanguagePreference.system => null,
};

AppLanguagePreference _languagePreferenceFor(String value) => switch (value) {
  'tr' => AppLanguagePreference.tr,
  'en' => AppLanguagePreference.en,
  'de' => AppLanguagePreference.de,
  'ar' => AppLanguagePreference.ar,
  _ => AppLanguagePreference.system,
};

void _runLifecycle(Future<void> operation) {
  unawaited(operation.catchError((_) {}));
}
