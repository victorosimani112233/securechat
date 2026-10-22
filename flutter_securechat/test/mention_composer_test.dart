import 'package:flutter/services.dart';
import 'package:flutter_securechat/src/chat/mention_composer.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _at(String text, [int? cursor]) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: cursor ?? text.length),
);

void main() {
  const ayse = MentionCandidate(userId: 'u-ayse', label: 'Ayşe Yılmaz');
  const ismail = MentionCandidate(userId: 'u-ismail', label: 'İsmail');
  const veli = MentionCandidate(userId: 'u-veli', label: 'Veli');

  test('a mention opens only after a space or at the start', () {
    expect(activeMentionQuery(_at('@'))?.text, '');
    expect(activeMentionQuery(_at('selam @ay'))?.text, 'ay');
    expect(activeMentionQuery(_at('selam @ay'))?.start, 6);
    // E-posta adresindeki "@" bahsetme degil.
    expect(activeMentionQuery(_at('mail ali@ornek')), isNull);
    // Secim yapmadan bosluk yazilinca liste kapanir.
    expect(activeMentionQuery(_at('@ay ')), isNull);
    expect(activeMentionQuery(_at('merhaba')), isNull);
    // Imlec "@" oncesindeyse bahsetme yok.
    expect(activeMentionQuery(_at('a @ay', 1)), isNull);
    // Secili metin varken oneri acilmaz.
    expect(
      activeMentionQuery(
        const TextEditingValue(
          text: '@ay',
          selection: TextSelection(baseOffset: 0, extentOffset: 3),
        ),
      ),
      isNull,
    );
  });

  test('candidates match any word and ignore Turkish case', () {
    final all = [veli, ismail, ayse];
    expect(filterMentionCandidates(all, ''), [ayse, ismail, veli]);
    expect(filterMentionCandidates(all, 'yıl'), [ayse]);
    expect(filterMentionCandidates(all, 'YIL'), [ayse]);
    expect(filterMentionCandidates(all, 'is'), [ismail]);
    expect(filterMentionCandidates(all, 'İS'), [ismail]);
    expect(filterMentionCandidates(all, 'zz'), isEmpty);
    final many = [
      for (var i = 0; i < 10; i++)
        MentionCandidate(userId: 'u$i', label: 'Üye $i'),
    ];
    expect(filterMentionCandidates(many, ''), hasLength(6));
  });

  test('picking a member replaces the query and moves the cursor', () {
    final value = _at('selam @ay nasılsın', 9);
    final query = activeMentionQuery(value)!;
    final next = insertMention(value, query, ayse);
    expect(next.text, 'selam @Ayşe Yılmaz  nasılsın');
    expect(next.selection.baseOffset, 'selam @Ayşe Yılmaz '.length);
  });

  test('only mentions still in the text are sent', () {
    final picked = {'u-ayse': 'Ayşe Yılmaz', 'u-veli': 'Veli'};
    expect(resolveMentionedUserIds('@Ayşe Yılmaz ve @Veli gelin', picked), [
      'u-ayse',
      'u-veli',
    ]);
    // Kullanici "@Veli" yazisini sildiyse Veli bahsedilmis sayilmaz.
    expect(resolveMentionedUserIds('@Ayşe Yılmaz gel', picked), ['u-ayse']);
    expect(resolveMentionedUserIds('kimse yok', picked), isEmpty);
  });

  test('known names are highlighted whole, others by their first word', () {
    String marked(String text, List<String> labels) {
      final buffer = StringBuffer();
      var cursor = 0;
      for (final range in findMentionRanges(text, labels)) {
        buffer
          ..write(text.substring(cursor, range.start))
          ..write('[${range.textInside(text)}]');
        cursor = range.end;
      }
      return (buffer..write(text.substring(cursor))).toString();
    }

    const labels = ['Ayşe Yılmaz', 'Ayşe', '+905432112345'];
    // En uzun bilinen ad tamamen alinir; harf buyuklugu onemsiz.
    expect(
      marked('Selam @ayşe yılmaz, nasılsın', labels),
      'Selam [@ayşe yılmaz], nasılsın',
    );
    expect(marked('@+905432112345 gel', labels), '[@+905432112345] gel');
    // Bilinmeyen ad: ilk kelime, sondaki noktalama haric.
    expect(marked('Tamam @Mehmet!', labels), 'Tamam [@Mehmet]!');
    // Kelime icindeki "@" (e-posta) bahsetme degil.
    expect(marked('ali@ornek.com yaz', labels), 'ali@ornek.com yaz');
    // Ad bir kelimenin basiysa tam ad sayilmaz.
    expect(marked('@Ayşegül geldi', labels), '[@Ayşegül] geldi');
    expect(marked('tek @ isaret', labels), 'tek @ isaret');
    expect(marked('@A ve @B', const []), '[@A] ve [@B]');
  });
}
