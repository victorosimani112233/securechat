import 'package:flutter/material.dart';

import '../features/calls/call_history_screen.dart';
import '../features/contacts/contacts_screen.dart';
import '../features/conversations/conversations_screen.dart';
import '../features/settings/settings_screen.dart';
import '../l10n/l10n.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  late final PageController _pages;
  int? _swipePointer;
  Offset? _swipeOrigin;
  int _swipeOriginPage = 0;

  static const _screens = [
    ConversationsScreen(embedded: true),
    CallHistoryScreen(embedded: true),
    ContactsScreen(embedded: true),
    SettingsScreen(embedded: true),
  ];

  @override
  void initState() {
    super.initState();
    _pages = PageController();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _select(int value) async {
    if (value == _index || !_pages.hasClients) return;
    await _pages.animateToPage(
      value,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _rememberSwipe(PointerDownEvent event) {
    if (_swipePointer != null) return;
    _swipePointer = event.pointer;
    _swipeOrigin = event.position;
    _swipeOriginPage = _index;
  }

  void _completeSwipe(PointerUpEvent event) {
    if (_swipePointer != event.pointer || _swipeOrigin == null) return;
    final delta = event.position - _swipeOrigin!;
    final origin = _swipeOrigin!;
    final originPage = _swipeOriginPage;
    _clearSwipe();
    if (delta.dx.abs() < 72 || delta.dx.abs() <= delta.dy.abs() * 1.25) {
      return;
    }
    // PageView normally owns horizontal gestures. This raw-pointer path is
    // only an edge fallback for children such as a horizontal Dismissible;
    // limiting it to the edge prevents a chat archive/delete swipe from also
    // changing the selected tab.
    final width = MediaQuery.sizeOf(context).width;
    final direction = Directionality.of(context);
    final forward = direction == TextDirection.ltr
        ? delta.dx < 0
        : delta.dx > 0;
    final fromForwardEdge = direction == TextDirection.ltr
        ? origin.dx >= width - 72
        : origin.dx <= 72;
    final fromBackEdge = direction == TextDirection.ltr
        ? origin.dx <= 72
        : origin.dx >= width - 72;
    if ((forward && !fromForwardEdge) || (!forward && !fromBackEdge)) return;
    final target = (originPage + (forward ? 1 : -1)).clamp(
      0,
      _screens.length - 1,
    );
    if (target != originPage) _select(target);
  }

  void _cancelSwipe(PointerCancelEvent event) {
    if (_swipePointer == event.pointer) _clearSwipe();
  }

  void _clearSwipe() {
    _swipePointer = null;
    _swipeOrigin = null;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index != 0) _select(0);
      },
      child: Scaffold(
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _rememberSwipe,
          onPointerUp: _completeSwipe,
          onPointerCancel: _cancelSwipe,
          child: PageView.builder(
            key: const ValueKey('main-horizontal-pager'),
            controller: _pages,
            itemCount: _screens.length,
            allowImplicitScrolling: true,
            physics: const PageScrollPhysics(),
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (_, index) => _KeepAlivePage(child: _screens[index]),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.chat_bubble_outline),
              selectedIcon: const Icon(Icons.chat_bubble),
              label: context.l10n.nav_chats,
            ),
            NavigationDestination(
              icon: const Icon(Icons.call_outlined),
              selectedIcon: const Icon(Icons.call),
              label: context.l10n.nav_calls,
            ),
            NavigationDestination(
              icon: const Icon(Icons.contacts_outlined),
              selectedIcon: const Icon(Icons.contacts),
              label: context.l10n.nav_contacts,
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: context.l10n.settings_title,
            ),
          ],
        ),
      ),
    );
  }
}

class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
