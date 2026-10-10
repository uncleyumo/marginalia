// The optional news source: Zhihu Daily, through the UApiPro hotboard.
//
// Measured against the live endpoints:
//
//   GET uapis.cn/api/v1/misc/hotboard?type=zhihu-daily   (Bearer <uapi key>)
//       → 200 · 8.4 KB · 358 ms · 30 items, each with index/title/url/extra.id
//
//   GET daily.zhihu.com/api/4/story/{id}
//       → 200 · 3.8 KB · 370 ms · NO auth, NO user-agent needed
//         {"title":…, "body":"<div>…</div>"}, ~636 characters of clean Chinese
//         once the tags are stripped
//
// The obvious approach — fetching the story's HTML page and scraping it — DOES
// NOT WORK. `daily.zhihu.com/story/{id}` returns a 28 KB JavaScript shell whose
// `<title>` is the generic "知乎 - 有问题，就会有答案", with no article, no
// `og:title` and no embedded state. The JSON endpoint above is on the same host
// and is what the page itself calls.
//
// This whole file is OPTIONAL. Nothing here is required for the app to write an
// article: if the reader has no key, or the endpoint moves, or the phone is in
// airplane mode, generation falls back to the writer choosing its own subject —
// which is the default anyway.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'log.dart';

/// One row of the hotboard.
class NewsItem {
  const NewsItem({
    required this.index,
    required this.title,
    required this.url,
    required this.id,
  });

  /// The number the model is shown and asks for. 1-based, as the API sends it.
  final int index;
  final String title;
  final String url;

  /// The Zhihu story id, taken from `extra.id` — NOT parsed out of the URL. The
  /// API hands it over, and parsing a URL to recover something already given is
  /// how a working integration breaks the day the URL shape changes.
  final int id;
}

class NewsSource {
  NewsSource({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _hotboard =
      'https://uapis.cn/api/v1/misc/hotboard?type=zhihu-daily';
  static const String _story = 'https://daily.zhihu.com/api/4/story/';

  static const Duration _timeout = Duration(seconds: 8);

  /// Today's list. Throws on failure — the caller decides what to do about it,
  /// and the answer is always "carry on without it".
  Future<List<NewsItem>> hotboard({required String apiKey}) async {
    final http.Response res = await _client.get(
      Uri.parse(_hotboard),
      headers: <String, String>{
        'Authorization': 'Bearer $apiKey',
        'Accept': 'application/json',
      },
    ).timeout(_timeout);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NewsFailure('the hotboard answered ${res.statusCode}');
    }
    // The body is utf8 and the header sometimes lies about it.
    final Object? decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) throw const NewsFailure('the hotboard was not an object');
    final Object? list = decoded['list'];
    if (list is! List) throw const NewsFailure('the hotboard had no list');

    final List<NewsItem> out = <NewsItem>[];
    for (final Object? item in list) {
      if (item is! Map) continue;
      final Object? title = item['title'];
      final Object? index = item['index'];
      final Object? extra = item['extra'];
      final Object? id = extra is Map ? extra['id'] : null;
      if (title is! String || title.trim().isEmpty) continue;
      if (index is! int || id is! int) continue;
      out.add(NewsItem(
        index: index,
        title: title.trim(),
        url: item['url'] is String ? item['url'] as String : '',
        id: id,
      ));
    }
    if (out.isEmpty) throw const NewsFailure('the hotboard was empty');
    AgentLog.instance.info('tool', 'fetched the day\'s headlines',
        detail: <String, Object?>{'items': out.length, 'bytes': res.bodyBytes.length});
    return out;
  }

  /// One story's body, as plain text.
  Future<String> storyBody(int id) async {
    final http.Response res =
        await _client.get(Uri.parse('$_story$id')).timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NewsFailure('the story answered ${res.statusCode}');
    }
    final Object? decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) throw const NewsFailure('the story was not an object');
    final Object? body = decoded['body'];
    if (body is! String || body.trim().isEmpty) {
      throw const NewsFailure('the story had no body');
    }
    final String text = stripHtml(body);
    if (text.trim().isEmpty) {
      throw const NewsFailure('the story had no readable text');
    }
    AgentLog.instance.info('tool', 'read a news story', detail: <String, Object?>{
      'id': id,
      'html': body.length,
      'text': text.length,
    });
    return text;
  }

  void close() => _client.close();
}

/// Turn the story's HTML into text.
///
/// Regexes rather than an HTML parser, deliberately. The app already hand-writes
/// a single-member zip reader rather than depend on `archive`; a dependency for
/// one known shape of one known endpoint would be the same mistake at a larger
/// scale. This is exactly the transform that was tested against the live API:
/// strip script and style, turn block boundaries into newlines, drop the rest
/// of the tags, unescape the entities, collapse the whitespace.
String stripHtml(String html) {
  String s = html;
  s = s.replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>',
      caseSensitive: false, dotAll: true), '');
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</(p|div|figure|blockquote|li|h[1-6])>',
      caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  s = _unescape(s);
  s = s.replaceAll(RegExp(r'[ \t ]+'), ' ');
  s = s.replaceAll(RegExp(r'\n[ \t]*'), '\n');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

/// The entities that actually turn up in this content.
///
/// `&amp;` is done LAST, or `&amp;lt;` would become `<`.
String _unescape(String s) {
  String out = s;
  const Map<String, String> named = <String, String>{
    '&nbsp;': ' ',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&mdash;': '—',
    '&ndash;': '–',
    '&hellip;': '…',
  };
  named.forEach((String k, String v) => out = out.replaceAll(k, v));
  out = out.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
      (Match m) => String.fromCharCode(int.parse(m[1]!, radix: 16)));
  out = out.replaceAllMapped(
      RegExp(r'&#(\d+);'), (Match m) => String.fromCharCode(int.parse(m[1]!)));
  return out.replaceAll('&amp;', '&');
}

/// A news failure. Separate from `RemoteFailure` because it is never shown to
/// the reader on its own — it becomes a tool result the model reads.
class NewsFailure implements Exception {
  const NewsFailure(this.message);
  final String message;
  @override
  String toString() => 'NewsFailure($message)';
}
