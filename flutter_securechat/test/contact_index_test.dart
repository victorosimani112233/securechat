import 'package:flutter_securechat/src/contacts/contact_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('names sort in Turkish alphabet order with symbols last', () {
    final names = [
      'Zeynep',
      'Şule',
      'selin',
      'Çağrı',
      'can',
      'İlker',
      'ırmak',
      'Ömer',
      'oya',
      'Ümit',
      'Uğur',
      '+90 532',
      '~ayşe',
      'Ğ',
      'gül',
    ]..sort(compareContactNames);
    expect(names, [
      '~ayşe',
      'can',
      'Çağrı',
      'gül',
      'Ğ',
      'ırmak',
      'İlker',
      'oya',
      'Ömer',
      'selin',
      'Şule',
      'Uğur',
      'Ümit',
      'Zeynep',
      '+90 532',
    ]);
  });

  test('groups carry their letter and keep "#" at the end', () {
    final groups = groupContactsByLetter([
      'ilker',
      'Işık',
      '123',
      'Ahmet',
      'ali',
      'Âdem',
      'Wanda',
    ], (name) => name);
    expect(groups.map((group) => group.letter), ['A', 'I', 'İ', 'W', '#']);
    expect(groups.first.items, ['Âdem', 'Ahmet', 'ali']);
    expect(groups.last.items, ['123']);
    expect(contactIndexLetter('  '), contactIndexOther);
    expect(contactIndexLetter('😀 Parti'), contactIndexOther);
  });
}
