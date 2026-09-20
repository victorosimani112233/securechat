import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../onboarding/permission_service.dart';
import '../../services/app_container.dart';
import '../../widgets/azure_backdrop.dart';
import '../../theme/secure_chat_theme.dart';

class LaunchScreen extends StatefulWidget {
  const LaunchScreen({super.key});
  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  Future<void> _route() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    _pulse.stop();
    final container = AppContainerScope.of(context);
    final onboarding = container.onboardingRuntime?.service;
    final route = onboarding == null
        ? (container.session.isLoggedIn ? '/' : '/auth')
        : !await onboarding.isIntroSeen()
        ? '/onboarding'
        : !await onboarding.isPermissionWalkthroughSeen()
        ? '/permissions'
        : container.session.isLoggedIn
        ? '/'
        : '/auth';
    if (mounted) Navigator.pushReplacementNamed(context, route);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AzureBackdrop(
    child: Scaffold(
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: Tween(begin: .55, end: 1.0).animate(_pulse),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/splash_logo.png',
                  width: 130,
                  height: 130,
                ),
                const SizedBox(height: 24),
                Text(
                  'elçim.',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(context.l10n.secure_communication),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  var _page = 0;
  Future<void> _finish() async {
    await AppContainerScope.of(
      context,
    ).onboardingRuntime?.service.markIntroSeen();
    if (mounted) Navigator.pushReplacementNamed(context, '/permissions');
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      (
        Icons.lock,
        const Color(0xFF1F8E3D),
        context.l10n.chat_e2ee,
        context.l10n.onboarding_private_subtitle,
        context.l10n.onboarding_private_body,
      ),
      (
        Icons.phone,
        const Color(0xFF3E7BFA),
        context.l10n.onboarding_direct_call,
        context.l10n.onboarding_webrtc_subtitle,
        context.l10n.onboarding_webrtc_body,
      ),
      (
        Icons.shield,
        const Color(0xFFEF6C00),
        context.l10n.onboarding_privacy_control,
        context.l10n.onboarding_you_decide,
        context.l10n.onboarding_privacy_body,
      ),
    ];
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(
          actions: [
            if (_page < 2)
              TextButton(onPressed: _finish, child: Text(context.l10n.skip)),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: pages.length,
                  onPageChanged: (value) => setState(() => _page = value),
                  itemBuilder: (_, index) {
                    final p = pages[index];
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxHeight < 460;
                        final avatarRadius = compact ? 48.0 : 64.0;
                        return SingleChildScrollView(
                          padding: EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: compact ? 16 : 32,
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight:
                                  constraints.maxHeight - (compact ? 32 : 64),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: avatarRadius,
                                  backgroundColor: p.$2.withValues(alpha: .18),
                                  child: Icon(
                                    p.$1,
                                    size: avatarRadius,
                                    color: p.$2,
                                  ),
                                ),
                                SizedBox(height: compact ? 24 : 40),
                                Text(
                                  p.$3,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineMedium,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  p.$4,
                                  style: TextStyle(
                                    color: p.$2,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 20),
                                Text(p.$5, textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PageIndicators(
                      currentPage: _page,
                      pageCount: pages.length,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        key: const ValueKey('onboarding-continue'),
                        onPressed: _page == 2
                            ? _finish
                            : () => _controller.nextPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              ),
                        child: Text(
                          _page == 2
                              ? context.l10n.lets_start
                              : context.l10n.continue_action,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageIndicators extends StatelessWidget {
  const _PageIndicators({required this.currentPage, required this.pageCount});

  final int currentPage;
  final int pageCount;

  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('onboarding-page-indicators'),
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var index = 0; index < pageCount; index++) ...[
        if (index > 0) const SizedBox(width: 8),
        AnimatedContainer(
          key: ValueKey('onboarding-page-indicator-$index'),
          duration: const Duration(milliseconds: 220),
          width: index == currentPage ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: index == currentPage
                ? Theme.of(context).colorScheme.primary
                : Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: .3),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    ],
  );
}

class PermissionWalkthroughScreen extends StatefulWidget {
  const PermissionWalkthroughScreen({super.key});
  @override
  State<PermissionWalkthroughScreen> createState() =>
      _PermissionWalkthroughScreenState();
}

class _PermissionWalkthroughScreenState
    extends State<PermissionWalkthroughScreen> {
  final _granted = <String, bool>{};
  String? _busy;

  Future<void> _request(String key) async {
    setState(() => _busy = key);
    var granted = false;
    try {
      final permission = AppPermission.values.where(
        (permission) => permission.name == key,
      );
      final service = AppContainerScope.of(
        context,
      ).onboardingRuntime?.permissions;
      granted = permission.isNotEmpty && service != null
          ? await service.request(permission.first)
          : false;
    } catch (_) {}
    if (mounted)
      setState(() {
        _granted[key] = granted;
        _busy = null;
      });
  }

  Future<void> _finish() async {
    final container = AppContainerScope.of(context);
    await container.onboardingRuntime?.service.markPermissionWalkthroughSeen();
    if (mounted)
      Navigator.pushReplacementNamed(
        context,
        container.session.isLoggedIn ? '/' : '/auth',
      );
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'notifications',
        Icons.notifications,
        context.l10n.notifications,
        context.l10n.notifications_permission_reason,
      ),
      (
        'contacts',
        Icons.contacts,
        context.l10n.nav_contacts,
        context.l10n.contacts_permission_reason,
      ),
      (
        'microphone',
        Icons.mic,
        context.l10n.microphone,
        context.l10n.microphone_permission_reason,
      ),
      (
        'camera',
        Icons.camera_alt,
        context.l10n.camera,
        context.l10n.camera_permission_reason,
      ),
    ];
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(title: Text(context.l10n.permissions_required)),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(context.l10n.permissions_intro),
              const SizedBox(height: 20),
              for (final item in items)
                Card(
                  child: _PermissionRow(
                    icon: Icon(item.$2),
                    title: item.$3,
                    reason: item.$4,
                    action: _granted[item.$1] == true
                        ? const Icon(Icons.check_circle, color: AzureTokens.ok)
                        : _busy == item.$1
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: () => _request(item.$1),
                            child: Text(context.l10n.grant_permission),
                          ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy == null ? _finish : null,
                child: Text(context.l10n.continue_action),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Izin satiri: eylem normalde sagda durur, sigmadigi zaman metnin altina iner.
///
/// Neden ozel widget: `ListTile` trailing widget'i satir genisligini asarsa
/// layout sirasinda assert atar ("Trailing widget consumes the entire tile
/// width") ve ekran hic cizilemez. Dar bir telefonda %200 metin olceginde
/// "Izin ver" butonu tam olarak bunu yapiyordu; yani erisilebilirlik ayari
/// acik olan kullanici kurulumun ilk ekranini goremiyordu. Almanca/Arapca gibi
/// daha uzun etiketlerde ayni sinir normal olcekte de zorlanir.
class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.reason,
    required this.action,
  });

  final Widget icon;
  final String title;
  final String reason;
  final Widget action;

  /// Eylemin yanina sigabilmesi icin metne birakilmasi gereken en az genislik.
  static const _minimumTextWidth = 120.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(reason, style: theme.textTheme.bodyMedium),
      ],
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actionWidth = _measureActionWidth(context);
          final fitsBeside =
              constraints.maxWidth - actionWidth - 48 >= _minimumTextWidth;
          if (fitsBeside) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                icon,
                const SizedBox(width: 16),
                Expanded(child: texts),
                const SizedBox(width: 8),
                action,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  icon,
                  const SizedBox(width: 16),
                  Expanded(child: texts),
                ],
              ),
              const SizedBox(height: 8),
              Align(alignment: AlignmentDirectional.centerEnd, child: action),
            ],
          );
        },
      ),
    );
  }

  /// Eylemin kaplayacagi genisligi olcer. Ikon ve gostergenin boyutu sabittir;
  /// buton metinle birlikte buyudugu icin gercek metin genisligi olculur.
  double _measureActionWidth(BuildContext context) {
    final button = action;
    if (button is! TextButton) return 32;
    final label = button.child;
    if (label is! Text) return 32;
    final painter = TextPainter(
      text: TextSpan(
        text: label.data ?? '',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    // TextButton'un varsayilan yatay ic bosluklari.
    return painter.width + 32;
  }
}
