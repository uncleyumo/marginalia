// The only network calls this app makes, and both of them are optional.
//
// There is no lookup endpoint. A word is answered from the bundled dictionary,
// always, for free — that promise is the product. The two calls below exist for
// the two things the phone genuinely cannot do on its own:
//
//   1. WRITING an article from the reader's plan. One call, ~$0.002, reachable
//      only by tapping Write it.
//   2. SPEAKING an article in a recorded voice. MiMo's TTS, free, and only
//      consulted when a key is present.
//
// Both are OpenAI-shaped `POST {base}/chat/completions`, which is why there is
// one client and three configurations rather than three clients. A key is sent
// as a bearer token to the address the reader typed, and to nowhere else.

import 'dart:convert';

import 'package:http/http.dart' as http;

/// A failure a reader can be told about in one sentence.
///
/// Every network error in this app arrives here rather than as a raw exception:
/// "your key was refused" and "there is no network" are different problems with
/// different fixes, and an app that reports them the same way is an app that
/// cannot help.
class RemoteFailure implements Exception {
  const RemoteFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One writing endpoint. A provider is a base URL, a model id and a price — and
/// that is the whole list, because switching between them must rewrite nothing.
class WriterEndpoint {
  const WriterEndpoint({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.costLine,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String model;

  /// Shown on the card BEFORE anything is spent. A price that appears after the
  /// call is an invoice, not a price.
  final String costLine;

  static const WriterEndpoint deepseek = WriterEndpoint(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    model: 'deepseek-chat',
    costLine: 'deepseek-chat · cheapest · ~\$0.002 an article',
  );

  static const WriterEndpoint openai = WriterEndpoint(
    id: 'openai',
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4o-mini',
    costLine: 'gpt-4o-mini · ~\$0.01 an article',
  );

  // `mimo-v2.5` is withdrawn on 2026-10-21, and a withdrawn model id is a 404
  // rather than a warning. v2.6-flash is the current replacement on the same
  // endpoint and the same request shape; nothing else here changes.
  static const WriterEndpoint mimo = WriterEndpoint(
    id: 'mimo',
    name: 'Xiaomi MiMo',
    baseUrl: 'https://api.xiaomimimo.com/v1',
    model: 'mimo-v2.6-flash',
    costLine: 'mimo-v2.6-flash · ~\$0.001 an article',
  );

  static const List<WriterEndpoint> all = <WriterEndpoint>[
    deepseek,
    openai,
    mimo,
  ];

  static WriterEndpoint byId(String id) => all.firstWhere(
        (WriterEndpoint e) => e.id == id,
        orElse: () => deepseek,
      );
}

/// The voice endpoint. There is exactly ONE online engine, deliberately: an app
/// that quietly changes voices is harder to trust than one that says which
/// voice you are hearing. MiMo publishes no voice list to fetch, so the
/// built-in names are stated here and each one is proven by asking it for a
/// word.
class VoiceEndpoint {
  const VoiceEndpoint({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.costLine,
    required this.voices,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String model;
  final String costLine;
  final List<String> voices;

  static const VoiceEndpoint mimo = VoiceEndpoint(
    id: 'mimo',
    name: 'Xiaomi MiMo',
    baseUrl: 'https://api.xiaomimimo.com/v1',
    model: 'mimo-v2.5-tts',
    costLine: 'reads the article aloud in a recorded voice · online · free',
    // The five the API actually answers to. `audio.voice` takes an ID, not a
    // name, and this list used to carry the four Chinese voices as TRANSLATED
    // names — `Ice Sugar`, `Jasmine`, `Soda`, `Birch` for 冰糖, 茉莉, 苏打, 白桦.
    // Those strings are not IDs, so picking one produced a rejected request and
    // a voice that could not be configured, which is the shape the bug report
    // had. They are also the wrong tool for this app: the articles are English
    // and DESIGN pins the voice to en-US, so a zh-CN voice has nothing to read
    // here. Removed rather than repaired.
    voices: <String>[
      'mimo_default',
      'Mia',
      'Chloe',
      'Milo',
      'Dean',
    ],
  );
}

/// The instruction sent with every synthesis. A recorded voice with no
/// direction reads like a radio advert; one sentence of direction is the
/// difference between a recording and a narrator.
const String kNarratorInstruction =
    'A calm adult narrator reading an English article aloud for someone '
    'studying English. Clear, unhurried, neutral accent, natural phrasing.';

/// The HTTP client. Thin on purpose: an interceptor stack would be machinery
/// without a job when there are two request shapes.
class RemoteApi {
  RemoteApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _writeTimeout = Duration(seconds: 60);
  static const Duration _speakTimeout = Duration(seconds: 45);

  /// One writing call. Returns the assistant's text, which is JSON because the
  /// prompt asks for JSON and the parser refuses anything else.
  Future<String> write({
    required WriterEndpoint endpoint,
    required String apiKey,
    required String system,
    required String user,
  }) async {
    final http.Response res = await _post(
      url: '${endpoint.baseUrl}/chat/completions',
      apiKey: apiKey,
      body: <String, Object?>{
        'model': endpoint.model,
        'messages': <Map<String, String>>[
          <String, String>{'role': 'system', 'content': system},
          <String, String>{'role': 'user', 'content': user},
        ],
        'temperature': 0.4,
        'response_format': <String, Object?>{'type': 'json_object'},
      },
      timeout: _writeTimeout,
      what: 'write an article',
    );
    return _text(res, what: 'write an article');
  }

  /// The cheapest possible round trip, used by Settings → Test.
  ///
  /// It asks for four characters and nothing else. A Test button that writes a
  /// whole article to prove a key works would spend money to answer a question
  /// a four-character request answers.
  Future<String> testWriter({
    required WriterEndpoint endpoint,
    required String apiKey,
  }) async {
    final String out = await write(
      endpoint: endpoint,
      apiKey: apiKey,
      system: 'Reply with JSON only.',
      user: 'Return exactly this JSON and nothing else: {"ok":true}',
    );
    return out;
  }

  /// Synthesise one sentence into WAV bytes.
  ///
  /// MiMo's rule, and it is a strange one: the text to be SPOKEN goes in the
  /// `assistant` message, and the `user` message is the direction. Putting the
  /// text in `user` produces a model that talks about the sentence instead of
  /// reading it.
  Future<List<int>> speak({
    required String baseUrl,
    required String apiKey,
    required String text,
    required String voice,
    String instruction = kNarratorInstruction,
  }) async {
    final http.Response res = await _post(
      url: '$baseUrl/chat/completions',
      apiKey: apiKey,
      body: <String, Object?>{
        'model': VoiceEndpoint.mimo.model,
        'messages': <Map<String, String>>[
          <String, String>{'role': 'user', 'content': instruction},
          <String, String>{'role': 'assistant', 'content': text},
        ],
        'audio': <String, Object?>{'format': 'wav', 'voice': voice},
      },
      timeout: _speakTimeout,
      what: 'speak a sentence',
    );

    final Map<String, dynamic> body = _object(res, what: 'speak a sentence');
    final Object? choices = body['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const RemoteFailure('MiMo returned no audio. Nothing was spoken.');
    }
    final Object? first = choices.first;
    if (first is! Map) {
      throw const RemoteFailure('MiMo returned an audio block nobody can read.');
    }
    final Object? message = first['message'];
    if (message is! Map) {
      throw const RemoteFailure('MiMo returned no message with the audio in it.');
    }
    final Object? audio = message['audio'];
    if (audio is! Map || audio['data'] is! String) {
      throw const RemoteFailure(
          'MiMo accepted the key but sent no audio. The voice name may be wrong.');
    }
    try {
      return base64Decode(audio['data']! as String);
    } catch (_) {
      throw const RemoteFailure('The audio arrived damaged and was discarded.');
    }
  }

  /// Prove a voice works by asking it for one word.
  Future<void> testVoice({
    required String baseUrl,
    required String apiKey,
    required String voice,
  }) async {
    await speak(
      baseUrl: baseUrl,
      apiKey: apiKey,
      text: 'Marginalia.',
      voice: voice,
    );
  }

  Future<http.Response> _post({
    required String url,
    required String apiKey,
    required Map<String, Object?> body,
    required Duration timeout,
    required String what,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const RemoteFailure('No key is saved, so nothing was sent.');
    }
    http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(url),
            headers: <String, String>{
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on RemoteFailure {
      rethrow;
    } catch (e) {
      throw RemoteFailure(
          'Could not reach $url — ${_short(e)}. Nothing was sent and nothing '
          'was spent.');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return res;
    throw RemoteFailure(_explain(res, what));
  }

  /// Turn an HTTP status into a sentence a reader can act on.
  String _explain(http.Response res, String what) {
    final String raw = res.body;
    final String detail = _errorDetail(raw);
    switch (res.statusCode) {
      case 401:
      case 403:
        return 'The key was refused ($what). Check it and save it again.';
      case 404:
        return 'That address has no $what endpoint ($what). Check the base URL.';
      case 429:
        return 'The provider is rate-limiting this phone. Try again shortly.';
      case >= 500:
        return 'The provider is having a bad minute ($what). Try again shortly.';
      default:
        return detail.isEmpty
            ? 'The request failed with ${res.statusCode}.'
            : detail;
    }
  }

  /// Pull the provider's own message out of the body, when there is one. DeepSeek
  /// and OpenAI both put it at `error.message`; MiMo uses the same shape.
  String _errorDetail(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) {
        final Object? err = decoded['error'];
        if (err is Map && err['message'] is String) {
          return '${err['message']}';
        }
      }
    } catch (_) {
      // Not json. The status code has already been explained.
    }
    return raw.length <= 160 ? raw : '${raw.substring(0, 160)}…';
  }

  String _text(http.Response res, {required String what}) {
    final Map<String, dynamic> body = _object(res, what: what);
    final Object? choices = body['choices'];
    if (choices is! List || choices.isEmpty) {
      throw RemoteFailure('The provider answered, but with nothing to $what.');
    }
    final Object? first = choices.first;
    if (first is! Map) return '';
    final Object? message = first['message'];
    if (message is! Map) return '';
    final Object? content = message['content'];
    return content is String ? content : '';
  }

  Map<String, dynamic> _object(http.Response res, {required String what}) {
    try {
      final Object? decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      throw RemoteFailure('The answer to "$what" was not json at all.');
    }
    throw RemoteFailure('The answer to "$what" was empty.');
  }

  static String _short(Object e) {
    final String s = '$e';
    return s.length <= 90 ? s : '${s.substring(0, 90)}…';
  }

  void close() => _client.close();
}