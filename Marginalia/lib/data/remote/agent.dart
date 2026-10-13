// The writing loop.
//
// This is the only place in the app that can spend money more than once per
// tap, so it is also the only place that has to prove it stops. The proof is
// three monotonic counters — model calls, tool calls, turns — plus a clock,
// every one of them checked BEFORE the blocking work it bounds. Every branch
// either increments a counter, sets `finish`, or returns. There is no path that
// re-enters the loop without consuming at least one of them.
//
// The loop is pure Dart. The http client, the clock, the sleep and the cancel
// flag are all injected, so `tool/check_agent.dart` can drive it with canned
// responses and assert the things that matter: that it terminates, that a
// second call is really a second call, and that no failure path returns a
// half-article.
//
// WHAT CROSSES THE BOUNDARY: a `String` of the model's final answer, or a
// `RemoteFailure`. Nothing else. Parsing that string into an Article stays
// where it has always been — in `ArticleWriter.parse` — so the "never a
// half-article" guarantee keeps exactly one owner.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../domain/agent_budget.dart';
import '../../domain/picture.dart';
import 'api.dart';
import 'chat.dart';
import 'log.dart';
import 'tools.dart';

/// How a run ended, for the log and the toast.
class AgentResult {
  const AgentResult({
    required this.content,
    required this.modelCalls,
    required this.toolCalls,
    required this.turns,
    required this.wallClockMs,
  });

  final String content;

  /// PAID round trips that reached the provider. This is the number the reader
  /// is told, and it includes retries — a retry is a second charge.
  final int modelCalls;
  final int toolCalls;
  final int turns;
  final int wallClockMs;
}

/// What one HTTP attempt produced, before it is parsed.
class _Response {
  const _Response(this.status, this.body, this.bytes);
  final int status;
  final String body;
  final int bytes;
}

