import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/contacts/contact_service.dart';
import 'package:flutter_securechat/src/features/backup/backup_screen.dart';
import 'package:flutter_securechat/src/features/chat/chat_screen.dart';
import 'package:flutter_securechat/src/features/contacts/contacts_screen.dart';
import 'package:flutter_securechat/src/features/settings/about_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/settings/settings_service.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_securechat/src/widgets/main_shell.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  testWidgets('theme dialog Back does not restore inactive Contacts search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = _navigationContainer(_NavigationContacts());
    await tester.pumpWidget(SecureChatFlutterApp(container: container));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(MainShell)));
    final contactsTab = find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(Icons.contacts_outlined),
    );
    await tester.tap(contactsTab);
    await tester.pumpAndSettle();
    final search = find.descendant(
      of: find.byType(ContactsScreen),
      matching: find.byType(TextField),
    );
    await tester.enterText(search, 'QA102nosuchperson');
    await tester.pumpAndSettle();
    final field = tester.widget<EditableText>(
      find.descendant(of: search, matching: find.byType(EditableText)),
    );
    expect(field.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.drag(
      find.byKey(const ValueKey('main-horizontal-pager')),
      const Offset(-350, 0),
    );
    await tester.pumpAndSettle();
    expect(_selectedTab(tester), 3);
    expect(field.focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(find.text(l10n.settings_chat_theme));
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsNothing);
    expect(_selectedTab(tester), 3);
    expect(
      field.focusNode.hasFocus,
      isFalse,
      reason: 'Dialog focus restoration must exclude offscreen Contacts',
    );
    expect(tester.testTextInput.isVisible, isFalse);
    expect(
      container.settingsRuntime!.service.current.theme,
      AppThemePreference.dark,
    );

    await tester.tap(contactsTab);
    await tester.pumpAndSettle();
    expect(_selectedTab(tester), 2);
    expect(field.controller.text, 'QA102nosuchperson');
    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(field.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  for (final (createGroup, swipe) in [
    (false, false),
    (true, false),
    (false, true),
    (true, true),
  ]) {
    testWidgets('leaving Contacts dismisses search focus and IME: '
        'group flow $createGroup, swipe $swipe', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final contacts = _NavigationContacts();
      await tester.pumpWidget(
        SecureChatFlutterApp(container: _navigationContainer(contacts)),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(tester.element(find.byType(MainShell)));
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byIcon(Icons.contacts_outlined),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.byType(ContactsScreen),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, 'Ayse');
      await tester.pumpAndSettle();
      final focus = tester
          .widget<EditableText>(
            find.descendant(of: search, matching: find.byType(EditableText)),
          )
          .focusNode;
      expect(focus.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);

      if (createGroup) {
        await _createGroupFromContacts(tester, l10n);
        expect(find.byType(ChatScreen), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(_selectedTab(tester), 2);
      }
      if (swipe) {
        await tester.drag(
          find.byKey(const ValueKey('main-horizontal-pager')),
          const Offset(-350, 0),
        );
      } else {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.byIcon(Icons.settings_outlined),
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(
        {
          'selectedTab': _selectedTab(tester),
          'contactsSearchFocused': focus.hasFocus,
          'textInputVisible': tester.testTextInput.isVisible,
        },
        {
          'selectedTab': 3,
          'contactsSearchFocused': false,
          'textInputVisible': false,
        },
        reason:
            'A kept-alive Contacts search must not retain the IME on Settings',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  for (final bottomInset in [0.0, 72.0, 135.0]) {
    testWidgets(
      'bottom navigation semantics respect physical system inset $bottomInset',
      (tester) async {
        const physicalSize = Size(1080, 2340);
        const pixelRatio = 3.0;
        tester.view.physicalSize = physicalSize;
        tester.view.devicePixelRatio = pixelRatio;
        tester.view.padding = FakeViewPadding(top: 72, bottom: bottomInset);
        tester.view.viewPadding = FakeViewPadding(top: 72, bottom: bottomInset);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        await tester.pumpWidget(
          SecureChatFlutterApp(container: createWidgetTestContainer()),
        );
        await tester.pumpAndSettle();
        final navigation = find.byType(NavigationBar);
        final labels = tester
            .widget<NavigationBar>(navigation)
            .destinations
            .cast<NavigationDestination>()
            .map((destination) => destination.label)
            .toList();
        final physicalSafeBottom = physicalSize.height - bottomInset;
        for (var index = 0; index < labels.length; index++) {
          final node = tester.getSemantics(
            find.descendant(of: navigation, matching: find.text(labels[index])),
          );
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          final bounds = _physicalSemanticsRect(node);
          expect(
            bounds.bottom,
            lessThanOrEqualTo(physicalSafeBottom + 0.01),
            reason: '${labels[index]} must exclude the system navigation strip',
          );
          expect(bounds.center.dy, lessThan(physicalSafeBottom));
          await tester.tapAt(bounds.center / pixelRatio);
          await tester.pumpAndSettle();
          expect(_selectedTab(tester), index);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  for (final submenu in ['backup', 'about']) {
    for (final systemBack in [false, true]) {
      testWidgets('settings submenu return preserves tab after group creation: '
          '$submenu, ${systemBack ? 'system' : 'app bar'} back', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final contacts = _NavigationContacts();
        final container = _navigationContainer(contacts);
        await tester.pumpWidget(SecureChatFlutterApp(container: container));
        await tester.pumpAndSettle();
        final shellState = tester.state(find.byType(MainShell));
        final l10n = AppLocalizations.of(
          tester.element(find.byType(MainShell)),
        );

        Future<void> selectTab(IconData icon, int expected) async {
          await tester.tap(
            find.descendant(
              of: find.byType(NavigationBar),
              matching: find.byIcon(icon),
            ),
          );
          await tester.pumpAndSettle();
          expect(_selectedTab(tester), expected);
        }

        await selectTab(Icons.contacts_outlined, 2);
        await _createGroupFromContacts(tester, l10n);
        expect(contacts.created, 1);
        expect(find.byType(ChatScreen), findsOneWidget);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(_selectedTab(tester), 2);
        await selectTab(Icons.settings_outlined, 3);
        final menuLabel = submenu == 'backup'
            ? l10n.settings_backup
            : l10n.settings_about;
        await tester.scrollUntilVisible(
          find.text(menuLabel),
          200,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('settings-list')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(menuLabel));
        await tester.pumpAndSettle();

        if (submenu == 'backup') {
          expect(find.byType(BackupScreen), findsOneWidget);
          await tester.tap(find.text(l10n.create_backup));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          await tester.tap(find.text(l10n.cancel));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.byType(BackupScreen), findsOneWidget);
        } else {
          expect(find.byType(AboutScreen), findsOneWidget);
        }

        if (systemBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.byType(BackButton));
        }
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(MainShell)), same(shellState));
        expect(
          _selectedTab(tester),
          3,
          reason: 'Returning from Settings must not restore Contacts',
        );
        expect(
          tester.widget<PageView>(find.byType(PageView)).controller!.page,
          3,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }
}

int _selectedTab(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

AppContainer _navigationContainer(_NavigationContacts contacts) {
  final base = createWidgetTestContainer();
  return AppContainer.testing(
    session: base.session,
    conversations: base.conversations,
    crypto: base.crypto,
    signaling: base.signaling,
    contacts: contacts,
    settingsRuntime: AppSettingsRuntime(service: _NavigationSettings()),
    chatAccessRuntime: base.chatAccessRuntime,
    callReadinessRuntime: base.callReadinessRuntime,
  );
}

Future<void> _createGroupFromContacts(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  await tester.tap(find.text(l10n.create_group_title));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('new-group-name')),
    'Navigation group',
  );
  await tester.pump();
  await tester.tap(find.text(l10n.continue_action));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('recipient-peer-ayse')));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('recipient-confirm')));
  await tester.pumpAndSettle();
}

// The root semantics transform includes the view's device-pixel ratio.
Rect _physicalSemanticsRect(SemanticsNode node) {
  var rect = node.rect;
  for (
    SemanticsNode? ancestor = node;
    ancestor != null;
    ancestor = ancestor.parent
  ) {
    final transform = ancestor.transform;
    if (transform != null) rect = MatrixUtils.transformRect(transform, rect);
  }
  return rect;
}

class _NavigationContacts extends Fake implements ContactService {
  static const _contact = ContactEntity(
    id: 'peer-ayse',
    displayName: 'Ayse Demir',
    phoneNumber: '+905320000001',
    phoneHash: 'navigation-test',
    isRegistered: true,
  );
  int created = 0;

  @override
  Stream<List<ContactEntity>> watchRegistered() => Stream.value([_contact]);

  @override
  Future<List<ContactEntity>> importAndDiscover() async => [_contact];

  @override
  Future<ConversationEntity> createGroup(
    String name,
    List<ContactEntity> members,
  ) async {
    created++;
    return ConversationEntity(
      id: 'group-ops',
      peerId: 'group-ops',
      peerName: name,
      peerPhone: '',
      isGroup: true,
      groupMembers: 'me,peer-ayse',
      groupAdmins: 'me',
    );
  }
}

class _NavigationSettings extends Fake implements SettingsService {
  @override
  AppSettingsState get current => const AppSettingsState(
    theme: AppThemePreference.dark,
    language: AppLanguagePreference.tr,
    showNotificationContent: true,
    notificationSound: NotificationSoundPreference.flow,
    useDoodleBackground: true,
    fullscreenMode: false,
    scheduledMessagesEnabled: true,
    shareLastSeen: true,
    profilePhotoPath: null,
  );

  @override
  Stream<AppSettingsState> get states => Stream.value(current);
}
