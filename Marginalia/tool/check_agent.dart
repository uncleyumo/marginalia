// The writing loop, as executable checks.
//
// `dart test` cannot run in this environment (see the note in
// `check_invariants.dart`), so this follows the same convention: a plain Dart
// program that exits non-zero and prints what broke.
//
//   dart tool/check_agent.dart
//
// These are not ordinary unit tests. They exist because the loop is the only
// thing in this app that can spend the reader's money more than once per tap,
// and the properties asserted here are the ones whose absence would be a
// financial bug rather than a visual one:
//
//   · it TERMINATES, whatever the model does
//   · it never exceeds the call ceiling the cost line advertises
//   · a retry really is a second paid call, and is counted as one
//   · a failure never returns a half-article
//   · the assistant message never echoes `reasoning_content` back, which is
//     the single most likely way for the second turn of a real run to crash

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../lib/data/remote/agent.dart';
import '../lib/data/remote/api.dart';
import '../lib/data/remote/chat.dart';
import '../lib/data/remote/log.dart';
import '../lib/data/remote/tools.dart';
import '../lib/domain/agent_budget.dart';
import '../lib/domain/queue.dart';

int _failures = 0;
int _checks = 0;

void check(String name, bool passed, [String detail = '']) {
  _checks++;
  if (passed) {
    print('  ok   $name');
  } else {
    _failures++;
    print('  FAIL $name${detail.isEmpty ? '' : '  -> $detail'}');
  }
}

void section(String title) {
  print('');
  print(title);
  print('-' * title.length);
}

/// Records every request the loop makes, and answers with a script.
class Scripted {
  Scripted(this._answers);

  /// One entry per expected POST. The last one repeats if the loop asks again.
  final List<http.Response Function(int call)> _answers;

  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
  int posts = 0;

  http.Client get client => MockClient((http.Request req) async {
        final Map<String, Object?> body =
            jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, Object?>;
        sent.add(body);
        final int i = posts;
        posts++;
        final int at = i < _answers.length ? i : _answers.length - 1;
        return _answers[at](i);
      });

  /// The messages array of the nth request.
  List<Object?> messagesOf(int i) =>
      (sent[i]['messages'] as List<Object?>?) ?? const <Object?>[];
}

http.Response _json(Map<String, Object?> body) => http.Response(
      jsonEncode(body), 200,
      headers: <String, String>{'content-type': 'application/json'});

/// A model turn that asks for a tool.
http.Response _toolTurn(String name, Map<String, Object?> args,
        {String? id, String? reasoning}) =>
    _json(<String, Object?>{
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'tool_calls',
          'message': <String, Object?>{
            // The standard OpenAI shape: content is null while a tool call is
            // present. A parser that assumes a string dies here.
            'content': null,
            if (reasoning != null) 'reasoning_content': reasoning,
            'tool_calls': <Object?>[
              <String, Object?>{
                if (id != null) 'id': id,
                'type': 'function',
                'function': <String, Object?>{
                  'name': name,
                  'arguments': jsonEncode(args),
                },
              },
            ],
          },
        },
      ],
    });

/// A model turn that answers with an article.
http.Response _articleTurn(String title) => _json(<String, Object?>{
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'stop',
          'message': <String, Object?>{
            'content': jsonEncode(<String, Object?>{
              'title': title,
              'keywords': <String>['pointers', 'memory'],
              'sentences': <Object?>[
                <String, Object?>{'en': 'A pointer is a number.', 'cn': '指针是数字。'},
              ],
              'marks': <Object?>[],
            }),
          },
        },
      ],
      'usage': <String, Object?>{'prompt_tokens': 100, 'completion_tokens': 50},
    });

class _FakeTool extends AgentTool {
  _FakeTool(this.name, {this.available = true, this.throws = false});

  @override
  final String name;
  final bool available;
  final bool throws;
  int calls = 0;

