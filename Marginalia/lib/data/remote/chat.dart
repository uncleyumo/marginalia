// One assistant turn, and the parser that reads it out of a response body.
//
// `parseTurn` is TOTAL: it returns a [ChatTurn] for any input whatsoever and
// never throws. That is not defensiveness for its own sake — the three
// providers this app supports return subtly different shapes, and a loop that
// can be killed by a shape it did not anticipate is a loop that takes the
// reader's money and gives them an error message.
//
// The shapes that actually occur, and are handled here:
//
//   · `message.content` is `null` while `tool_calls` is present. This is the
//     standard OpenAI shape and the single most common cause of a naive parser
//     throwing on a perfectly good tool call.
//   · `content` is an ARRAY of parts rather than a string.
//   · `function.arguments` is an OBJECT rather than a JSON string.
//   · `tool_calls[i].id` is missing, so there is nothing to answer with.
//   · the legacy singular `function_call`.
//   · `name`/`arguments` sitting directly on the call object.
//   · `choices` missing or empty entirely.

import 'dart:convert';

/// One tool call the model asked for.
class ToolCall {
  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  /// The id the `tool` result must carry. Synthesized when the provider did not
  /// supply one, and the SAME value is used in the reply — a provider that
  /// omitted the id still has to see its own call answered.
  final String id;

  final String name;

  /// Always a JSON string, whatever the provider sent. Re-encoded here so the
  /// rest of the app has one shape to deal with.
  final String arguments;

  /// The arguments as a map, or null when they are not valid JSON.
  ///
  /// Null rather than `{}`: a call whose arguments did not parse is a call that
  /// must not be executed, and an empty map would silently look like a valid
  /// call with no arguments.
  Map<String, Object?>? get args {
    try {
      final Object? d = jsonDecode(arguments);
      return d is Map ? d.map((Object? k, Object? v) => MapEntry('$k', v)) : null;
    } catch (_) {
      return null;
    }
  }

  /// A stable identity for repeat detection: the tool plus its canonical
  /// arguments. Sorted keys, so `{a,b}` and `{b,a}` are the same call.
  String get signature {
    final Map<String, Object?>? a = args;
    if (a == null) return '$name($arguments)';
    final List<String> keys = a.keys.toList()..sort();
    return '$name(${keys.map((String k) => '$k=${a[k]}').join(',')})';
  }

  @override
  String toString() => 'ToolCall($id, $signature)';
}

/// One normalized assistant turn.
class ChatTurn {
  const ChatTurn({
    this.content = '',
    this.toolCalls = const <ToolCall>[],
    this.finishReason = '',
    this.reasoningChars = 0,
    this.contentWasNull = false,
    this.promptTokens = 0,
    this.completionTokens = 0,
  });

  final String content;
  final List<ToolCall> toolCalls;
  final String finishReason;

  /// Length of `reasoning_content`, if the provider sent one. Kept as a LENGTH
  /// and never as the text: it is large, it is useless to the reader, and it
  /// must never be echoed back — see [assistantMessage].
  final int reasoningChars;

  /// True when `content` was JSON null. Worth distinguishing in the log from an
  /// empty string: one means "the model chose not to speak", the other means
  /// "the proxy stripped the body".
  final bool contentWasNull;

  final int promptTokens;
  final int completionTokens;

  bool get hasToolCalls => toolCalls.isNotEmpty;
  bool get isEmpty => content.trim().isEmpty && toolCalls.isEmpty;

  /// The message to append back into the conversation.
  ///
  /// THIS IS WHERE `reasoning_content` IS DROPPED, and it matters more than it
  /// looks. MiMo and DeepSeek both return a `reasoning_content` field on their
  /// reasoning models, and both ERROR if a later request echoes it back. Since
  /// this function is the only thing that builds an assistant message, the drop
  /// happens in exactly one place and cannot be forgotten at a call site.
  ///
  /// It also guarantees the result is never a bare empty assistant message,
  /// which some providers reject outright.
  Map<String, Object?> assistantMessage() => <String, Object?>{
        'role': 'assistant',
        'content': content.isEmpty ? null : content,
        if (toolCalls.isNotEmpty)
          'tool_calls': <Object?>[
            for (final ToolCall c in toolCalls)
              <String, Object?>{
                'id': c.id,
                'type': 'function',
                'function': <String, Object?>{
                  'name': c.name,
                  'arguments': c.arguments,
                },
              },
          ],
      };

