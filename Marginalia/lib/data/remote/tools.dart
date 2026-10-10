// The tools the writer may use, and the envelope every result travels in.
//
// THE RULE THAT MATTERS: a tool never throws into the loop. Every failure —
// a timeout, a 500, a key that was never configured, a call the model invented
// — comes back as a `tool` message the model can read and act on. A thrown
// exception would abort a run that has already been paid for, and the reader
// would lose the article over a failed search that the writer could simply have
// done without.
//
// Every failure message therefore ends with WHAT TO DO NEXT. A model handed a
// bare error tends to call the same tool again, which costs another paid round
// trip to learn the same thing.

import 'dart:convert';

import '../../domain/agent_budget.dart';
import 'log.dart';
import 'mcp.dart';
import 'news.dart';

/// What a tool call produced. Exactly one of [data] and [error] is set.
class ToolOutcome {
  const ToolOutcome._({
    this.data,
    this.error = '',
    this.message = '',
    this.hint = '',
    this.cached = false,
  });

  factory ToolOutcome.ok(Object? data, {bool cached = false}) =>
      ToolOutcome._(data: data, cached: cached);

  /// [error] is a short machine-ish code, [message] is the sentence the model
  /// reads, [hint] is what it should do next.
  factory ToolOutcome.failed(String error, String message, String hint) =>
      ToolOutcome._(error: error, message: message, hint: hint);

  final Object? data;

  /// Empty on success.
  final String error;
  final String message;
  final String hint;

  bool get ok => error.isEmpty;

  /// True when this result was served from the repeat cache.
  final bool cached;

  /// The same result, marked as a repeat.
  ///
  /// The loop replays a cached answer rather than re-running the tool, and the
  /// model has to be TOLD it is a repeat — otherwise it sees the same data it
  /// already had, concludes nothing happened, and asks a third time. Saying
  /// "you already asked this" is what actually breaks that loop.
  ToolOutcome cachedCopy() => ToolOutcome._(
        data: data,
        error: error,
        message: message,
        hint: hint,
        cached: true,
      );

  /// The JSON the model sees.
  String toJson() => jsonEncode(ok
      ? <String, Object?>{'ok': true, if (cached) 'cached': true, 'data': data}
      : <String, Object?>{
          'ok': false,
          'error': error,
          // `retryable` is ALWAYS false at this level, even for a timeout: the
          // tool already retried internally, and telling the model it may try
          // again only spends the call budget re-learning the same failure.
          'retryable': false,
          'message': message,
          'hint': hint,
        });
}

/// One tool. `isAvailable` is what keeps an unconfigured tool out of the
/// `tools` array entirely — the model cannot call what it was not offered.
abstract class AgentTool {
  const AgentTool();

  String get name;

  /// Shown to the model. One sentence about WHEN to use it, not just what it
  /// does — the difference between a model that researches and one that spams.
  String get description;

  Map<String, Object?> get schema;

  bool get isAvailable;

  Future<ToolOutcome> run(Map<String, Object?> args);

  /// The OpenAI tool declaration.
  Map<String, Object?> declaration() => <String, Object?>{
        'type': 'function',
        'function': <String, Object?>{
          'name': name,
          'description': description,
          'parameters': schema,
        },
      };
}

/// Reads one of today's Zhihu Daily stories.
class ReadStoryTool extends AgentTool {
  ReadStoryTool({required this.news, required this.items});

  final NewsSource news;

  /// The list the reader's run was given. Empty means the source is off.
  final List<NewsItem> items;

  @override
  String get name => 'read_story';

