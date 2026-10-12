import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/widgets/avatar.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresyon: sohbet listesinde farkli kisiler ayni harfe dusuyordu.
///
/// Bas harfler yalnizca BOSLUKTAN bolunuyordu. "QA_Test_Mehmet",
/// "QA_Grup_1" ve "qa-peer-01" hepsi tek "Q" gosteriyordu; cihazda dort
/// sohbet ayni monogramla goruldu. Gruplar da kisilerle ayni gorunuyordu,
/// bu yuzden yanlis sohbete girmek kolaydi.
void main() {
  test('ad ayiricilari bosluk disinda da bolunur', () {
    expect(GeneratedAvatar.initialsOf('Ayse Demir'), 'AD');
    expect(GeneratedAvatar.initialsOf('QA_Test_Mehmet'), 'QT');
    expect(GeneratedAvatar.initialsOf('qa-peer-01'), 'QP');
    expect(GeneratedAvatar.initialsOf('ali.veli'), 'AV');
  });

  test('tek parcali ad tek harf verir, bos ad cokmemeli', () {
    expect(GeneratedAvatar.initialsOf('Mehmet'), 'M');
    expect(GeneratedAvatar.initialsOf(''), '');
    expect(GeneratedAvatar.initialsOf('   '), '');
    expect(GeneratedAvatar.initialsOf('---'), '');
  });

  test('harf olmayan parcalar atlanir', () {
    expect(GeneratedAvatar.initialsOf('+90 532 000'), '95');
  });

  testWidgets('grup avatari monogram yerine grup ikonu gosterir', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [
            GeneratedAvatar(name: 'QA_Grup_1', isGroup: true),
            GeneratedAvatar(name: 'QA_Test_Ayse'),
          ],
        ),
      ),
    );
    expect(find.byIcon(Icons.groups), findsOneWidget);
    expect(find.text('QT'), findsOneWidget);
    expect(
      find.text('Q'),
      findsNothing,
      reason: 'iki sohbet ayni tek harfe dusmemeli',
    );
  });

  // QA 2026-10-12 Bulgu 4: numara "9", UUID "33" gibi anlamsiz bas harf
  // gosteriyordu; adi olmayan kisi icin kisi simgesi gosterilir.
  testWidgets('a nameless contact shows a person icon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [
            GeneratedAvatar(name: '+90 532 100 04 13'),
            GeneratedAvatar(name: '3b3663e9-3046-4ba9-acd6-dfdaf3fa510c'),
            GeneratedAvatar(name: ''),
            GeneratedAvatar(name: '~QaAlfa'),
          ],
        ),
      ),
    );
    expect(find.byIcon(Icons.person), findsNWidgets(3));
    expect(find.text('9'), findsNothing);
    expect(find.text('33'), findsNothing);
    expect(find.text('Q'), findsOneWidget);
  });
}
