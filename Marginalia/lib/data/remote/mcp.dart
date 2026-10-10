// A minimal MCP client, for one server and one tool.
//
// Model Context Protocol over HTTP is JSON-RPC 2.0 in a POST body. That is the
// whole of it, and it was verified against the live server:
//
//   POST dashscope.aliyuncs.com/api/v1/mcps/WebSearch/mcp
//   Authorization: Bearer <key>
//   → `initialize`     200 · 185 B · capabilities.tools
//   → `tools/list`     200 · 415 B · one tool: bailian_web_search {query, count}
//   → `tools/call`     200 · 2.0 KB · ~1.1 s
//
// The server answers `application/json` rather than SSE, and returns NO
// `Mcp-Session-Id` header — it is stateless, so there is no handshake to keep
// alive and no session to expire. `initialize` is still sent once and cached,
// because the spec asks for it and a stricter server would require it; a
// failure there is logged and stepped over rather than fatal, since the
// `tools/call` that follows is what actually matters.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/agent_budget.dart';
import 'log.dart';

/// One search result, already reduced to what is worth putting in a prompt.
class SearchResult {
  const SearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });

  final String title;
  final String url;
  final String snippet;

  Map<String, Object?> toJson() => <String, Object?>{
        'title': title,
        'url': url,
        'snippet': snippet,
      };
}

class McpClient {
  McpClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String endpoint =
      'https://dashscope.aliyuncs.com/api/v1/mcps/WebSearch/mcp';

  static const Duration _timeout = Duration(seconds: kToolTimeoutSeconds);

  int _id = 0;
  String? _serverName;

  /// The handshake. Cached: done once per client, never per call.
  Future<void> initialize(String apiKey) async {
    if (_serverName != null) return;
    try {
      final Map<String, Object?> result =
          await _rpc(apiKey, 'initialize', <String, Object?>{
        'protocolVersion': '2024-11-05',
        'capabilities': <String, Object?>{},
        'clientInfo': <String, Object?>{'name': 'marginalia', 'version': '1.0'},
      });
      final Object? info = result['serverInfo'];
      _serverName = info is Map && info['name'] is String
          ? info['name'] as String
          : 'unknown';
      AgentLog.instance
          .info('tool', 'mcp initialized', detail: <String, Object?>{
        'server': _serverName,
        'protocol': result['protocolVersion'],
      });
    } catch (e) {
      // Not fatal. The call below is what matters and the server is stateless.
      AgentLog.instance
          .warn('tool', 'mcp initialize failed, continuing', detail: <String, Object?>{
        'error': '$e',
      });
    }
  }

  /// Run a web search. Throws [McpFailure] on anything that went wrong.
  Future<List<SearchResult>> search(
    String apiKey,
    String query, {
    int count = kSearchCountDefault,
  }) async {
    // Clamped HERE, not in the tool schema. A model that asks for twenty
    // results would otherwise get 5.8 KB of envelope pushed into the prompt on
    // the reader's money.
    final int n = count.clamp(kSearchCountMin, kSearchCountMax);

    await initialize(apiKey);

    final Map<String, Object?> result =
        await _rpc(apiKey, 'tools/call', <String, Object?>{
      'name': 'bailian_web_search',
      'arguments': <String, Object?>{'query': query, 'count': n},
    });

    if (result['isError'] == true) {
      throw const McpFailure('the search reported an error');
    }

    // The result is a list of content blocks; the payload is a JSON STRING
    // inside the first text block. Parsing twice is correct here — that is the
    // shape the server sends.
    final Object? content = result['content'];
    if (content is! List || content.isEmpty) {
      throw const McpFailure('the search returned nothing');
    }
    final Object? first = content.first;
    if (first is! Map || first['text'] is! String) {
      throw const McpFailure('the search returned an unreadable block');
    }

    Object? pages;
    try {
      final Object? decoded = jsonDecode(first['text'] as String);
      if (decoded is Map) pages = decoded['pages'];
    } catch (_) {
      throw const McpFailure('the search payload was not json');
    }
    if (pages is! List) throw const McpFailure('the search had no pages');

    final List<SearchResult> out = <SearchResult>[];
    for (final Object? p in pages) {
      if (p is! Map) continue;
      final Object? title = p['title'];
      final Object? snippet = p['snippet'];
      if (title is! String && snippet is! String) continue;
      out.add(SearchResult(
        title: title is String ? title.trim() : '',
        url: p['url'] is String ? p['url'] as String : '',
        // Cut here rather than in the prompt builder: the raw snippets run to
        // 500 characters each and most of the tail is navigation boilerplate.
        snippet: _cut(snippet is String ? snippet.trim() : ''),
      ));
    }
    AgentLog.instance.info('tool', 'web search finished', detail: <String, Object?>{
      'query': query,
      'asked': n,
      'results': out.length,
    });
    return out;
  }

  /// The tool names this server offers, as a one-shot.
  ///
  /// This is what Settings' Test button runs. It proves the key is accepted and
  /// the endpoint is reachable, and it costs nothing at all — `tools/list` is
  /// not a model call, so testing a key here cannot spend the reader's money.
  static Future<List<String>> listTools({required String apiKey}) async {
    final McpClient c = McpClient();
    try {
      final Map<String, Object?> result =
          await c._rpc(apiKey, 'tools/list', <String, Object?>{});
      final Object? tools = result['tools'];
      if (tools is! List) return const <String>[];
      return <String>[
        for (final Object? t in tools)
          if (t is Map && t['name'] is String) t['name'] as String,
      ];
    } finally {
      c.close();
    }
  }

  static String _cut(String s) {
    if (s.length <= kMaxSnippetChars) return s;
    return '${s.substring(0, kMaxSnippetChars)}…';
  }

  /// One JSON-RPC round trip.
  Future<Map<String, Object?>> _rpc(
    String apiKey,
    String method,
    Map<String, Object?> params,
  ) async {
    final int id = ++_id;
    final String body = jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });

    http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(endpoint),
            headers: <String, String>{
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
              // The spec asks for both; this server answers with json.
              'Accept': 'application/json, text/event-stream',
            },
            body: utf8.encode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const McpFailure('the search timed out');
    } catch (e) {
      throw McpFailure('could not reach the search: $e');
    }

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const McpFailure('the search key was refused');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw McpFailure('the search answered ${res.statusCode}');
    }

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw const McpFailure('the search answered with something unreadable');
    }
    if (decoded is! Map) throw const McpFailure('the search was not an object');

    final Object? error = decoded['error'];
    if (error is Map) {
      final Object? message = error['message'];
      throw McpFailure(message is String ? message : 'the search refused');
    }

    final Object? result = decoded['result'];
    if (result is! Map) throw const McpFailure('the search returned no result');
    return result.map((Object? k, Object? v) => MapEntry('$k', v));
  }

  void close() => _client.close();
}

class McpFailure implements Exception {
  const McpFailure(this.message);
  final String message;
  @override
  String toString() => 'McpFailure($message)';
}