class AgentLoop {
  AgentLoop({
    required this.endpoint,
    required this.apiKey,
    required this.tools,
    http.Client? client,
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
    bool Function()? cancelled,
    math.Random? random,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _now = now ?? DateTime.now,
        _sleep = sleep ?? Future<void>.delayed,
        _cancelled = cancelled ?? (() => false),
        _random = random ?? math.Random();

  final WriterEndpoint endpoint;
  final String apiKey;
  final List<AgentTool> tools;

  /// Mutable because a timed-out request has to be ABORTED, not merely
  /// abandoned — see [_recycleClient].
  http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;
  final bool Function() _cancelled;
  final math.Random _random;

  // ── run state ─────────────────────────────────────────────────────────
  late String _runId;
  late DateTime _started;
  int _calls = 0; // paid round trips
  int _toolCalls = 0;
  int _turns = 0;
  int _spentCalls = 0;
  int _backoffMs = 0;
  int _consecutiveToolFailures = 0;
  bool _finish = false;
  bool _repairUsed = false;
  bool _spent = false;

  final Map<String, int> _signatures = <String, int>{};
  final Map<String, ToolOutcome> _cache = <String, ToolOutcome>{};

  int get remainingMs =>
      kMaxWallClockSeconds * 1000 - _now().difference(_started).inMilliseconds;

  bool get _outOfTime => remainingMs <= kMinCallWindowSeconds * 1000;

  /// Run it.
  ///
  /// [system] and [user] are the two messages the writer built. The system
  /// message is extended here with the tool policy, because whether tools exist
  /// is this layer's business and not the prompt builder's.
  ///
  /// [pictures] go into the FIRST user message and nowhere else, which is the
  /// whole design: a loop makes several calls, and a loop that re-sent five
  /// pictures on every turn would send the same kilobytes four times and charge
  /// for every one of them. The model has seen them once; every later turn is a
  /// continuation of that same conversation, so they are still in context.
  Future<AgentResult> run({
    required String system,
    required String user,
    required String what,
    List<Picture> pictures = const <Picture>[],
  }) async {
    _runId = 'r${_now().millisecondsSinceEpoch.toRadixString(36)}';
    _started = _now();

    // The label is what the CALLER says this run is for — "Writing an article
    // about pointers", "Rewriting your reading plan". It is stamped on every
    // line of this run, because a reader scrolling the log should never have
    // to decode a run id to know which article a call belongs to.
    AgentLog.instance.beginRun(_runId, what);

    final List<Map<String, Object?>> messages = <Map<String, Object?>>[
      <String, Object?>{
        'role': 'system',
        'content': tools.isEmpty ? system : '$system\n\n${_toolPolicy()}',
      },
      <String, Object?>{
        'role': 'user',
        'content': userContent(user, pictures),
      },
    ];

    AgentLog.instance.info('plan', 'started', runId: _runId,
        detail: <String, Object?>{
          'what': what,
          'endpoint': endpoint.id,
          'model': endpoint.model,
          'tools': <String>[for (final AgentTool t in tools) t.name],
          'system': system.length,
          'user': user.length,
          if (pictures.isNotEmpty)
            'pictures': <String, Object?>{
              'count': pictures.length,
              'bytes': pictures.fold<int>(
                  0, (int s, Picture p) => s + p.bytes.lengthInBytes),
            },
        });

    try {
      while (true) {
        if (_cancelled()) throw _fail('cancelled', 'the run was cancelled');
        if (_now().difference(_started).inMilliseconds >=
            kMaxWallClockSeconds * 1000) {
          throw _fail('timeout', 'the run ran out of time');
        }
        if (_outOfTime) throw _fail('timeout', 'not enough time left to call');

        // Every one of these is a reason to stop RESEARCHING, not a reason to
        // fail. The article is still worth having, and the model can write it
        // from what it already has.
        if (_finish ||
            _turns >= kMaxTurns ||
            _calls >= kMaxModelCalls ||
            _toolCalls >= kMaxToolCalls) {
          return await _finalize(messages, what);
        }

        _turns++;
        final ChatTurn turn = await _request(
          messages,
          what: what,
          toolChoice: 'auto',
          responseFormat: null,
          kind: 'turn',
        );

        if (!turn.hasToolCalls) {
          if (turn.content.trim().isNotEmpty) {
            return _done(turn.content, what);
          }
          if (turn.contentWasNull || turn.finishReason == 'length') {
            // The model answered with nothing, or was cut off. Ask once for the
            // article and take whatever comes.
            _finish = true;
            continue;
          }
          if (!_repairUsed) {
            _repairUsed = true;
            messages.add(<String, Object?>{
              'role': 'user',
              'content': 'You did not answer. Call a tool, or write the article '
                  'as the JSON object described above.',
            });
            continue;
          }
          _finish = true;
          continue;
        }

        // The assistant message MUST be appended before its results, and every
        // id it carries must be answered before the next assistant turn.
        messages.add(turn.assistantMessage());
        await _runTools(turn, messages);
      }
    } on RemoteFailure {
      rethrow;
    } catch (e) {
      AgentLog.instance.error('done', 'the app crashed mid-run', runId: _runId,
          detail: <String, Object?>{'error': '$e'});
      throw RemoteFailure('The writer failed unexpectedly ($e).', spent: _spent);
    } finally {
      if (_ownsClient) _client.close();
    }
  }

  /// Execute one turn's tool calls, in order, answering every id.
  Future<void> _runTools(
      ChatTurn turn, List<Map<String, Object?>> messages) async {
    for (int i = 0; i < turn.toolCalls.length; i++) {
      final ToolCall call = turn.toolCalls[i];

      if (_toolCalls >= kMaxToolCalls) {
        messages.add(ChatTurn.toolMessage(
          call.id,
          ToolOutcome.failed('budget_exhausted',
                  'You have used all $kMaxToolCalls research calls.',
                  'Write the article now, from what you already have.')
              .toJson(),
        ));
        _finish = true;
        // Answer the REST of this turn's calls too, or the next request is
        // rejected for having an unanswered tool_call_id.
        for (int j = i + 1; j < turn.toolCalls.length; j++) {
          messages.add(ChatTurn.toolMessage(
            turn.toolCalls[j].id,
            ToolOutcome.failed('budget_exhausted',
                    'You have used all $kMaxToolCalls research calls.',
                    'Write the article now, from what you already have.')
                .toJson(),
          ));
        }
        return;
      }

      final String sig = call.signature;
      final int seen = (_signatures[sig] ?? 0) + 1;
      _signatures[sig] = seen;

      if (seen > kMaxRepeatedIdenticalToolCall) {
        messages.add(ChatTurn.toolMessage(
          call.id,
          ToolOutcome.failed('already_answered',
                  'You already called ${call.name} with those arguments.',
                  'Use different arguments, or write the article now.')
              .toJson(),
        ));
        _finish = true;
        continue;
      }

      // The second identical call is served from memory. It still counts
      // against the budget — the model spent a call asking — but it does not
      // touch the network.
      if (seen > 1 && _cache.containsKey(sig)) {
        messages.add(
            ChatTurn.toolMessage(call.id, _cache[sig]!.cachedCopy().toJson()));
        AgentLog.instance.info('tool', 'used a saved answer', runId: _runId,
            detail: <String, Object?>{'tool': call.name, 'signature': sig});
        continue;
      }

      final ToolOutcome outcome = await _dispatch(call);
      _cache[sig] = outcome;
      messages.add(ChatTurn.toolMessage(call.id, outcome.toJson()));
      _toolCalls++;

      if (outcome.ok) {
        _consecutiveToolFailures = 0;
      } else {
        _consecutiveToolFailures++;
        if (_consecutiveToolFailures >= kMaxConsecutiveToolFailures) {
          _finish = true;
          for (int j = i + 1; j < turn.toolCalls.length; j++) {
            messages.add(ChatTurn.toolMessage(
              turn.toolCalls[j].id,
              ToolOutcome.failed('skipped',
                      'Research stopped: the last two calls both failed.',
                      'Write the article now, from what you already have.')
                  .toJson(),
            ));
          }
          return;
        }
      }
    }
  }

  /// Run one tool. Never throws: anything that escapes becomes a `tool_crashed`
  /// envelope, because an exception here would kill a run that has been paid
  /// for.
  Future<ToolOutcome> _dispatch(ToolCall call) async {
    final AgentTool? tool =
        tools.where((AgentTool t) => t.name == call.name).firstOrNull;
    final DateTime t0 = _now();

    if (tool == null) {
      return ToolOutcome.failed(
        'unknown_tool',
        'There is no tool called "${call.name}". The only tools are '
            '${tools.map((AgentTool t) => t.name).join(' and ')}.',
        'Write the article, or use one of those.',
      );
    }
    if (!tool.isAvailable) {
      return ToolOutcome.failed(
        'unavailable',
        '${call.name} is not available: the reader has not turned that source on.',
        'Write the article from what you already have. Do not call it again.',
      );
    }

    final Map<String, Object?>? args = call.args;
    if (args == null) {
      return ToolOutcome.failed(
        'bad_arguments',
        'The arguments to ${call.name} were not readable.',
        'Call it again with valid arguments, or write the article.',
      );
    }

    ToolOutcome outcome;
    try {
      outcome = await tool.run(args);
    } catch (e) {
      outcome = ToolOutcome.failed(
        'tool_crashed',
        '${call.name} failed inside the app.',
        'Write the article from what you already have.',
      );
      AgentLog.instance
          .error('tool', 'a research step broke', runId: _runId, detail: <String, Object?>{
        'tool': call.name,
        'error': '$e',
      });
    }

    AgentLog.instance.info(
      'tool',
      outcome.ok ? '${call.name} worked' : '${call.name} failed: ${outcome.error}',
      runId: _runId,
      detail: <String, Object?>{
        'tool': call.name,
        'signature': call.signature,
        'ms': _now().difference(t0).inMilliseconds,
        'bytes': outcome.toJson().length,
        if (!outcome.ok) 'message': outcome.message,
      },
    );
    return outcome;
  }

  /// One paid request, with retry and budget accounting.
  Future<ChatTurn> _request(
    List<Map<String, Object?>> messages, {
    required String what,
    required String toolChoice,
    required String? responseFormat,
    required String kind,
    /// Overrides the run's tools for this one request. Used by the finalize
    /// ladder, which has to try the request with and without them. A parameter
    /// rather than mutating the field: the field is shared with the caller and
    /// clearing it would leave the run in a state nobody intended.
    List<AgentTool>? withTools,
  }) async {
    // An unavailable tool is not OFFERED. Enforced here rather than trusting
    // the caller to filter, because "the model cannot call what it was not
    // shown" is the only thing that actually stops it — the `unavailable`
    // envelope in `_dispatch` is a backstop for a hallucinated name, not the
    // mechanism.
    final List<AgentTool> offer = withTools ??
        <AgentTool>[for (final AgentTool t in tools) if (t.isAvailable) t];
    int attempt = 0;
    while (true) {
      if (_cancelled()) throw _fail('cancelled', 'the run was cancelled');
      if (_calls >= kMaxModelCalls) {
        throw _fail('no_article', 'the run used every call it was allowed');
      }
      if (_outOfTime) throw _fail('timeout', 'not enough time left to call');

      attempt++;
      _calls++;
      final DateTime t0 = _now();

      final Map<String, Object?> body = <String, Object?>{
        'model': endpoint.model,
        'messages': messages,
        'temperature': 0.4,
        if (offer.isNotEmpty) ...<String, Object?>{
          'tools': <Object?>[for (final AgentTool t in offer) t.declaration()],
          'tool_choice': toolChoice,
        },
        // NEVER together with `tools` on a normal turn: several providers
        // reject the combination outright, and the ones that accept it
        // sometimes ignore one of the two.
        if (responseFormat != null) 'response_format': <String, Object?>{
          'type': responseFormat,
        },
      };

      final String encoded = jsonEncode(body);

      // LOGGED BEFORE THE CALL, NOT AFTER.
      //
      // This line exists because of a real debugging session: the first live
      // run failed with two timeouts and the log said only "retrying in 500ms
      // {attempt: 1, reason: timeout}". Nothing recorded WHAT was sent, how big
      // it was, or which tools were offered — so there was no way to tell a
      // model that was thinking from a request that never left the phone. The
      // cost of the extra line is one ring-buffer entry; the cost of not having
      // it was an hour.
      AgentLog.instance.info('http', 'asking the model ($kind)', runId: _runId,
          detail: <String, Object?>{
            'attempt': attempt,
            'turn': _turns,
            'reqBytes': encoded.length,
            'messages': messages.length,
            'tools': <String>[for (final AgentTool t in offer) t.name],
            'toolChoice': offer.isEmpty ? null : toolChoice,
            'responseFormat': responseFormat,
            'cumulativeCalls': _calls,
            'elapsedMs': _now().difference(_started).inMilliseconds,
          });

      _Response res;
      try {
        res = await _post(encoded, attempt: attempt, kind: kind);
      } on _TransientFailure catch (e) {
        if (attempt >= kMaxAttemptsPerCall || _outOfTime) {
          AgentLog.instance.error('http', 'gave up after $attempt tries',
              runId: _runId, detail: <String, Object?>{'reason': e.reason});
          throw RemoteFailure(e.sentence, spent: _spent);
        }
        final int wait = _backoffFor(attempt);
        if (_backoffMs + wait > kMaxBackoffTotalMs) {
          throw RemoteFailure(e.sentence, spent: _spent);
        }
        _backoffMs += wait;
        AgentLog.instance.warn('http', 'trying again in ${wait}ms', runId: _runId,
            detail: <String, Object?>{'attempt': attempt, 'reason': e.reason});
        await _sleep(Duration(milliseconds: wait));
        continue;
      } on _TerminalFailure catch (e) {
        AgentLog.instance.error('http', 'the provider said no: ${e.reason}', runId: _runId,
            detail: <String, Object?>{'attempt': attempt, 'body': e.snippet});
        throw RemoteFailure(e.sentence, spent: _spent);
      }

      final ChatTurn turn = parseTurn(res.body, turn: _turns);
      AgentLog.instance.info('http', 'the model answered ($kind)', runId: _runId,
          detail: <String, Object?>{
            'attempt': attempt,
            'status': res.status,
            'ms': _now().difference(t0).inMilliseconds,
            'reqBytes': encoded.length,
            'resBytes': res.bytes,
            'toolChoice': toolChoice,
            'responseFormat': responseFormat,
            'finish': turn.finishReason,
            'contentChars': turn.content.length,
            'contentNull': turn.contentWasNull,
            'reasoningChars': turn.reasoningChars,
            'toolCalls': <String>[
              for (final ToolCall c in turn.toolCalls) c.name,
            ],
            'promptTokens': turn.promptTokens,
            'completionTokens': turn.completionTokens,
            'cumulativeCalls': _calls,
          });
      return turn;
    }
  }

  /// The last request: tools off, JSON forced, and a fallback ladder if the
  /// provider refuses the combination.
  Future<AgentResult> _finalize(
      List<Map<String, Object?>> messages, String what) async {
    messages.add(<String, Object?>{
      'role': 'user',
      'content': 'You have used your research budget. Write the article now, '
          'as the JSON object described above, using what you already have. '
          'Do not call any tools.',
    });

    // Rung 1: tools declared but forbidden, plus json_object. Rung 2: no tools
    // at all, still json_object. Rung 3: neither — the prompt already contains
    // "Output ONE json object" and the exact shape, and `_decode` tolerates
    // fences and surrounding prose.
    final List<(String, String?)> ladder = <(String, String?)>[
      ('none', 'json_object'),
      ('', 'json_object'),
      ('', null),
    ];

    Object? lastError;
    for (final (String choice, String? fmt) in ladder) {
      try {
        final ChatTurn turn = await _request(
          messages,
          what: what,
          toolChoice: choice.isEmpty ? 'auto' : choice,
          responseFormat: fmt,
          kind: 'finalize',
          // Rung 2 and 3 send no tools at all.
          withTools: choice.isEmpty ? const <AgentTool>[] : null,
        );
        if (turn.content.trim().isEmpty) {
          throw RemoteFailure('the writer answered with nothing',
              spent: _spent);
        }
        return _done(turn.content, what);
      } on RemoteFailure catch (e) {
        lastError = e;
        // Only a refusal of the SHAPE is worth stepping down for. A key that
        // was refused or a network that is down will fail identically on the
        // next rung, and retrying it would spend another paid call to learn
        // the same thing.
        if (!_looksLikeShapeRefusal(e.message)) rethrow;
        AgentLog.instance.warn('http', 'the model refused that format, trying a simpler one',
            runId: _runId,
            detail: <String, Object?>{'from': '$choice/$fmt', 'why': e.message});
      }
    }
    throw RemoteFailure(
        'The writer would not produce an article (${_short(lastError)}).',
        spent: _spent);
  }

  static bool _looksLikeShapeRefusal(String message) {
    final String m = message.toLowerCase();
    return m.contains('tools') ||
        m.contains('tool_choice') ||
        m.contains('response_format') ||
        m.contains('rejected the request');
  }

  AgentResult _done(String content, String what) {
    final int ms = _now().difference(_started).inMilliseconds;
    AgentLog.instance.info('done', 'finished OK', runId: _runId,
        detail: <String, Object?>{
          'turns': _turns,
          'modelCalls': _calls,
          'spentCalls': _spentCalls,
          'toolCalls': _toolCalls,
          'wallClockMs': ms,
          'backoffMs': _backoffMs,
          'contentChars': content.length,
        });
    return AgentResult(
      content: content,
      modelCalls: _spentCalls,
      toolCalls: _toolCalls,
      turns: _turns,
      wallClockMs: ms,
    );
  }

  RemoteFailure _fail(String code, String why) {
    AgentLog.instance.error('done', 'failed: $code', runId: _runId,
        detail: <String, Object?>{
          'why': why,
          'turns': _turns,
          'modelCalls': _calls,
          'spentCalls': _spentCalls,
          'toolCalls': _toolCalls,
          'wallClockMs': _now().difference(_started).inMilliseconds,
        });
    return RemoteFailure(_sentenceFor(code), spent: _spent);
  }

  static String _sentenceFor(String code) => switch (code) {
        'timeout' => 'Writing took too long and was stopped.',
        'cancelled' => 'Writing was stopped.',
        'no_article' => 'The writer did not produce a usable article.',
        _ => 'The writer did not produce a usable article.',
      };

  /// One POST, classified.
  Future<_Response> _post(
    String body, {
    required int attempt,
    required String kind,
  }) async {
    final int budget = math.min(
      kPerCallTimeoutSeconds * 1000,
      remainingMs - kMinCallWindowSeconds * 1000,
    );
    if (budget <= 0) {
      throw const _TransientFailure('no time left', 'Writing took too long.');
    }

    http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('${endpoint.baseUrl}/chat/completions'),
            headers: <String, String>{
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: utf8.encode(body),
          )
          .timeout(Duration(milliseconds: budget));
    } on TimeoutException {
      // `Future.timeout` does NOT cancel the request: the socket stays open and
      // the response can still land, into a turn nobody is waiting for. Closing
      // the client tears down the in-flight connection; a fresh one is built
      // for the next attempt. This client is the loop's OWN — the shared one in
      // `main._api` is used by audio and the plan editor and must never be
      // closed by an abandoned write.
      _recycleClient();
      throw const _TransientFailure('timeout', 'Writing took too long.');
    } catch (e) {
      throw _TransientFailure('network', 'Could not reach the writer — ${_short(e)}.');
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      _spentCalls++;
      _spent = true;
      return _Response(res.statusCode, utf8.decode(res.bodyBytes), res.bodyBytes.length);
    }

    final String snippet = AgentLog.scrub(
      utf8.decode(res.bodyBytes, allowMalformed: true),
      knownKeys: <String>[apiKey],
    );
    final int code = res.statusCode;
    if (_isTransient(code)) {
      throw _TransientFailure('http $code', _explain(code, snippet));
    }
    throw _TerminalFailure(_explain(code, snippet), 'http $code', snippet);
  }

  static bool _isTransient(int code) =>
      code == 408 ||
      code == 425 ||
      code == 429 ||
      code >= 500;

  static String _explain(int code, String body) {
    final String detail = _detail(body);
    return switch (code) {
      401 || 403 => 'The key was refused while writing an article. Check it and '
          'save it again.',
      404 => 'That address has no endpoint for writing an article. Check the '
          'base URL.',
      429 => 'The provider is rate-limiting this phone. Try again in a minute.',
      >= 500 => 'The provider is having a bad minute. Try again shortly.',
      _ => detail.isEmpty
          ? 'The provider rejected the request while writing an article '
              '($code).'
          : 'The provider rejected the request while writing an article: $detail',
    };
  }

  static String _detail(String body) {
    try {
      final Object? d = jsonDecode(body);
      if (d is Map && d['error'] is Map) {
        final Object? m = (d['error'] as Map)['message'];
        if (m is String) return m;
      }
    } catch (_) {
      // not json; the status code is the message
    }
    return '';
  }

  static String _short(Object? e) {
    final String s = '$e';
    return s.length <= 120 ? s : '${s.substring(0, 120)}…';
  }

  int _backoffFor(int attempt) {
    final int base = attempt <= 1 ? 500 : 1500;
    // ±30% jitter, so two phones retrying together do not stay in lockstep.
    final int jitter = (_random.nextDouble() * 0.6 - 0.3).abs() ~/ 1;
    return base + (base * jitter ~/ 10);
  }

  /// Drop the connection and build a new one for the next attempt.
  ///
  /// Only when this loop created the client. An INJECTED client belongs to the
  /// caller — in the tests it is a fake, and in the app it is the loop's own
  /// anyway, but a client somebody else handed in is not this loop's to close.
  void _recycleClient() {
    if (!_ownsClient) return;
    try {
      _client.close();
    } catch (_) {
      // already gone; nothing to do
    }
    _client = http.Client();
  }

  String _toolPolicy() {
    final List<String> names = <String>[for (final AgentTool t in tools) t.name];
    return 'You may look things up before you write.\n'
        'Available tools: ${names.join(', ')}.\n'
        'Use them ONLY when being wrong would spoil the article, or when you '
        'want to read one of the stories you were shown. Do not call a tool to '
        'look for something to write about — that choice is yours. Do not call '
        'the same tool twice with the same arguments. You have at most '
        '$kMaxToolCalls calls in total, and every one of them makes the reader '
        'wait, so prefer writing. When you have what you need, answer with the '
        'JSON object and no tool calls.';
  }
}

class _TransientFailure implements Exception {
  const _TransientFailure(this.reason, this.sentence);
  final String reason;
  final String sentence;
}

class _TerminalFailure implements Exception {
  const _TerminalFailure(this.sentence, this.reason, this.snippet);
  final String sentence;
  final String reason;
  final String snippet;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
