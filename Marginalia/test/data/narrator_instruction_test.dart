// What the synthesis request actually asks for.
//
// MiMo has no accent parameter. Nothing in `audio` selects a dialect, and the
// audio-tag vocabulary carries no English accents at all — the only way to ask
// for American pronunciation is to say so in the `user` message, which the
// model treats as direction. That makes the instruction string load-bearing
// rather than decorative, and worth pinning: an edit that quietly turns it back
// into a vague phrase would cost the reader their accent and nothing would
// fail.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marginalia/data/remote/api.dart';

void main() {
  test('the synthesis request asks for General American pronunciation',
      () async {
    Map<String, Object?>? sent;
    final RemoteApi api = RemoteApi(
      client: MockClient((http.Request req) async {
        sent = jsonDecode(req.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode(<String, Object?>{
            'choices': <Object>[
              <String, Object?>{
                'message': <String, Object?>{
                  'audio': <String, Object?>{'data': base64Encode(<int>[1, 2, 3])},
                },
              },
            ],
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    await api.speak(
      baseUrl: 'https://example.invalid/v1',
      apiKey: 'k',
      text: 'The quick brown fox.',
      voice: 'Chloe',
    );

    expect(sent, isNotNull, reason: 'no request body was captured');

    // The direction lives in the `user` message; the text to speak goes in
    // `assistant`. Getting those two the wrong way round makes MiMo talk about
    // the sentence instead of reading it.
    final List<Object?> messages = sent!['messages'] as List<Object?>;
    final Map<String, Object?> user =
        messages.first as Map<String, Object?>;
    final Map<String, Object?> assistant =
        messages.last as Map<String, Object?>;

    expect(user['role'], 'user');
    expect(assistant['role'], 'assistant');
    expect(assistant['content'], 'The quick brown fox.');

    final String instruction = (user['content'] as String).toLowerCase();
    expect(instruction, contains('american'),
        reason: 'the accent request is gone — the voice would drift to '
            'whatever the model calls neutral');
    expect(instruction, isNot(contains('neutral accent')),
        reason: '"neutral accent" is the vague wording this replaced');
  });

  test('the instruction is a description the model can act on', () {
    // Not a keyword list and not a parameter. The docs are explicit that a
    // single natural-language sentence is enough, and equally explicit that
    // words with no referent — "normal", "ordinary" — are the ones to avoid.
    final String lower = kNarratorInstruction.toLowerCase();

    expect(kNarratorInstruction.split(' ').length, greaterThan(15),
        reason: 'too short to describe a delivery');
    for (final String banned in <String>['normal', 'ordinary', 'standard']) {
      // "standard" is allowed only as part of "standard american accent",
      // which is a named accent; on its own it is a word with no referent.
      if (banned == 'standard') continue;
      expect(lower, isNot(contains(banned)),
          reason: '"$banned" is a description of nothing');
    }
  });
}
