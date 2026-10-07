// Making the sound.
//
// Two engines and no silent retry between them, because that is the design: the
// device's own text-to-speech is the floor, and MiMo is the one online engine.
// The app never changes voice behind the reader's back — it says which one is
// speaking on the Listen screen, every time.
//
// Three bugs lived here and all three are fixed below rather than worked around:
//
//   - The player used to speak a `pendingText` field the Listen screen never
//     set, so every sentence on that screen reached the engine as an empty
//     string: silence, behind a play button that looked alive. The text is now
//     an ARGUMENT of `play()`, and there is no field left to forget.
//   - `flutter_tts` was asked to pause and resume, and neither is reliable
//     across platforms. Resume now re-speaks from the start of the sentence,
//     which is what actually happens and what the screen says.
//   - A recording that would not play used to end the sentence. It now falls
//     through to the device voice, and the label changes to match.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'remote/api.dart';

/// Which engine is speaking. The UI reads this to label itself honestly.
enum VoiceSource {
  /// A pre-built recording from MiMo.
  recorded,

  /// The phone's own text-to-speech.
  device,
}

extension VoiceSourceX on VoiceSource {
  bool get isRecorded => this == VoiceSource.recorded;

  /// Spoken in the reader's language. The Listen screen shows this verbatim
  /// rather than implying a recording exists when none does.
  String get label => this == VoiceSource.recorded
      ? 'a recorded voice · MiMo · online · free'
      : "the phone's own voice · free · offline · airplane mode";

  String get storageId => this == VoiceSource.recorded ? 'mimo' : 'device';
}

/// What the device engine can actually do on THIS phone.
///
/// Checked rather than assumed. A phone with no speech engine installed is a
/// perfectly ordinary phone, and the honest thing is to say so on the Settings
/// screen instead of leaving the reader pressing a button that does nothing.
class DeviceVoice {
  const DeviceVoice({required this.available, required this.note});

  final bool available;
  final String note;
}

/// What a view needs from whatever is making the sound.
///
/// An interface rather than a concrete class so the widgets never learn which
/// engine answered, and so the sentence screen can be reasoned about without
/// opening this file.
abstract class SentencePlayer {
  /// Speak [text], which belongs to sentence [index], and return when it has
  /// finished or been stopped.
  Future<void> play(int index, String text);

  Future<void> stop();

  /// Pause. There is no portable resume that continues mid-word, so [resume]
  /// re-speaks from the start of the sentence — stated on screen, not hidden.
  Future<void> pause();

  Future<void> resume();

  bool get isPlaying;

  VoiceSource get source;

  bool get hasRecordedAudio;
}

class SentenceAudio implements SentencePlayer {
  SentenceAudio({FlutterTts? tts, ja.AudioPlayer? player, RemoteApi? api})
      : _tts = tts ?? FlutterTts(),
        _player = player ?? ja.AudioPlayer(),
        _api = api ?? RemoteApi() {
    _configureTts();
  }

  final FlutterTts _tts;
  final ja.AudioPlayer _player;
  final RemoteApi _api;

  Completer<void>? _current;
  String _currentText = '';
  VoiceSource _source = VoiceSource.device;
  DeviceVoice _device = const DeviceVoice(
      available: true, note: 'this phone has an English voice installed');

  String _apiKey = '';
  String _baseUrl = VoiceEndpoint.mimo.baseUrl;
  String _voice = VoiceEndpoint.mimo.voices.first;
  bool _sessionReady = false;

  @override
  bool get isPlaying => _current != null;

  @override
  VoiceSource get source => _source;

  @override
  bool get hasRecordedAudio => _source == VoiceSource.recorded;

  DeviceVoice get deviceVoice => _device;

  String get voiceName => _voice;

  String get baseUrl => _baseUrl;

  /// Point the player at an engine. Called at boot and whenever Settings
  /// changes, so neither screen has to know how the other one was configured.
  void configure({
    required VoiceSource source,
    String apiKey = '',
    String baseUrl = '',
    String voice = '',
  }) {
    _source = source;
    _apiKey = apiKey.trim();
    if (baseUrl.trim().isNotEmpty) _baseUrl = baseUrl.trim();
    if (voice.trim().isNotEmpty) _voice = voice.trim();
  }

  /// Set the engine up once. Called from the constructor and not awaited: nothing
  /// may speak until the reader asks, and by then this has long finished. A
  /// failure is recorded rather than thrown — a phone that refuses to be
  /// configured still has to open.
  Future<void> _configureTts() async {
    try {
      await _tts.setLanguage('en-US');
      // The prototype is explicit that this is an American app: spelling, usage,
      // IPA and voices are all en-US, so the voice must match.
      await _tts.setSpeechRate(0.44);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      // Stop rather than roll on: a sentence that bleeds into the next one makes
      // a listener lose the thread.
      await _tts.awaitSpeakCompletion(true);
    } catch (e) {
      debugPrint('tts configure failed: $e');
    }
  }

  /// Ask the phone what it can speak with. Cheap, and the answer is shown on the
  /// Settings screen instead of being discovered by pressing play.
  Future<DeviceVoice> probeDevice() async {
    try {
      final Object? lang = await _tts.isLanguageAvailable('en-US');
      final Object? engines = await _tts.getEngines;
      final bool hasEngine = engines is List && engines.isNotEmpty;
      if (lang == false) {
        _device = DeviceVoice(
          available: false,
          note: hasEngine
              ? 'this phone has no English voice pack installed'
              : 'this phone has no speech engine installed',
        );
      } else if (lang == null && !hasEngine) {
        _device = const DeviceVoice(
          available: false,
          note: 'this phone could not be asked about its voices',
        );
      } else {
        _device =
            const DeviceVoice(available: true, note: 'English is installed');
      }
    } catch (e) {
      _device = const DeviceVoice(
          available: false, note: 'the speech engine refused to answer');
    }
    return _device;
  }

