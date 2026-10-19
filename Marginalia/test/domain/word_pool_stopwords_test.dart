import 'package:flutter_test/flutter_test.dart';
import 'package:marginalia/data/remote/api.dart';
import 'package:marginalia/domain/stopwords.dart';
import 'package:marginalia/domain/word_pool.dart';

void main() {
  group('stopwords', () {
    test('function words are recognised, including possessives', () {
      for (final String w in <String>[
        'the', 'and', 'for', 'has', 'is', 'it\'s', 'don’t', 'The',
      ]) {
        expect(isStopword(w), isTrue, reason: w);
      }
    });

    test('ordinary vocabulary is not treated as a stopword', () {
      for (final String w in <String>[
        'threshold', 'history', 'people', 'make', 'need', 'first',
        'reader\'s',
      ]) {
        expect(isStopword(w), isFalse, reason: w);
      }
    });

    test('a pool loaded from an old database drops function words', () {
      final WordPool pool = WordPool(<WordEntry>[
        WordEntry(lemma: 'the', encounters: 9),
        WordEntry(lemma: 'harbour', encounters: 2),
        WordEntry(lemma: 'and', encounters: 7),
      ]);
      expect(pool.length, 1);
      expect(pool.all().single.lemma, 'harbour');
    });

    test('meeting a function word records nothing', () {
      final WordPool pool = WordPool(const <WordEntry>[]);
      pool.meet('for', '2026-10-17');
      expect(pool.length, 0);
      expect(pool.all(), isEmpty);
    });
  });

  group('WriterEndpoint.copyWith', () {
    test('overrides only what the reader set', () {
      final WriterEndpoint e = WriterEndpoint.deepseek
          .copyWith(model: 'deepseek-reasoner', baseUrl: 'https://example.com/v1');
      expect(e.model, 'deepseek-reasoner');
      expect(e.baseUrl, 'https://example.com/v1');
      expect(e.id, WriterEndpoint.deepseek.id);
      expect(e.supportsVision, WriterEndpoint.deepseek.supportsVision);
    });

    test('null keeps the provider defaults', () {
      final WriterEndpoint e = WriterEndpoint.mimo.copyWith();
      expect(e.model, WriterEndpoint.mimo.model);
      expect(e.baseUrl, WriterEndpoint.mimo.baseUrl);
    });
  });
}