  @override
  String get description =>
      'Read the full text of one story from the list of today\'s Zhihu Daily '
      'headlines you were given. Use it when a headline looks promising and you '
      'want to know what the story actually says before writing about it. '
      'Reading a story costs nothing but time.';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'index': <String, Object?>{
            'type': 'integer',
            'description': 'The number shown beside the headline.',
          },
        },
        'required': <String>['index'],
      };

  @override
  bool get isAvailable => items.isNotEmpty;

  @override
  Future<ToolOutcome> run(Map<String, Object?> args) async {
    final Object? raw = args['index'];
    if (raw is! int) {
      return ToolOutcome.failed(
        'bad_arguments',
        'read_story needs an integer "index".',
        'Call it again with a number, or write the article from what you have.',
      );
    }
    final NewsItem? item = items.where((NewsItem i) => i.index == raw).firstOrNull;
    if (item == null) {
      return ToolOutcome.failed(
        'bad_arguments',
        'There is no story number $raw. The list runs from '
            '${items.first.index} to ${items.last.index}.',
        'Pick a number from the list, or write the article from what you have.',
      );
    }

    try {
      final String body = await news.storyBody(item.id);
      final bool cut = body.length > kMaxStoryChars;
      return ToolOutcome.ok(<String, Object?>{
        'index': item.index,
        'title': item.title,
        'body': cut ? body.substring(0, kMaxStoryChars) : body,
        if (cut) 'truncated': true,
      });
    } on NewsFailure catch (e) {
      return ToolOutcome.failed(
        'bad_payload',
        'That story could not be read (${e.message}).',
        'Do not call read_story again for this one. Write the article from '
            'what you already have, or read a different story.',
      );
    } catch (e) {
      AgentLog.instance.warn('tool', 'reading a story broke', detail: <String, Object?>{'error': '$e'});
      return ToolOutcome.failed(
        'tool_crashed',
        'That story failed inside the app.',
        'Write the article from what you already have.',
      );
    }
  }
}

/// Searches the web through the Aliyun MCP server.
class WebSearchTool extends AgentTool {
  WebSearchTool({required this.mcp, required this.apiKey});

  final McpClient mcp;
  final String apiKey;

  @override
  String get name => 'web_search';

  @override
  String get description =>
      'Search the web for facts you are not sure about: what a term means, what '
      'happened recently, or how something works. Use it when being wrong would '
      'spoil the article. Do NOT use it to look for something to write about — '
      'that is your own choice — and do not call it more than once or twice, '
      'because every call makes the reader wait.';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'query': <String, Object?>{
            'type': 'string',
            'description': 'What to search for.',
          },
          'count': <String, Object?>{
            'type': 'integer',
            'description': 'How many results, $kSearchCountMin to '
                '$kSearchCountMax. Default $kSearchCountDefault.',
          },
        },
        'required': <String>['query'],
      };

  @override
  bool get isAvailable => apiKey.trim().isNotEmpty;

  @override
  Future<ToolOutcome> run(Map<String, Object?> args) async {
    final Object? q = args['query'];
    if (q is! String || q.trim().isEmpty) {
      return ToolOutcome.failed(
        'bad_arguments',
        'web_search needs a non-empty "query".',
        'Call it again with a search phrase, or write the article from what '
            'you have.',
      );
    }
    final Object? c = args['count'];
    final int count = c is int ? c : kSearchCountDefault;

    try {
      final List<SearchResult> results =
          await mcp.search(apiKey, q.trim(), count: count);
      if (results.isEmpty) {
        return ToolOutcome.ok(<String, Object?>{
          'query': q,
          'results': const <Object?>[],
          'note': 'Nothing was found. Do not search again for this.',
        });
      }
      return ToolOutcome.ok(<String, Object?>{
        'query': q,
        'results': <Object?>[for (final SearchResult r in results) r.toJson()],
      });
    } on McpFailure catch (e) {
      return ToolOutcome.failed(
        'http_error',
        'The search did not work (${e.message}).',
        'Do not search again. Write the article from what you already know.',
      );
    } catch (e) {
      AgentLog.instance.warn('tool', 'the web search broke', detail: <String, Object?>{'error': '$e'});
      return ToolOutcome.failed(
        'tool_crashed',
        'The search failed inside the app.',
        'Write the article from what you already have.',
      );
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
