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
}