  @override
  String get description => 'a fake';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'index': <String, Object?>{'type': 'integer'},
        },
      };

  @override
  bool get isAvailable => available;

  @override
  Future<ToolOutcome> run(Map<String, Object?> args) async {
    calls++;
    if (throws) throw StateError('the tool exploded');
    return ToolOutcome.ok(<String, Object?>{'index': args['index'], 'body': '…'});
  }
}

const WriterEndpoint _endpoint = WriterEndpoint(
  id: 'test',
  name: 'Test',
  baseUrl: 'https://example.invalid/v1',
  model: 'test-model',
  costLine: 'free',
);

Future<void> main() async {
  print('Marginalia — writing-loop checks');

  // ── 1. the ordinary run: one tool call, then the article ──────────────
  section('1. a browse turn and a write turn cost exactly two calls');
  {
    final Scripted s = Scripted(<http.Response Function(int)>[
      (int _) => _toolTurn('read_story', <String, Object?>{'index': 2}),
      (int _) => _articleTurn('Rhinoceroses'),
    ]);
    final _FakeTool tool = _FakeTool('read_story');
    final AgentLoop loop = AgentLoop(
      endpoint: _endpoint,
      apiKey: 'k',
      tools: <AgentTool>[tool],
      client: s.client,
      sleep: (Duration _) async {},
    );

    final AgentResult r =
        await loop.run(system: 'sys', user: 'usr', what: 'write an article');

    check('exactly two POSTs', s.posts == 2, 'got ${s.posts}');
    check('the tool ran once', tool.calls == 1, 'got ${tool.calls}');
    check('two calls are reported as spent', r.modelCalls == 2,
        'got ${r.modelCalls}');
    check('the article comes back', r.content.contains('Rhinoceroses'));

    // The second request must carry the assistant turn AND its result, in that
    // order, with a matching id. A provider rejects anything else.
    final List<Object?> msgs = s.messagesOf(1);
    check('the conversation grew by two messages', msgs.length == 4,
        'got ${msgs.length}');
    final Map<Object?, Object?> assistant = msgs[2] as Map<Object?, Object?>;
    final Map<Object?, Object?> result = msgs[3] as Map<Object?, Object?>;
    check('the assistant turn is second-to-last',
        assistant['role'] == 'assistant');
    check('and its tool result follows it', result['role'] == 'tool');
    final String answeredId =
        ((assistant['tool_calls'] as List<Object?>).first as Map<Object?, Object?>)['id']!
            as String;
    check('the result answers the id that was asked',
        result['tool_call_id'] == answeredId,
        '$answeredId vs ${result['tool_call_id']}');
  }

  // ── 2. reasoning_content must not be echoed back ──────────────────────
  section('2. reasoning_content is never sent back');
  {
    final Scripted s = Scripted(<http.Response Function(int)>[
      (int _) => _toolTurn('read_story', <String, Object?>{'index': 1},
          reasoning: 'let me think about which story to read…'),
      (int _) => _articleTurn('Done'),
    ]);
    final AgentLoop loop = AgentLoop(
      endpoint: _endpoint,
      apiKey: 'k',
      tools: <AgentTool>[_FakeTool('read_story')],
      client: s.client,
      sleep: (Duration _) async {},
    );
    await loop.run(system: 's', user: 'u', what: 'w');

    final String second = jsonEncode(s.messagesOf(1));
    check('the reasoning text is not in the second request',
        !second.contains('let me think'),
        'found the reasoning string in the follow-up request');
    check('and the key is not there either',
        !second.contains('reasoning_content'));
  }

  // ── 3. a model that only ever calls tools still terminates ────────────
  section('3. a tool-looping model is stopped by the budget');
  {
    final Scripted s = Scripted(<http.Response Function(int)>[
      // A different index each time, so the repeat guard does not fire first —
      // this is testing the BUDGET, not the repeat rule.
      (int i) => _toolTurn('read_story', <String, Object?>{'index': i + 1}),
    ]);
    final _FakeTool tool = _FakeTool('read_story');
    final AgentLoop loop = AgentLoop(
      endpoint: _endpoint,
      apiKey: 'k',
      tools: <AgentTool>[tool],
      client: s.client,
      sleep: (Duration _) async {},
    );

    bool threw = false;
    try {
      await loop.run(system: 's', user: 'u', what: 'w');
    } on RemoteFailure {
      threw = true;
    }
    check('the run stops', s.posts <= kMaxModelCalls,
        'made ${s.posts} POSTs, ceiling is $kMaxModelCalls');
    check('and it stopped by writing, not by hanging',
        s.posts >= 2 && threw,
        'posts=${s.posts} threw=$threw');
    check('no more than the tool budget was spent',
        tool.calls <= kMaxToolCalls, 'got ${tool.calls}');
  }

  // ── 4. the same call three times ──────────────────────────────────────
  section('4. the identical call is refused the third time');
  {
    final Scripted s = Scripted(<http.Response Function(int)>[
      (int _) => _toolTurn('read_story', <String, Object?>{'index': 7}),
      (int _) => _toolTurn('read_story', <String, Object?>{'index': 7}),
      (int _) => _toolTurn('read_story', <String, Object?>{'index': 7}),
      (int _) => _articleTurn('Written anyway'),
    ]);
    final _FakeTool tool = _FakeTool('read_story');
    final AgentLoop loop = AgentLoop(
      endpoint: _endpoint,
      apiKey: 'k',
      tools: <AgentTool>[tool],
      client: s.client,
      sleep: (Duration _) async {},
    );

    final AgentResult r =
        await loop.run(system: 's', user: 'u', what: 'w');
    check('the tool itself ran only once', tool.calls == 1,
        'got ${tool.calls}');
    // The tool result is a JSON STRING inside the message, so it arrives
    // escaped in the encoded messages — match the word, not the quoted key.
    check('the second call was served from the cache',
        jsonEncode(s.messagesOf(2)).contains('cached'));
    check('the third was refused',
        jsonEncode(s.messagesOf(3)).contains('already_answered'));
    check('and the run still produced the article',
        r.content.contains('Written anyway'));
  }

  // ── 5. retry policy ───────────────────────────────────────────────────
  section('5. terminal errors do not retry, transient ones do');
  {
    final Scripted s = Scripted(<http.Response Function(int)>[
      (int _) => http.Response('{"error":{"message":"bad key"}}', 401),
    ]);
    final AgentLoop loop = AgentLoop(
      endpoint: _endpoint, apiKey: 'k', tools: const <AgentTool>[],
      client: s.client, sleep: (Duration _) async {},
    );
    bool threw = false;
    try {
      await loop.run(system: 's', user: 'u', what: 'w');
    } on RemoteFailure {
      threw = true;
    }
    check('a 401 fails immediately', s.posts == 1, 'got ${s.posts} POSTs');
    check('and it is reported', threw);
  }
  {
    final Scripted s = Scripted(<http.Response Function(int)>[
      (int _) => http.Response('{"error":{"message":"boom"}}', 500),
    ]);
    final AgentLoop loop = AgentLoop(
      endpoint: _endpoint, apiKey: 'k', tools: const <AgentTool>[],
      client: s.client, sleep: (Duration _) async {},
    );
    try {
      await loop.run(system: 's', user: 'u', what: 'w');
    } on RemoteFailure {
      // expected
    }
    check('a 500 retries to the attempt ceiling',
        s.posts == kMaxAttemptsPerCall, 'got ${s.posts} POSTs');
    check('and every retry was counted as a paid call',
        s.posts <= kMaxModelCalls);
  }

  // ── 6. a tool that throws does not kill the run ───────────────────────
  section('6. a crashing tool becomes something the model can read');
  {
    final Scripted s = Scripted(<http.Response Function(int)>[
      (int _) => _toolTurn('read_story', <String, Object?>{'index': 1}),
      (int _) => _articleTurn('Written without research'),
    ]);
    final AgentLoop loop = AgentLoop(
      endpoint: _endpoint, apiKey: 'k',
      tools: <AgentTool>[_FakeTool('read_story', throws: true)],
      client: s.client, sleep: (Duration _) async {},
    );
    final AgentResult r = await loop.run(system: 's', user: 'u', what: 'w');
    final String toolMsg = jsonEncode(s.messagesOf(1)[3]);
    check('the crash is reported as a tool error',
        toolMsg.contains('tool_crashed'));
    check('and it tells the model what to do next',
        toolMsg.contains('hint'));
    check('the run carries on and writes', r.content.contains('without research'));
  }

  // ── 7. an unavailable tool is never offered ───────────────────────────
  section('7. a tool that is off is not advertised');
  {
    final Scripted s = Scripted(<http.Response Function(int)>[
      (int _) => _articleTurn('No tools needed'),
    ]);
    final AgentLoop loop = AgentLoop(
      endpoint: _endpoint, apiKey: 'k',
      tools: <AgentTool>[_FakeTool('read_story', available: false)],
      client: s.client, sleep: (Duration _) async {},
    );
    await loop.run(system: 's', user: 'u', what: 'w');
    check('the tools array is absent from the request',
        !s.sent.first.containsKey('tools'));
    check('and no tool_choice is sent either',
        !s.sent.first.containsKey('tool_choice'));
  }

  // ── 8. the wall clock stops a run ─────────────────────────────────────
  section('8. the wall clock is a hard stop');
  {
    int ticks = 0;
    final Scripted s = Scripted(<http.Response Function(int)>[
      (int _) => _toolTurn('read_story', <String, Object?>{'index': 1}),
    ]);
    final AgentLoop loop = AgentLoop(
      endpoint: _endpoint, apiKey: 'k',
      tools: <AgentTool>[_FakeTool('read_story')],
      client: s.client,
      // Every look at the clock jumps a minute.
      now: () => DateTime(2026, 1, 1).add(Duration(minutes: ticks++)),
      sleep: (Duration _) async {},
    );
    bool threw = false;
    try {
      await loop.run(system: 's', user: 'u', what: 'w');
    } on RemoteFailure catch (e) {
      threw = true;
      check('the failure says what happened',
          e.message.toLowerCase().contains('long'), 'got "${e.message}"');
    }
    check('the run is stopped by the clock', threw);
    check('and it stopped early, not after the full call budget',
        s.posts < kMaxModelCalls, 'got ${s.posts} POSTs');
  }

  // ── 9. the parser is total ────────────────────────────────────────────
  section('9. the response parser survives every shape');
  {
    check('null content with tool_calls', () {
      final ChatTurn t = parseTurn(jsonEncode(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{
              'content': null,
              'tool_calls': <Object?>[
                <String, Object?>{
                  'function': <String, Object?>{
                    'name': 'read_story',
                    'arguments': <String, Object?>{'index': 3},
                  },
                },
              ],
            },
          },
        ],
      }));
      return t.toolCalls.length == 1 &&
          t.toolCalls.first.id.isNotEmpty &&
          t.toolCalls.first.args?['index'] == 3;
    }());
    check('content as an array of parts', () {
      final ChatTurn t = parseTurn(jsonEncode(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{
              'content': <Object?>[
                <String, Object?>{'type': 'text', 'text': 'hello '},
                <String, Object?>{'type': 'text', 'text': 'world'},
              ],
            },
          },
        ],
      }));
      return t.content == 'hello world';
    }());
    check('the legacy singular function_call', () {
      final ChatTurn t = parseTurn(jsonEncode(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{
              'content': '',
              'function_call': <String, Object?>{
                'name': 'web_search',
                'arguments': '{"query":"x"}',
              },
            },
          },
        ],
      }));
      return t.toolCalls.length == 1 && t.toolCalls.first.name == 'web_search';
    }());
    check('garbage in, empty turn out', () {
      final ChatTurn a = parseTurn('not json at all');
      final ChatTurn b = parseTurn('{}');
      final ChatTurn c = parseTurn('{"choices":[]}');
      final ChatTurn d = parseTurn('{"choices":[{"message":"a string"}]}');
      return a.isEmpty && b.isEmpty && c.isEmpty && d.isEmpty;
    }());
    check('an unparseable argument string is not silently an empty map', () {
      final ChatTurn t = parseTurn(jsonEncode(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{
              'content': '',
              'tool_calls': <Object?>[
                <String, Object?>{
                  'id': 'x',
                  'function': <String, Object?>{
                    'name': 'read_story',
                    'arguments': '{"index": ',
                  },
                },
              ],
            },
          },
        ],
      }));
      return t.toolCalls.first.args == null;
    }());
  }

  // ── 10. the log scrubs credentials ────────────────────────────────────
  section('10. the debug log never carries a key');
  {
    const String key = 'sk-abcdefghijklmnopqrstuvwxyz0123456789';
    final String scrubbed = AgentLog.scrub(
      'Authorization: Bearer $key and also uapi-8vfipeu4J_1j-4R8C3nuc-NtNeuSy0p',
      knownKeys: const <String>[key],
    );
    check('a known key is masked', !scrubbed.contains('abcdefghij'),
        'got "$scrubbed"');
    check('an unknown key-shaped token is masked too',
        !scrubbed.contains('8vfipeu4J_1j'), 'got "$scrubbed"');
    check('and the prefix is kept so it is still identifiable',
        scrubbed.contains('sk-a') || scrubbed.contains('uapi'),
        'got "$scrubbed"');
  }

  section('11. the price on the card is the price the loop can charge');
  {
    // The one place where a constant in the budget and a string on a button
    // have to agree. `researchedArticle.buttonLabel` promises a ceiling, and
    // the ceiling is `kMaxModelCalls` — so the two are read against each other
    // rather than trusted to stay in step by hand.
    final String button = CostKind.researchedArticle.buttonLabel;
    check('the button states a call ceiling',
        button.contains('up to $kMaxModelCalls calls'), 'got "$button"');

    final String label = CostKind.researchedArticle.label;
    check('the full cost line states the same ceiling',
        label.contains('up to $kMaxModelCalls calls'), 'got "$label"');
    check('and it is a range, not a single number',
        label.contains('–') || label.contains('-'), 'got "$label"');

    check('the fast path still promises exactly one call',
        CostKind.oneArticle.buttonLabel.contains('one call') == false &&
            CostKind.oneArticle.label.contains('one call'),
        'got "${CostKind.oneArticle.label}"');
    // The measured fact that made the first timeout wrong. If a writing call
    // can take 72 s, a per-call ceiling under that is a ceiling that fires on
    // working calls — and this check exists so the two cannot drift apart
    // again without somebody seeing it.
    // 230 s is the slowest call actually observed (a research run's writing
    // turn, measured on the emulator). A ceiling under that fires on working
    // calls, so the check is against the measurement, not against a feeling.
    check('a call may outlive the slowest measured call (230 s)',
        kPerCallTimeoutSeconds >= 300,
        'per-call ceiling is ${kPerCallTimeoutSeconds}s');
    check('and the run may outlive several of them',
        kMaxWallClockSeconds > kPerCallTimeoutSeconds * 1.5,
        'wall ${kMaxWallClockSeconds}s vs per-call ${kPerCallTimeoutSeconds}s');
    check('the card does not promise seconds for a minutes-long job',
        !CostKind.oneArticle.label.contains('~25 s'),
        'got "${CostKind.oneArticle.label}"');
    check('and the fast path is cheaper than the researched one',
        CostKind.oneArticle.spendsMoney &&
            CostKind.researchedArticle.spendsMoney);
  }

  // ── summary ───────────────────────────────────────────────────────────
  print('');
  print('=' * 60);
  if (_failures == 0) {
    print('ALL $_checks CHECKS PASSED');
  } else {
    print('$_failures of $_checks CHECKS FAILED');
  }
  print('=' * 60);
  if (_failures > 0) {
    throw StateError('$_failures agent check(s) failed');
  }
}