  /// The result of one tool call, as the provider expects it.
  static Map<String, Object?> toolMessage(String id, String content) =>
      <String, Object?>{'role': 'tool', 'tool_call_id': id, 'content': content};

  @override
  String toString() => 'ChatTurn(tools: ${toolCalls.length}, '
      'content: ${content.length} chars, finish: $finishReason)';
}

/// Read a chat-completions body into a [ChatTurn]. Never throws.
ChatTurn parseTurn(String body, {int turn = 0}) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return const ChatTurn();
  }
  if (decoded is! Map) return const ChatTurn();

  final Object? choices = decoded['choices'];
  if (choices is! List || choices.isEmpty) return const ChatTurn();
  final Object? first = choices.first;
  if (first is! Map) return const ChatTurn();

  final String finish = first['finish_reason'] is String
      ? first['finish_reason'] as String
      : '';

  final Object? message = first['message'];
  if (message is! Map) {
    return ChatTurn(finishReason: finish);
  }

  final (String content, bool wasNull) = _content(message['content']);

  int reasoning = 0;
  final Object? r = message['reasoning_content'];
  if (r is String) reasoning = r.length;

  final List<ToolCall> calls = _toolCalls(message, turn);

  final Object? usage = decoded['usage'];
  int pt = 0;
  int ct = 0;
  if (usage is Map) {
    if (usage['prompt_tokens'] is int) pt = usage['prompt_tokens'] as int;
    if (usage['completion_tokens'] is int) ct = usage['completion_tokens'] as int;
  }

  return ChatTurn(
    content: content,
    toolCalls: calls,
    finishReason: finish,
    reasoningChars: reasoning,
    contentWasNull: wasNull,
    promptTokens: pt,
    completionTokens: ct,
  );
}

/// `content` may be a string, an array of parts, or null.
(String, bool) _content(Object? raw) {
  if (raw == null) return ('', true);
  if (raw is String) return (raw, false);
  if (raw is List) {
    final StringBuffer b = StringBuffer();
    for (final Object? part in raw) {
      if (part is String) {
        b.write(part);
      } else if (part is Map && part['text'] is String) {
        b.write(part['text'] as String);
      }
    }
    return (b.toString(), false);
  }
  return ('', false);
}

/// Every tool-call shape, normalized to a list.
List<ToolCall> _toolCalls(Map<Object?, Object?> message, int turn) {
  final Object? raw = message['tool_calls'];
  final List<Object?> items = <Object?>[
    if (raw is List) ...raw,
    // The legacy singular form, lifted into the list. Some providers still
    // send it, and a model that asked for a tool and got no answer will ask
    // again — spending another paid call to say the same thing.
    if (raw is! List && message['function_call'] is Map) message['function_call'],
  ];

  final List<ToolCall> out = <ToolCall>[];
  for (int i = 0; i < items.length; i++) {
    final Object? item = items[i];
    if (item is! Map) continue;

    // The function payload may be nested under `function` or sitting directly
    // on the call object.
    final Object? fnRaw = item['function'];
    final Map<Object?, Object?> fn =
        fnRaw is Map ? fnRaw : item;

    final Object? name = fn['name'];
    if (name is! String || name.trim().isEmpty) continue;

    final Object? argsRaw = fn['arguments'];
    // Re-encoded when the provider sent an object, so everything downstream has
    // one shape. A Map is jsonEncoded; anything else that is not a String
    // becomes an empty object, which the tool layer will reject as bad
    // arguments rather than crash on.
    final String args = argsRaw is String
        ? argsRaw
        : (argsRaw == null ? '{}' : jsonEncode(argsRaw));

    final Object? id = item['id'];
    out.add(ToolCall(
      id: id is String && id.isNotEmpty ? id : 'call_t${turn}_$i',
      name: name.trim(),
      arguments: args,
    ));
  }
  return out;
}