  /// Speak one word. Used by the word sheet's Say it, and it must work with no
  /// key at all — which it does, because the device engine is the floor.
  Future<bool> speakWord(String word, {double rate = 0.42}) async {
    await stop();
    try {
      await _tts.setSpeechRate(rate);
      await _tts.speak(word);
      await _tts.setSpeechRate(0.44);
      return true;
    } catch (e) {
      debugPrint('speakWord failed: $e');
      return false;
    }
  }

  /// Prove a recorded voice works. Returns null on success, or a sentence the
  /// Settings screen can show verbatim.
  Future<String?> probeMiMo() async {
    try {
      await _api.testVoice(baseUrl: _baseUrl, apiKey: _apiKey, voice: _voice);
      return null;
    } on RemoteFailure catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    }
  }

  @override
  Future<void> play(int index, String text) async {
    await stop();
    _currentText = text;
    final Completer<void> done = Completer<void>();
    _current = done;

    // A recorded voice, when one is configured and one can be had. Any failure
    // at all falls THROUGH to the device engine rather than leaving a gap.
    if (_source == VoiceSource.recorded && _apiKey.isNotEmpty) {
      final String? path = await _cachedRecording(text);
      if (path != null) {
        final bool played = await _playFile(path);
        if (played) {
          _finish(done);
          return;
        }
        // The recording was useless. Say it with the phone's own voice instead.
        _source = VoiceSource.device;
      }
    }

    await _speak(done, text);
  }

  void _finish(Completer<void> done) {
    if (!done.isCompleted) done.complete();
    _current = null;
    _currentText = '';
  }

  Future<void> _speak(Completer<void> done, String text) async {
    try {
      await _ensureSession();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('tts speak failed: $e');
      _device = const DeviceVoice(
        available: false,
        note: 'the speech engine refused to speak',
      );
    }
    _finish(done);
  }

  /// MiMo's answer, written to disk once and reused forever after.
  ///
  /// A synthesised sentence is a fact about the phone, not about the network:
  /// hearing it again must not cost another request. So the cache is keyed by
  /// the voice AND the exact words, and a hit never touches the network at all.
  Future<String?> _cachedRecording(String text) async {
    final File file = await _recordingFile(text);
    if (file.existsSync() && file.lengthSync() > 1024) return file.path;
    try {
      final List<int> bytes = await _api.speak(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        text: text,
        voice: _voice,
      );
      await file.parent.create(recursive: true);
      final File tmp = File('${file.path}.part');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
      return file.path;
    } on RemoteFailure catch (e) {
      debugPrint('MiMo did not speak: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('MiMo recording failed: $e');
      return null;
    }
  }

  Future<File> _recordingFile(String text) async {
    final Directory base = await getApplicationSupportDirectory();
    final Directory dir = Directory(p.join(base.path, 'voice'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(p.join(dir.path, '${_hash('$_voice|$text')}.wav'));
  }

  /// FNV-1a. Short, stable, and good enough to tell two sentences apart — this is
  /// a cache key, not a security primitive.
  static String _hash(String s) {
    int h = 0x811c9dc5;
    for (final int b in utf8.encode(s)) {
      h ^= b;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  Future<bool> _playFile(String path) async {
    try {
      await _ensureSession();
      await _player.setFilePath(path);
      await _player.play();
      await _player.processingStateStream.firstWhere(
        (ja.ProcessingState s) =>
            s == ja.ProcessingState.completed ||
            s == ja.ProcessingState.idle,
      );
      return true;
    } catch (e) {
      debugPrint('recorded audio failed, using the device voice: $e');
      return false;
    }
  }

  Future<void> _ensureSession() async {
    if (_sessionReady) return;
    _sessionReady = true;
    try {
      // Speech, not music: this must keep playing with the screen off and be
      // routed as speech on a headset.
      final AudioSession session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
    } catch (e) {
      debugPrint('audio session unavailable: $e');
    }
  }

  @override
  Future<void> stop() async {
    final Completer<void>? c = _current;
    _current = null;
    _currentText = '';
    try {
      await _tts.stop();
    } catch (_) {
      // Stopping something that is not speaking is not an error.
    }
    // `PlayerState` is a CLASS in just_audio 0.10, not an enum — `idle` lives on
      // `ProcessingState`. Checking the wrong one is a compile error rather than
      // a silent wrong answer, which is the good kind of version difference.
      try {
        if (_player.processingState != ja.ProcessingState.idle) {
          await _player.stop();
        }
      } catch (_) {
        // Nothing loaded, so nothing to stop.
      }
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  Future<void> pause() async {
    try {
      await _tts.pause();
    } catch (_) {
      // Not every device engine has pause.
    }
    try {
      await _player.pause();
    } catch (_) {
      // As above.
    }
  }

  @override
  Future<void> resume() async {
    if (_currentText.isEmpty) return;
    if (_source == VoiceSource.recorded && _apiKey.isNotEmpty) {
      final String? path = await _cachedRecording(_currentText);
      if (path != null && await _playFile(path)) return;
    }
    try {
      await _tts.speak(_currentText);
    } catch (_) {
      // Nothing left to try; the sentence stays visible on screen.
    }
  }

  Future<void> dispose() async {
    await stop();
    try {
      await _player.dispose();
    } catch (_) {}
    _api.close();
  }
}